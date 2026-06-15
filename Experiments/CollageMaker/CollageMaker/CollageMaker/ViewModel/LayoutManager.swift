import AppKit
import Foundation

@MainActor
@Observable
final class LayoutManager {
    var layoutStyle: LayoutStyle = .hero
    var gutter: CGFloat = 0
    var diagonalSliceAngle: CGFloat = 45.0
    var hexagonalSpacing: CGFloat = 8.0

    var panels: [ImagePanel] = []
    var panelAssignments: [UUID: Int] = [:]

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

    func buildLayoutConfig() -> LayoutConfig {
        LayoutConfig(
            panels: panels,
            crops: [:],
            panelAssignments: panelAssignments
        )
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
}
