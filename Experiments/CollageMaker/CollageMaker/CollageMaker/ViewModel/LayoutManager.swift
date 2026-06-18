import AppKit
import Foundation
import OSLog

private let logger = Logger(
    subsystem: "austin183.indie.CollageMaker",
    category: "LayoutManager"
)

@MainActor
@Observable
final class LayoutManager {
    var layoutStyle: LayoutStyle = .hero
    var gutter: CGFloat = 0
    var diagonalSliceAngle: CGFloat = 45.0
    var hexagonalSpacing: CGFloat = 8.0

    var panels: [ImagePanel] = []
    var panelAssignments: [UUID: Int] = [:]

    /// Incremented whenever panels are regenerated. Used by the VM to invalidate
    /// cached derived values (e.g., panelFrames) without exposing LayoutManager internals.
    var layoutVersion: Int = 0

    // Double exposure
    var doubleExposureMaskImage: NSImage?
    var doubleExposureMaskImagePath: String?
    var doubleExposureMaskOpacity: CGFloat = 0.5

    func regenerateLayout(
        images: [ImageItem],
        customImageOrder: [Int],
        cropManager: CropManager,
        previewManager: PreviewManager,
        saliencyResults: [Int: SaliencyResult],
        preserveCrops: Bool
    ) {
        guard !images.isEmpty else { return }
        layoutVersion += 1

        var order = customImageOrder
        if order.isEmpty || order.count != images.count {
            order = Array(0..<images.count)
        }

        let oldCropsBySlot = preserveCrops ? cropManager.cropsBySlot(panels) : nil
        let oldRenderedBySlot = preserveCrops ? previewManager.panelRenderedImagesBySlot(panels) : nil

        panels = LayoutGenerator.generate(
            numImages: images.count,
            canvasSize: SizeConstants.defaultCanvasSize,
            gutter: gutter,
            style: layoutStyle,
            imageOrder: order,
            options: LayoutOptions(sliceAngle: diagonalSliceAngle, hexSpacing: hexagonalSpacing)
        )

        panelAssignments.removeAll()
        for (i, panel) in panels.enumerated() {
            panelAssignments[panel.id] = order[i]
        }

        if preserveCrops, let oldCropsBySlot, let oldRenderedBySlot {
            cropManager.applyCropsBySlot(oldCropsBySlot, panels: panels)
            previewManager.applyRenderedBySlot(oldRenderedBySlot, panels: panels)
        } else {
            previewManager.panelRenderedImages.removeAll()
            if saliencyResults.isEmpty {
                cropManager.computeInitialCrops(panels: panels, images: images)
            } else {
                cropManager.computeCropsFromSaliency(
                    panels: panels,
                    images: images,
                    results: saliencyResults
                )
            }
        }
    }

    func buildOverlayConfig() -> OverlayConfig? {
        guard layoutStyle == .doubleExposure,
              let maskImage = doubleExposureMaskImage,
              let cgImage = maskImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return OverlayConfig(
            maskImage: cgImage,
            opacity: doubleExposureMaskOpacity,
            blendMode: .multiply
        )
    }

    func reset() {
        layoutVersion += 1
        layoutStyle = .hero
        gutter = 0
        diagonalSliceAngle = 45.0
        hexagonalSpacing = 8.0
        panels.removeAll()
        panelAssignments.removeAll()
        doubleExposureMaskImage = nil
        doubleExposureMaskImagePath = nil
        doubleExposureMaskOpacity = 0.5
    }

    // MARK: - Setters with Side Effects

    func setLayoutStyle(_ style: LayoutStyle) -> LayoutStyle {
        let old = layoutStyle
        layoutStyle = style
        logger.info("Layout style changed to \(style.rawValue, privacy: .public)")
        return old
    }

    func setGutter(_ value: CGFloat) -> CGFloat {
        let old = gutter
        gutter = value
        return old
    }

    func setDiagonalSliceAngle(_ value: CGFloat) -> CGFloat {
        let old = diagonalSliceAngle
        diagonalSliceAngle = value
        return old
    }

    func setHexagonalSpacing(_ value: CGFloat) -> CGFloat {
        let old = hexagonalSpacing
        hexagonalSpacing = value
        return old
    }

    func setDoubleExposureMaskOpacity(_ value: CGFloat) -> CGFloat {
        let old = doubleExposureMaskOpacity
        doubleExposureMaskOpacity = value
        return old
    }

    func setMaskImage(_ image: NSImage?, path: String?) -> (NSImage?, String?) {
        let oldImage = doubleExposureMaskImage
        let oldPath = doubleExposureMaskImagePath
        doubleExposureMaskImagePath = path
        doubleExposureMaskImage = image
        if image == nil {
            doubleExposureMaskImagePath = nil
        }
        return (oldImage, oldPath)
    }
}
