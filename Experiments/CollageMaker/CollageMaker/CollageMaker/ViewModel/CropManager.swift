import AppKit
import CoreGraphics
import Foundation
import SwiftUI

@MainActor
final class CropManager {
    var cropMap: [UUID: CropInfo] = [:]

    private var gestureActivePanelId: UUID?
    private var gestureBaseOrigin: CGPoint?
    private var gestureBaseZoom: CGFloat?
    private var panDelta: CGSize = .zero
    private var zoomDelta: CGFloat = 1.0

    // Scroll pan state
    private var scrollPanPanelId: UUID?
    private var scrollPanAccumulator: CGSize = .zero

    var cropsArray: [CropInfo] {
        Array(cropMap.values).sorted { $0.destinationRect.origin.y < $1.destinationRect.origin.y }
    }

    var activePanelId: UUID? {
        scrollPanPanelId ?? gestureActivePanelId
    }

    // MARK: - Scroll Pan

    func beginScrollPan(panelId: UUID) {
        scrollPanPanelId = panelId
        scrollPanAccumulator = .zero
        beginPan(panelId: panelId)
    }

    func scrollPanAccumulateDelta(_ delta: CGSize, sensitivity: CGFloat) {
        guard scrollPanPanelId != nil else { return }
        scrollPanAccumulator.width += delta.width * sensitivity
        scrollPanAccumulator.height += delta.height * sensitivity
    }

    func scrollPanApply(panels: [ImagePanel], images: [ImageItem], panelAssignments: [UUID: Int] = [:], finish: Bool = true) {
        pan(by: scrollPanAccumulator)
        applyPan(panelId: nil, panels: panels, images: images, panelAssignments: panelAssignments, finish: finish)
    }

    func endScrollPan() {
        scrollPanPanelId = nil
        scrollPanAccumulator = .zero
        endGesture()
    }

    var scrollPanHasActivePan: Bool {
        scrollPanPanelId != nil
    }

    var scrollPanActivePanelId: UUID? {
        scrollPanPanelId
    }

    var scrollPanAccumulatorValue: CGSize {
        scrollPanAccumulator
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
                destination: panel.geometry
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
                destination: panel.geometry
            )
        }
    }

    /// Extracts sourceRect values by slot index for crop preservation across layout changes.
    func cropsBySlot(_ panels: [ImagePanel]) -> [CGRect] {
        panels.map { cropMap[$0.id]?.sourceRect ?? CGRect(origin: .zero, size: $0.frame.size) }
    }

    /// Applies previously extracted sourceRect values to new panels by slot index.
    func applyCropsBySlot(_ sourceRects: [CGRect], panels: [ImagePanel]) {
        cropMap.removeAll()
        for (index, panel) in panels.enumerated() {
            let sourceRect = index < sourceRects.count ? sourceRects[index] :
                CGRect(origin: .zero, size: panel.frame.size)
            cropMap[panel.id] = CropInfo(
                panelId: panel.id,
                sourceRect: sourceRect,
                destination: panel.geometry
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

        let visBounds = computeVisibleSourceBounds(destRect: crop.destinationRect, sourceW: scaledW, sourceH: scaledH)

        let effectiveBaseX = baseOrigin.x + visBounds.offsetX
        let effectiveBaseY = baseOrigin.y + visBounds.offsetY
        let maxEffX = max(0, image.size.width - visBounds.visibleW)
        let maxEffY = max(0, image.size.height - visBounds.visibleH)

        let newEffX = clamp(effectiveBaseX - panDelta.width, min: 0, max: maxEffX)
        let newEffY = clamp(effectiveBaseY - panDelta.height, min: 0, max: maxEffY)

        let newOX = newEffX - visBounds.offsetX
        let newOY = newEffY - visBounds.offsetY

        cropMap[id] = CropInfo(
            panelId: id,
            sourceRect: CGRect(x: newOX, y: newOY, width: scaledW, height: scaledH),
            destination: crop.destination
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

        let maxZoomOut = Swift.min(image.size.width / panelSize.width, image.size.height / panelSize.height)
        let newZoom = clamp(baseZoom / zoomDelta, min: 0.5, max: maxZoomOut)
        let scaledW = panelSize.width * newZoom
        let scaledH = panelSize.height * newZoom

        let visBounds = computeVisibleSourceBounds(destRect: crop.destinationRect, sourceW: scaledW, sourceH: scaledH)

        let currentCenterX = crop.sourceRect.midX
        let currentCenterY = crop.sourceRect.midY

        let maxOX = max(0, image.size.width - scaledW)
        let maxOY = max(0, image.size.height - scaledH)

        let newOX = clamp(currentCenterX - scaledW / 2, min: 0, max: maxOX)
        let newOY = clamp(currentCenterY - scaledH / 2, min: 0, max: maxOY)

        cropMap[id] = CropInfo(
            panelId: id,
            sourceRect: CGRect(x: newOX, y: newOY, width: scaledW, height: scaledH),
            destination: crop.destination
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
            destination: panel.geometry
        )
    }

    func resetAllCrops(panels: [ImagePanel], images: [ImageItem]) {
        computeInitialCrops(panels: panels, images: images)
    }

    // MARK: - Coordinate Conversion (Static)

    static func canvasToPreviewFrame(_ canvasRect: CGRect, in previewSize: CGSize) -> CGRect {
        let canvasSize = SizeConstants.defaultCanvasSize
        return CoordinateConverter.canvasToPreviewFrame(canvasRect, in: previewSize, canvasSize: canvasSize)
    }

    static func sourceRectInContainer(_ crop: CropInfo, imageSize: CGSize, container: CGSize) -> CGRect {
        CoordinateConverter.sourceRectInContainer(crop, imageSize: imageSize, container: container)
    }

    static func hitTestPanel(
        at location: CGPoint,
        panelFrames: [UUID: CGRect],
        panelGeometries: [UUID: PanelGeometry]? = nil,
        previewSize: CGSize
    ) -> UUID? {
        let candidates = panelFrames.filter { $0.value.contains(location) }
        guard !candidates.isEmpty else { return nil }

        if let geometries = panelGeometries {
            let canvasPoint = screenToCanvasPoint(location, in: previewSize)
            for (id, _) in candidates {
                guard let geometry = geometries[id] else { continue }
                switch geometry {
                case .rect:
                    return id
                case .path(let cgPath, _):
                    if cgPath.contains(canvasPoint) {
                        return id
                    }
                }
            }
            return nil
        }

        return candidates.first?.key
    }

    static func translateZoom(magnification: CGFloat, baseZoom: CGFloat, imageSize: CGSize, panelSize: CGSize) -> CGFloat {
        let newZoom = baseZoom / magnification
        let maxZoomOut = Swift.min(imageSize.width / panelSize.width, imageSize.height / panelSize.height)
        return Swift.max(0.5, Swift.min(maxZoomOut, newZoom))
    }

    static func screenToCanvasPoint(_ screenPoint: CGPoint, in previewSize: CGSize) -> CGPoint {
        let canvasSize = SizeConstants.defaultCanvasSize
        let (fittedSize, offset) = FitMath.fit(canvasSize, into: previewSize)

        let canvasX = (screenPoint.x - offset.x) / fittedSize.width * canvasSize.width
        let canvasY = canvasSize.height - (screenPoint.y - offset.y) / fittedSize.height * canvasSize.height

        return CGPoint(x: canvasX, y: canvasY)
    }

    private func currentZoom(for panelId: UUID) -> CGFloat {
        guard let crop = cropMap[panelId] else { return 1.0 }
        let panelSize = crop.destinationRect.size
        let sourceW = crop.sourceRect.width
        return sourceW / panelSize.width
    }

    private func computeBestFitSource(imageSize: CGSize, panelSize: CGSize) -> CGRect {
        FitMath.sourceRect(imageSize: imageSize, panelSize: panelSize)
    }

    struct VisibleSourceBounds {
        let offsetX: CGFloat
        let offsetY: CGFloat
        let visibleW: CGFloat
        let visibleH: CGFloat
    }

    private func computeVisibleSourceBounds(destRect: CGRect, sourceW: CGFloat, sourceH: CGFloat) -> VisibleSourceBounds {
        let canvasSize = SizeConstants.defaultCanvasSize
        let visMinX = Swift.max(0, destRect.minX)
        let visMaxX = Swift.min(canvasSize.width, destRect.maxX)
        let visMinY = Swift.max(0, destRect.minY)
        let visMaxY = Swift.min(canvasSize.height, destRect.maxY)
        let offCanvasLeft = Swift.max(0, -destRect.minX)
        let offCanvasTop = Swift.max(0, -destRect.minY)
        let dw = destRect.width
        let dh = destRect.height
        return VisibleSourceBounds(
            offsetX: dw > 0 ? offCanvasLeft / dw * sourceW : 0,
            offsetY: dh > 0 ? offCanvasTop / dh * sourceH : 0,
            visibleW: dw > 0 ? (visMaxX - visMinX) / dw * sourceW : sourceW,
            visibleH: dh > 0 ? (visMaxY - visMinY) / dh * sourceH : sourceH
        )
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
        let (fittedSize, offset) = FitMath.fit(canvasSize, into: previewSize)

        let flippedY = canvasSize.height - canvasRect.origin.y - canvasRect.height

        return CGRect(
            x: offset.x + canvasRect.origin.x / canvasSize.width * fittedSize.width,
            y: offset.y + flippedY / canvasSize.height * fittedSize.height,
            width: canvasRect.width / canvasSize.width * fittedSize.width,
            height: canvasRect.height / canvasSize.height * fittedSize.height
        )
    }

    static func sourceRectInContainer(_ crop: CropInfo, imageSize: CGSize, container: CGSize) -> CGRect {
        let (fittedSize, offset) = FitMath.fit(imageSize, into: container)

        return CGRect(
            x: offset.x + crop.sourceRect.origin.x / imageSize.width * fittedSize.width,
            y: offset.y + crop.sourceRect.origin.y / imageSize.height * fittedSize.height,
            width: crop.sourceRect.width / imageSize.width * fittedSize.width,
            height: crop.sourceRect.height / imageSize.height * fittedSize.height
        )
    }
}
