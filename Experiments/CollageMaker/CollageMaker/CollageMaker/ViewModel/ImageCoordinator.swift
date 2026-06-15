import AppKit
import CoreGraphics
import Foundation
import OSLog

private let logger = Logger(
    subsystem: "austin183.indie.CollageMaker",
    category: "ImageCoordinator"
)

/// Coordinates image loading, reordering, removal, panel assignment,
/// and saliency analysis. Wraps ImageLibraryManager calls with undo
/// registration, layout regeneration, and preview updates.
@MainActor
final class ImageCoordinator {
    private let viewModel: CollageViewModel
    let imageLibrary: ImageLibraryManager
    let layoutManager: LayoutManager
    let cropManager: CropManager
    let previewManager: PreviewManager
    let undoManager: UndoManager
    private let saliencyAnalyzer: SaliencyAnalysis

    var saliencyResults: [Int: SaliencyResult] = [:]

    init(
        viewModel: CollageViewModel,
        imageLibrary: ImageLibraryManager,
        layoutManager: LayoutManager,
        cropManager: CropManager,
        previewManager: PreviewManager,
        undoManager: UndoManager,
        saliencyAnalyzer: SaliencyAnalysis
    ) {
        self.viewModel = viewModel
        self.imageLibrary = imageLibrary
        self.layoutManager = layoutManager
        self.cropManager = cropManager
        self.previewManager = previewManager
        self.undoManager = undoManager
        self.saliencyAnalyzer = saliencyAnalyzer
    }

    // MARK: - Image Operations

    func browseImages() {
        imageLibrary.browseImages()
    }

    func addImages(from urls: [URL]) async {
        await imageLibrary.addImages(from: urls)
        if !imageLibrary.images.isEmpty && !viewModel.isProcessing {
            Task { [weak self] in
                await self?.analyzeSaliency()
            }
        }
    }

    func removeImage(at index: Int) {
        guard let (removed, at) = imageLibrary.removeImage(at: index) else { return }
        undoManager.registerUndo(withTarget: viewModel) { target in
            target.imageLibrary.images.insert(removed, at: at)
            target.regenerateLayout()
        }
        undoManager.setActionName("Remove Image")

        Task { [weak self] in
            await self?.analyzeSaliency()
        }
    }

    func moveImages(from: IndexSet, to: Int) {
        let oldCustomOrder = imageLibrary.customImageOrder
        imageLibrary.moveImages(from: from, to: to)
        layoutManager.panelAssignments.removeAll()
        undoManager.registerUndo(withTarget: viewModel) { target in
            target.customImageOrder = oldCustomOrder
            target.regenerateLayout()
        }
        undoManager.setActionName("Reorder Images")

        Task { [weak self] in
            await self?.analyzeSaliency()
        }
    }

    func clearAll() {
        guard !imageLibrary.images.isEmpty else { return }
        logger.info("Clear all images")
        let oldPanels = layoutManager.panels
        let oldCropMap = cropManager.cropMap
        let oldImages = imageLibrary.clearAll()
        let oldBgImage = viewModel.backgroundManager.backgroundImage
        let oldBgImagePath = viewModel.backgroundManager.backgroundImagePath
        viewModel.backgroundManager.reset()
        viewModel.titleManager.reset()
        layoutManager.reset()
        undoManager.registerUndo(withTarget: viewModel) { target in
            target.imageLibrary.images = oldImages
            target.layoutManager.panels = oldPanels
            target.cropMap = oldCropMap
            target.backgroundManager.backgroundImage = oldBgImage
            target.backgroundManager.backgroundImagePath = oldBgImagePath
            target.regenerateLayout()
        }
        undoManager.setActionName("Clear All")
        viewModel.exportManager.exportTask?.cancel()
        cropManager.cropMap.removeAll()
        saliencyResults.removeAll()
        viewModel.selectedPanelId = nil
        previewManager.clearAll()
        viewModel.errorMessage = nil
    }

    // MARK: - Panel Assignment

    func assignImage(_ imageIndex: Int, to panelId: UUID) {
        layoutManager.panelAssignments[panelId] = imageIndex
        viewModel.resetCrop(panelId: panelId)
        viewModel.updatePanelPreview(panelId: panelId)
    }

    func getEffectiveImageIndex(for panelId: UUID) -> Int? {
        if let assigned = layoutManager.panelAssignments[panelId] {
            return assigned
        }
        guard let panelIndex = layoutManager.panels.firstIndex(where: { $0.id == panelId }) else { return nil }
        return panelIndex
    }

    func selectPanelForImage(at imageIndex: Int) {
        guard imageIndex < imageLibrary.images.count else { return }
        if let panel = layoutManager.panels.first(where: {
            layoutManager.panelAssignments[$0.id] == imageIndex || $0.imageIndex == imageIndex
        }) {
            viewModel.selectedPanelId = panel.id
        }
    }

    func swapPanelImages(sourceId: UUID, targetId: UUID) {
        guard sourceId != targetId else { return }
        guard let sourceSlot = layoutManager.panels.firstIndex(where: { $0.id == sourceId }),
              let targetSlot = layoutManager.panels.firstIndex(where: { $0.id == targetId }) else { return }
        let oldOrder = imageLibrary.customImageOrder
        undoManager.registerUndo(withTarget: viewModel) { target in
            target.customImageOrder = oldOrder
            target.regenerateLayout()
        }
        undoManager.setActionName("Swap Images")
        imageLibrary.customImageOrder.swapAt(sourceSlot, targetSlot)
        layoutManager.panelAssignments[sourceId] = imageLibrary.customImageOrder[sourceSlot]
        layoutManager.panelAssignments[targetId] = imageLibrary.customImageOrder[targetSlot]

        if let cropA = cropManager.cropMap[sourceId], let cropB = cropManager.cropMap[targetId] {
            cropManager.cropMap[sourceId] = CropInfo(panelId: sourceId, sourceRect: cropB.sourceRect, destination: cropA.destination)
            cropManager.cropMap[targetId] = CropInfo(panelId: targetId, sourceRect: cropA.sourceRect, destination: cropB.destination)
        }

        viewModel.updatePanelPreview(panelId: sourceId)
        viewModel.updatePanelPreview(panelId: targetId)
    }

    // MARK: - Saliency

    func analyzeSaliency() async {
        guard !imageLibrary.images.isEmpty else { return }
        logger.info("Saliency analysis started for \(self.imageLibrary.images.count) image(s)")
        viewModel.beginProcessing()
        defer { viewModel.endProcessing() }

        do {
            let cgImages = imageLibrary.images.map { $0.cgImage }
            let results = try await saliencyAnalyzer.analyzeAll(cgImages)
            var indexed: [Int: SaliencyResult] = [:]
            for (i, result) in results.enumerated() {
                indexed[i] = result
            }
            logger.info("Saliency analysis complete: \(indexed.count) result(s)")
            saliencyResults = indexed
            cropManager.computeCropsFromSaliency(
                panels: layoutManager.panels,
                images: imageLibrary.images,
                results: indexed
            )
            viewModel.debouncer.cancel(id: "previewRender")
            viewModel.updatePreview()
            viewModel.updateAllPanelPreviews()
        } catch {
            logger.error("Saliency analysis failed: \(error.localizedDescription, privacy: .public)")
            viewModel.errorMessage = error.localizedDescription
        }
    }
}
