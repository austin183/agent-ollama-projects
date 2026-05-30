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

        let maxZoomOut = Swift.min(image.size.width / panelSize.width, image.size.height / panelSize.height)
        let newZoom = clamp(baseZoom / zoomDelta, min: 0.5, max: maxZoomOut)
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

    static func translateZoom(magnification: CGFloat, baseZoom: CGFloat, imageSize: CGSize, panelSize: CGSize) -> CGFloat {
        let newZoom = baseZoom / magnification
        let maxZoomOut = Swift.min(imageSize.width / panelSize.width, imageSize.height / panelSize.height)
        return Swift.max(0.5, Swift.min(maxZoomOut, newZoom))
    }

    static func screenToCanvasPoint(_ screenPoint: CGPoint, in previewSize: CGSize) -> CGPoint {
        let canvasSize = CanvasConfig.defaultCanvasSize
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
