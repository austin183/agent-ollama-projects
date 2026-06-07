import AppKit
import Foundation
import OSLog

private let logger = Logger(
    subsystem: "austin183.indie.CollageMaker",
    category: "PreviewManager"
)

@MainActor
@Observable
final class PreviewManager {
    var previewImage: NSImage?
    var previewBackgroundImage: NSImage?
    var panelRenderedImages: [UUID: NSImage] = [:]
    var titleImage: NSImage?

    private var previewTask: Task<Void, Never>?
    private var previewDebounceTask: Task<Void, Never>?
    private var panelPreviewTasks: [UUID: Task<Void, Never>] = [:]
    private var backgroundTask: Task<Void, Never>?
    private var titleTask: Task<Void, Never>?

    private var previewGeneration: Int = 0
    private var backgroundGeneration: Int = 0
    private var panelGenerations: [UUID: Int] = [:]
    private var titleGeneration: Int = 0

    private let assembler: CollageAssembly

    init(assembler: CollageAssembly) {
        self.assembler = assembler
    }

    func updatePreview(
        config: AssemblyConfig,
        cgImages: [CGImage],
        backgroundImage: CGImage?,
        previewSize: CGSize
    ) {
        previewGeneration += 1
        let gen = previewGeneration
        let assembler = self.assembler

        previewTask?.cancel()
        previewTask = Task { [weak self, assembler, config, cgImages, backgroundImage, previewSize] in
            guard let self else { return }
            let result = await assembler.assemblePreviewWithCGImages(
                config: config,
                cgImages: cgImages,
                backgroundImage: backgroundImage,
                previewSize: previewSize
            )
            guard gen == self.previewGeneration else { return }
            self.previewImage = result
        }
    }

    func updateBackground(
        config: BackgroundConfig,
        canvasSize: CGSize,
        backgroundImage: CGImage?,
        previewSize: CGSize
    ) {
        backgroundGeneration += 1
        let gen = backgroundGeneration
        let assembler = self.assembler

        backgroundTask?.cancel()
        backgroundTask = Task { [weak self, assembler, config, canvasSize, backgroundImage, previewSize] in
            guard let self else { return }
            let result = await assembler.renderBackground(
                config: config,
                canvasSize: canvasSize,
                backgroundImage: backgroundImage,
                previewSize: previewSize
            )
            guard gen == self.backgroundGeneration else { return }
            self.previewBackgroundImage = result
        }
    }

    func updatePanelPreview(
        crop: CropInfo,
        cgImage: CGImage,
        panelSize: CGSize,
        geometry: PanelGeometry,
        panelId: UUID
    ) {
        panelGenerations[panelId, default: 0] += 1
        let gen = panelGenerations[panelId]!
        let assembler = self.assembler

        panelPreviewTasks[panelId]?.cancel()
        panelPreviewTasks[panelId] = Task { [weak self, assembler, crop, cgImage, panelSize, geometry, panelId, gen] in
            guard let self, gen == self.panelGenerations[panelId] else { return }
            let result = await assembler.renderPanel(
                crop: crop,
                cgImage: cgImage,
                panelSize: panelSize,
                geometry: geometry
            )
            guard gen == self.panelGenerations[panelId] else { return }
            self.panelRenderedImages[panelId] = result
        }
    }

    func updateAllPanelPreviews(
        panels: [ImagePanel],
        crops: [UUID: CropInfo],
        images: [ImageItem],
        panelAssignments: [UUID: Int]
    ) {
        for panel in panels {
            let effectiveIndex = panelAssignments[panel.id] ?? panel.imageIndex
            guard effectiveIndex < images.count,
                  let crop = crops[panel.id] else { continue }
            let cgImage = images[effectiveIndex].cgImage
            updatePanelPreview(
                crop: crop,
                cgImage: cgImage,
                panelSize: panel.frame.size,
                geometry: panel.geometry,
                panelId: panel.id
            )
        }
    }

    func updateTitleImage(
        titleAttrString: NSAttributedString,
        titleStyle: TitleStyle,
        canvasSize: CGSize
    ) {
        let textData = TitleTextData.extract(from: titleAttrString)
        let fontColor = titleStyle.fontColor.cgColor
        let backgroundColor = titleStyle.backgroundColor.cgColor
        let titleConfig = TitleConfig(
            textData: textData,
            style: titleStyle,
            fontColor: fontColor,
            backgroundColor: backgroundColor
        )

        titleGeneration += 1
        let gen = titleGeneration
        let assembler = self.assembler

        titleTask?.cancel()
        titleTask = Task { [weak self, assembler, titleConfig, canvasSize] in
            guard let self else { return }
            let result = await assembler.renderTitle(
                titleConfig: titleConfig,
                canvasSize: canvasSize
            )
            guard gen == self.titleGeneration else { return }
            self.titleImage = result
        }
    }

    /// Extracts rendered images by slot index for preservation across layout changes.
    func panelRenderedImagesBySlot(_ panels: [ImagePanel]) -> [NSImage?] {
        panels.map { panelRenderedImages[$0.id] }
    }

    /// Applies previously extracted rendered images to new panels by slot index.
    func applyRenderedBySlot(_ images: [NSImage?], panels: [ImagePanel]) {
        panelRenderedImages.removeAll()
        for (index, panel) in panels.enumerated() {
            if index < images.count, let image = images[index] {
                panelRenderedImages[panel.id] = image
            }
        }
    }

    private func cancelAllTasks() {
        previewTask?.cancel()
        previewDebounceTask?.cancel()
        panelPreviewTasks.values.forEach { $0.cancel() }
        backgroundTask?.cancel()
        titleTask?.cancel()
        previewTask = nil
        previewDebounceTask = nil
        panelPreviewTasks.removeAll()
        backgroundTask = nil
        titleTask = nil
    }

    func clearAll() {
        cancelAllTasks()
        previewImage = nil
        previewBackgroundImage = nil
        panelRenderedImages.removeAll()
        titleImage = nil
        previewGeneration = 0
        backgroundGeneration = 0
        panelGenerations.removeAll()
        titleGeneration = 0
    }

    func cancelAll() {
        cancelAllTasks()
    }

    /// Yields to let pending async rendering tasks complete.
    /// Used by tests to synchronize with background work.
    func awaitPendingTasks() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
    }
}
