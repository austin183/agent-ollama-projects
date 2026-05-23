import AppKit
import CoreGraphics
import Foundation

@MainActor
final class CropManager {
    var cropMap: [UUID: CropInfo] = [:]

    private var gestureActivePanelId: UUID?
    private var gestureBaseOrigin: CGPoint?
    private var gestureBaseZoom: CGFloat?
    private var panDelta: CGSize = .zero
    private var zoomDelta: CGFloat = 1.0

    var cropsArray: [CropInfo] {
        Array(cropMap.values).sorted { $0.destinationRect.origin.y < $1.destinationRect.origin.y }
    }

    func computeInitialCrops(panels: [ImagePanel], images: [ImageItem]) {
        cropMap.removeAll()
        for panel in panels {
            guard panel.imageIndex < images.count else { continue }
            let image = images[panel.imageIndex]
            let panelSize = panel.frame.size
            let cropRect = computeBestFitSource(imageSize: image.size, panelSize: panelSize)
            cropMap[panel.id] = CropInfo(
                panelId: panel.id,
                sourceRect: cropRect,
                destinationRect: panel.frame
            )
        }
    }

    func computeCropsFromSaliency(
        panels: [ImagePanel],
        images: [ImageItem],
        results: [Int: SaliencyResult]
    ) {
        cropMap.removeAll()
        for panel in panels {
            guard panel.imageIndex < images.count else { continue }
            let image = images[panel.imageIndex]
            let panelSize = panel.frame.size
            let saliency = results[panel.imageIndex]

            var sourceRect: CGRect
            if let sal = saliency {
                let origin = sal.cropOrigin(for: image.size, cropSize: panelSize)
                sourceRect = CGRect(origin: origin, size: panelSize)
            } else {
                sourceRect = computeBestFitSource(imageSize: image.size, panelSize: panelSize)
            }

            cropMap[panel.id] = CropInfo(
                panelId: panel.id,
                sourceRect: sourceRect,
                destinationRect: panel.frame
            )
        }
    }

    func beginPan(panelId: UUID) {
        guard let crop = cropMap[panelId] else { return }
        gestureActivePanelId = panelId
        gestureBaseOrigin = crop.sourceRect.origin
        gestureBaseZoom = currentZoom(for: panelId)
        panDelta = .zero
        zoomDelta = 1.0
    }

    func pan(by delta: CGSize) {
        panDelta = delta
    }

    func applyPan(panelId: UUID?, panels: [ImagePanel], images: [ImageItem], panelAssignments: [UUID: Int] = [:], finish: Bool = true) {
        let id = panelId ?? gestureActivePanelId
        guard
            let id,
            let crop = cropMap[id],
            let panel = panels.first(where: { $0.id == id }),
            let baseOrigin = gestureBaseOrigin
        else {
            if finish { endGesture() }
            return
        }

        let imageIndex = panelAssignments[id] ?? panel.imageIndex
        guard imageIndex < images.count else {
            if finish { endGesture() }
            return
        }

        let image = images[imageIndex]
        let panelSize = crop.destinationRect.size
        let zoom = gestureBaseZoom ?? 1.0
        let scaledW = panelSize.width * zoom
        let scaledH = panelSize.height * zoom
        let maxOX = max(0, image.size.width - scaledW)
        let maxOY = max(0, image.size.height - scaledH)

        let newOX = clamp(baseOrigin.x - panDelta.width, min: 0, max: maxOX)
        let newOY = clamp(baseOrigin.y - panDelta.height, min: 0, max: maxOY)

        cropMap[id] = CropInfo(
            panelId: id,
            sourceRect: CGRect(x: newOX, y: newOY, width: scaledW, height: scaledH),
            destinationRect: crop.destinationRect
        )

        if finish { endGesture() }
    }

    func beginPinch(panelId: UUID) {
        gestureActivePanelId = panelId
        gestureBaseZoom = currentZoom(for: panelId)
        zoomDelta = 1.0
        panDelta = .zero
    }

    func pinch(magnification: CGFloat) {
        zoomDelta = magnification
    }

    func applyPinch(panelId: UUID?, panels: [ImagePanel], images: [ImageItem], panelAssignments: [UUID: Int] = [:], finish: Bool = true) {
        let id = panelId ?? gestureActivePanelId
        guard
            let id,
            let crop = cropMap[id],
            let panel = panels.first(where: { $0.id == id }),
            let baseZoom = gestureBaseZoom
        else {
            if finish { endGesture() }
            return
        }

        let imageIndex = panelAssignments[id] ?? panel.imageIndex
        guard imageIndex < images.count else {
            if finish { endGesture() }
            return
        }

        let image = images[imageIndex]
        let panelSize = crop.destinationRect.size
        let newZoom = clamp(baseZoom / zoomDelta, min: 0.5, max: 3.0)
        let scaledW = panelSize.width * newZoom
        let scaledH = panelSize.height * newZoom

        let currentCenterX = crop.sourceRect.midX
        let currentCenterY = crop.sourceRect.midY

        let maxOX = max(0, image.size.width - scaledW)
        let maxOY = max(0, image.size.height - scaledH)

        let newOX = clamp(currentCenterX - scaledW / 2, min: 0, max: maxOX)
        let newOY = clamp(currentCenterY - scaledH / 2, min: 0, max: maxOY)

        cropMap[id] = CropInfo(
            panelId: id,
            sourceRect: CGRect(x: newOX, y: newOY, width: scaledW, height: scaledH),
            destinationRect: crop.destinationRect
        )

        if finish { endGesture() }
    }

    func resetCrop(panelId: UUID, panels: [ImagePanel], images: [ImageItem], panelAssignments: [UUID: Int] = [:]) {
        guard let panel = panels.first(where: { $0.id == panelId }) else { return }

        let imageIndex = panelAssignments[panelId] ?? panel.imageIndex
        guard imageIndex < images.count else { return }

        let image = images[imageIndex]
        let panelSize = panel.frame.size
        let cropRect = computeBestFitSource(imageSize: image.size, panelSize: panelSize)

        cropMap[panelId] = CropInfo(
            panelId: panelId,
            sourceRect: cropRect,
            destinationRect: panel.frame
        )
    }

    func resetAllCrops(panels: [ImagePanel], images: [ImageItem]) {
        computeInitialCrops(panels: panels, images: images)
    }

    // MARK: - Coordinate Conversion (Static)

    static func canvasToPreviewFrame(_ canvasRect: CGRect, in previewSize: CGSize) -> CGRect {
        let canvasSize = CanvasConfig.defaultCanvasSize
        return CoordinateConverter.canvasToPreviewFrame(canvasRect, in: previewSize, canvasSize: canvasSize)
    }

    static func sourceRectInContainer(_ crop: CropInfo, imageSize: CGSize, container: CGSize) -> CGRect {
        CoordinateConverter.sourceRectInContainer(crop, imageSize: imageSize, container: container)
    }

    static func hitTestPanel(at location: CGPoint, panelFrames: [UUID: CGRect]) -> UUID? {
        for (id, frame) in panelFrames where frame.contains(location) {
            return id
        }
        return nil
    }

    static func translateZoom(magnification: CGFloat, baseZoom: CGFloat) -> CGFloat {
        let newZoom = baseZoom / magnification
        return Swift.max(0.5, Swift.min(3.0, newZoom))
    }

    static func screenToCanvasPoint(_ screenPoint: CGPoint, in previewSize: CGSize) -> CGPoint {
        let canvasSize = CanvasConfig.defaultCanvasSize
        let canvasAspect = canvasSize.width / canvasSize.height
        let previewAspect = previewSize.width / previewSize.height

        var fittedSize: CGSize
        if canvasAspect > previewAspect {
            fittedSize = CGSize(width: previewSize.width, height: previewSize.width / canvasAspect)
        } else {
            fittedSize = CGSize(width: previewSize.height * canvasAspect, height: previewSize.height)
        }

        let offsetX = (previewSize.width - fittedSize.width) / 2
        let offsetY = (previewSize.height - fittedSize.height) / 2

        let canvasX = (screenPoint.x - offsetX) / fittedSize.width * canvasSize.width
        let canvasY = canvasSize.height - (screenPoint.y - offsetY) / fittedSize.height * canvasSize.height

        return CGPoint(x: canvasX, y: canvasY)
    }

    private func currentZoom(for panelId: UUID) -> CGFloat {
        guard let crop = cropMap[panelId] else { return 1.0 }
        let panelSize = crop.destinationRect.size
        let sourceW = crop.sourceRect.width
        return sourceW / panelSize.width
    }

    private func computeBestFitSource(imageSize: CGSize, panelSize: CGSize) -> CGRect {
        let imageAspect = imageSize.width / imageSize.height
        let panelAspect = panelSize.width / panelSize.height

        var sourceW: CGFloat
        var sourceH: CGFloat

        if imageAspect > panelAspect {
            sourceH = imageSize.height
            sourceW = sourceH * panelAspect
        } else {
            sourceW = imageSize.width
            sourceH = sourceW / panelAspect
        }

        let originX = (imageSize.width - sourceW) / 2
        let originY = (imageSize.height - sourceH) / 2

        return CGRect(x: originX, y: originY, width: sourceW, height: sourceH)
    }

    private func endGesture() {
        gestureActivePanelId = nil
        gestureBaseOrigin = nil
        gestureBaseZoom = nil
        panDelta = .zero
        zoomDelta = 1.0
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        if max < min { return value }
        return Swift.max(min, Swift.min(max, value))
    }
}

struct CoordinateConverter {
    static func canvasToPreviewFrame(_ canvasRect: CGRect, in previewSize: CGSize, canvasSize: CGSize) -> CGRect {
        let canvasAspect = canvasSize.width / canvasSize.height
        let previewAspect = previewSize.width / previewSize.height

        var fittedSize: CGSize
        if canvasAspect > previewAspect {
            fittedSize = CGSize(width: previewSize.width, height: previewSize.width / canvasAspect)
        } else {
            fittedSize = CGSize(width: previewSize.height * canvasAspect, height: previewSize.height)
        }

        let offsetX = (previewSize.width - fittedSize.width) / 2
        let offsetY = (previewSize.height - fittedSize.height) / 2

        let flippedY = canvasSize.height - canvasRect.origin.y - canvasRect.height

        return CGRect(
            x: offsetX + canvasRect.origin.x / canvasSize.width * fittedSize.width,
            y: offsetY + flippedY / canvasSize.height * fittedSize.height,
            width: canvasRect.width / canvasSize.width * fittedSize.width,
            height: canvasRect.height / canvasSize.height * fittedSize.height
        )
    }

    static func sourceRectInContainer(_ crop: CropInfo, imageSize: CGSize, container: CGSize) -> CGRect {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = container.width / container.height

        let (fittedW, fittedH): (CGFloat, CGFloat)
        if imageAspect > containerAspect {
            fittedW = container.width
            fittedH = container.width / imageAspect
        } else {
            fittedH = container.height
            fittedW = container.height * imageAspect
        }

        let offsetX = (container.width - fittedW) / 2
        let offsetY = (container.height - fittedH) / 2

        return CGRect(
            x: offsetX + crop.sourceRect.origin.x / imageSize.width * fittedW,
            y: offsetY + crop.sourceRect.origin.y / imageSize.height * fittedH,
            width: crop.sourceRect.width / imageSize.width * fittedW,
            height: crop.sourceRect.height / imageSize.height * fittedH
        )
    }
}
