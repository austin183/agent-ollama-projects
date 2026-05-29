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
    private var panelPreviewTask: Task<Void, Never>?
    private var backgroundTask: Task<Void, Never>?
    private var titleTask: Task<Void, Never>?

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
        let assembler = self.assembler

        previewTask?.cancel()
        previewTask = Task { [weak self, assembler, config, cgImages, backgroundImage, previewSize] in
            guard let self else { return }
            let result = await Task.detached {
                assembler.assemblePreviewWithCGImages(
                    config: config,
                    cgImages: cgImages,
                    backgroundImage: backgroundImage,
                    previewSize: previewSize
                )
            }.value
            self.previewImage = result
        }
    }

    func updateBackground(
        config: BackgroundConfig,
        canvasSize: CGSize,
        backgroundImage: CGImage?,
        previewSize: CGSize
    ) {
        let assembler = self.assembler

        backgroundTask?.cancel()
        backgroundTask = Task { [weak self, assembler, config, canvasSize, backgroundImage, previewSize] in
            guard let self else { return }
            let result = await Task.detached {
                assembler.renderBackground(
                    config: config,
                    canvasSize: canvasSize,
                    backgroundImage: backgroundImage,
                    previewSize: previewSize
                )
            }.value
            self.previewBackgroundImage = result
        }
    }

    func updatePanelPreview(
        crop: CropInfo,
        cgImage: CGImage,
        panelSize: CGSize,
        panelId: UUID
    ) {
        let assembler = self.assembler

        panelPreviewTask?.cancel()
        panelPreviewTask = Task { [weak self, assembler, crop, cgImage, panelSize, panelId] in
            guard let self else { return }
            let result = await Task.detached {
                assembler.renderPanel(
                    crop: crop,
                    cgImage: cgImage,
                    panelSize: panelSize
                )
            }.value
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
                panelId: panel.id
            )
        }
    }

    func updateTitleImage(
        titleAttrString: NSAttributedString,
        titleStyle: TitleStyle,
        canvasSize: CGSize
    ) {
        let assembler = self.assembler

        titleTask?.cancel()
        titleTask = Task { [weak self, assembler, titleAttrString, titleStyle, canvasSize] in
            guard let self else { return }
            let result = await Task.detached {
                assembler.renderTitle(
                    titleAttrString: titleAttrString,
                    titleStyle: titleStyle,
                    canvasSize: canvasSize
                )
            }.value
            self.titleImage = result
        }
    }

    func clearAll() {
        previewTask?.cancel()
        previewDebounceTask?.cancel()
        panelPreviewTask?.cancel()
        backgroundTask?.cancel()
        titleTask?.cancel()
        previewTask = nil
        previewDebounceTask = nil
        panelPreviewTask = nil
        backgroundTask = nil
        titleTask = nil
        previewImage = nil
        previewBackgroundImage = nil
        panelRenderedImages.removeAll()
        titleImage = nil
    }

    func cancelAll() {
        previewTask?.cancel()
        previewDebounceTask?.cancel()
        panelPreviewTask?.cancel()
        backgroundTask?.cancel()
        titleTask?.cancel()
        previewTask = nil
        previewDebounceTask = nil
        panelPreviewTask = nil
        backgroundTask = nil
        titleTask = nil
    }
}
