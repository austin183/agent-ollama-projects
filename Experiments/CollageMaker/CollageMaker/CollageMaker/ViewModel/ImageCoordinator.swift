import AppKit
import CoreGraphics
import Foundation
import OSLog

private let logger = Logger(
    subsystem: "austin183.indie.CollageMaker",
    category: "ImageCoordinator"
)

/// Snapshot of image-coordinator domain state for undo restoration.
struct ImageDomainState {
    let images: [ImageItem]
    let customImageOrder: [Int]
    let panels: [ImagePanel]
    let panelAssignments: [UUID: Int]
    let cropMap: [UUID: CropInfo]
    let cropVersions: [UUID: Int]
}

/// Snapshot of swap state for undo restoration.
struct SwapState {
    let customOrder: [Int]
    let sourceAssign: Int?
    let targetAssign: Int?
    let sourceCrop: CropInfo?
    let targetCrop: CropInfo?
}

/// Coordinates image loading, reordering, removal, panel assignment,
/// and saliency analysis. Returns data for undo; VM handles registration.
@MainActor
final class ImageCoordinator {
    var target: ImageCoordinationTarget!
    let imageLibrary: ImageLibraryManager
    let layoutManager: LayoutManager
    let cropManager: CropManager
    let previewManager: PreviewManager
    let undoManager: UndoManager
    private let saliencyAnalyzer: SaliencyAnalysis

    var saliencyResults: [Int: SaliencyResult] = [:]
    private var saliencyTask: Task<Void, Never>?

    init(
        imageLibrary: ImageLibraryManager,
        layoutManager: LayoutManager,
        cropManager: CropManager,
        previewManager: PreviewManager,
        undoManager: UndoManager,
        saliencyAnalyzer: SaliencyAnalysis
    ) {
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
        scheduleSaliencyAnalysis()
    }

    func removeImage(at index: Int) -> (item: ImageItem, at: Int)? {
        guard let (removed, at) = imageLibrary.removeImage(at: index) else { return nil }
        scheduleSaliencyAnalysis()
        return (removed, at)
    }

    func moveImages(from: IndexSet, to: Int) -> [Int] {
        let oldCustomOrder = imageLibrary.customImageOrder
        imageLibrary.moveImages(from: from, to: to)
        layoutManager.panelAssignments.removeAll()
        scheduleSaliencyAnalysis()
        return oldCustomOrder
    }

    private func scheduleSaliencyAnalysis() {
        guard !imageLibrary.images.isEmpty && !target.isProcessing else { return }
        saliencyTask?.cancel()
        saliencyTask = Task { [weak self] in
            await self?.analyzeSaliency()
        }
    }

    func cancelSaliencyTask() {
        saliencyTask?.cancel()
        saliencyTask = nil
    }

    func awaitPendingTasks() async {
        if let task = saliencyTask {
            await task.value
        }
    }

    func clearDomain() -> ImageDomainState {
        guard !imageLibrary.images.isEmpty else {
            return ImageDomainState(images: [], customImageOrder: [], panels: [], panelAssignments: [:], cropMap: [:], cropVersions: [:])
        }
        logger.info("Clear image domain")
        let oldPanels = layoutManager.panels
        let oldPanelAssignments = layoutManager.panelAssignments
        let oldCropMap = cropManager.cropMap
        let oldCropVersions = cropManager.cropVersions
        let oldCustomImageOrder = imageLibrary.customImageOrder
        let oldImages = imageLibrary.clearAll()
        saliencyResults.removeAll()
        return ImageDomainState(images: oldImages, customImageOrder: oldCustomImageOrder, panels: oldPanels, panelAssignments: oldPanelAssignments, cropMap: oldCropMap, cropVersions: oldCropVersions)
    }

    // MARK: - Panel Assignment

    func assignImage(_ imageIndex: Int, to panelId: UUID) {
        layoutManager.panelAssignments[panelId] = imageIndex
        target.resetCrop(panelId: panelId)
        target.updatePanelPreview(panelId: panelId)
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
            target.selectedPanelId = panel.id
        }
    }

    func swapPanelImages(sourceId: UUID, targetId: UUID) -> SwapState? {
        guard sourceId != targetId else { return nil }
        guard let sourceSlot = layoutManager.panels.firstIndex(where: { $0.id == sourceId }),
              let targetSlot = layoutManager.panels.firstIndex(where: { $0.id == targetId }) else { return nil }

        let state = SwapState(
            customOrder: imageLibrary.customImageOrder,
            sourceAssign: layoutManager.panelAssignments[sourceId],
            targetAssign: layoutManager.panelAssignments[targetId],
            sourceCrop: cropManager.cropMap[sourceId],
            targetCrop: cropManager.cropMap[targetId]
        )

        imageLibrary.customImageOrder.swapAt(sourceSlot, targetSlot)
        layoutManager.panelAssignments[sourceId] = imageLibrary.customImageOrder[sourceSlot]
        layoutManager.panelAssignments[targetId] = imageLibrary.customImageOrder[targetSlot]

        if let cropA = state.sourceCrop, let cropB = state.targetCrop {
            cropManager.cropMap[sourceId] = CropInfo(panelId: sourceId, sourceRect: cropB.sourceRect, destination: cropA.destination)
            cropManager.cropVersions[sourceId, default: 0] += 1
            cropManager.cropMap[targetId] = CropInfo(panelId: targetId, sourceRect: cropA.sourceRect, destination: cropB.destination)
            cropManager.cropVersions[targetId, default: 0] += 1
        }

        target.updatePanelPreview(panelId: sourceId)
        target.updatePanelPreview(panelId: targetId)
        return state
    }

    // MARK: - Saliency

    func analyzeSaliency() async {
        guard !imageLibrary.images.isEmpty else { return }
        logger.info("Saliency analysis started for \(self.imageLibrary.images.count) image(s)")
        target.beginProcessing()
        defer { target.endProcessing() }

        do {
            let cgImages = imageLibrary.images.map { $0.cgImage }
            let results = try await saliencyAnalyzer.analyzeAll(cgImages)
            guard !Task.isCancelled else {
                logger.info("Saliency analysis cancelled, discarding results")
                return
            }
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
            target.cancelDebouncer(id: "previewRender")
            target.updatePreview()
            target.updateAllPanelPreviews()
        } catch {
            logger.error("Saliency analysis failed: \(error.localizedDescription, privacy: .public)")
            target.errorMessage = error.localizedDescription
        }
    }
}
