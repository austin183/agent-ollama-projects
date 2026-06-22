import AppKit
import CoreGraphics
import Foundation
import SwiftUI

enum CropResizeEdge: String {
    case topLeft, topRight, bottomLeft, bottomRight
}

@MainActor
@Observable
final class CropManager {
    var cropMap: [UUID: CropInfo] = [:]
    var cropVersions: [UUID: Int] = [:]

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

    private func setCropInfo(_ info: CropInfo, panelId: UUID) {
        cropMap[panelId] = info
        cropVersions[panelId, default: 0] += 1
    }

    func getCropVersion(panelId: UUID) -> Int {
        cropVersions[panelId, default: 0]
    }

    func computeInitialCrops(panels: [ImagePanel], images: [ImageItem]) {
        cropMap.removeAll()
        cropVersions.removeAll()
        for panel in panels {
            guard panel.imageIndex < images.count else { continue }
            let image = images[panel.imageIndex]
            let panelSize = panel.frame.size
            let cropRect = computeBestFitSource(imageSize: image.size, panelSize: panelSize)
            setCropInfo(CropInfo(
                panelId: panel.id,
                sourceRect: cropRect,
                destination: panel.geometry
            ), panelId: panel.id)
        }
    }

    func computeCropsFromSaliency(
        panels: [ImagePanel],
        images: [ImageItem],
        results: [Int: SaliencyResult]
    ) {
        cropMap.removeAll()
        cropVersions.removeAll()
        for panel in panels {
            guard panel.imageIndex < images.count else { continue }
            let image = images[panel.imageIndex]
            let panelSize = panel.frame.size
            let saliency = results[panel.imageIndex]

            var sourceRect: CGRect
            if let sal = saliency {
                let origin = sal.cropOrigin(for: image.size, cropSize: panelSize)
                var rect = CGRect(origin: origin, size: panelSize)
                rect = rect.intersection(CGRect(origin: .zero, size: image.size))
                sourceRect = rect
            } else {
                sourceRect = computeBestFitSource(imageSize: image.size, panelSize: panelSize)
            }

            setCropInfo(CropInfo(
                panelId: panel.id,
                sourceRect: sourceRect,
                destination: panel.geometry
            ), panelId: panel.id)
        }
    }

    /// Extracts sourceRect values by slot index for crop preservation across layout changes.
    func cropsBySlot(_ panels: [ImagePanel]) -> [CGRect] {
        panels.map { cropMap[$0.id]?.sourceRect ?? CGRect(origin: .zero, size: $0.frame.size) }
    }

    /// Applies previously extracted sourceRect values to new panels by slot index.
    func applyCropsBySlot(_ sourceRects: [CGRect], panels: [ImagePanel]) {
        cropMap.removeAll()
        cropVersions.removeAll()
        for (index, panel) in panels.enumerated() {
            let sourceRect = index < sourceRects.count ? sourceRects[index] :
                CGRect(origin: .zero, size: panel.frame.size)
            setCropInfo(CropInfo(
                panelId: panel.id,
                sourceRect: sourceRect,
                destination: panel.geometry
            ), panelId: panel.id)
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

        let visBounds = Self.computeVisibleSourceBounds(destination: crop.destination, sourceW: scaledW, sourceH: scaledH)

        let effectiveBaseX = baseOrigin.x + visBounds.offsetX
        let effectiveBaseY = baseOrigin.y + visBounds.offsetY
        let maxEffX = max(0, image.size.width - visBounds.visibleW)
        let maxEffY = max(0, image.size.height - visBounds.visibleH)

        let newEffX = clamp(effectiveBaseX - panDelta.width, min: 0, max: maxEffX)
        let newEffY = clamp(effectiveBaseY - panDelta.height, min: 0, max: maxEffY)

        let newOX = newEffX - visBounds.offsetX
        let newOY = newEffY - visBounds.offsetY

        setCropInfo(CropInfo(
            panelId: id,
            sourceRect: CGRect(x: newOX, y: newOY, width: scaledW, height: scaledH),
            destination: crop.destination
        ), panelId: id)

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

        let visBounds = Self.computeVisibleSourceBounds(destination: crop.destination, sourceW: scaledW, sourceH: scaledH)
        let oldVisBounds = Self.computeVisibleSourceBounds(destination: crop.destination, sourceW: crop.sourceRect.width, sourceH: crop.sourceRect.height)

        // Determine the zoom anchor point. The anchor's effective source
        // coordinate is computed from the OLD crop, and the offset subtracted
        // is the anchor's position within the NEW visible region.
        var anchorEffX: CGFloat = 0
        var anchorOffsetX: CGFloat = 0
        var anchorEffY: CGFloat = 0
        var anchorOffsetY: CGFloat = 0

        if crop.destination.isRect {
            let cx = crop.sourceRect.origin.x + oldVisBounds.offsetX + oldVisBounds.visibleW / 2
            let cy = crop.sourceRect.origin.y + oldVisBounds.offsetY + oldVisBounds.visibleH / 2
            anchorEffX = cx; anchorOffsetX = visBounds.visibleW / 2
            anchorEffY = cy; anchorOffsetY = visBounds.visibleH / 2
        } else {
            let dest = crop.destinationRect
            let baseEffX = crop.sourceRect.origin.x + oldVisBounds.offsetX
            let baseEffY = crop.sourceRect.origin.y + oldVisBounds.offsetY

            if dest.minX < 0 {
                // Left edge clipped — anchor at top-left of visible region
                anchorEffX = baseEffX; anchorOffsetX = 0
                anchorEffY = baseEffY; anchorOffsetY = 0
            } else if dest.maxX > SizeConstants.defaultCanvasSize.width {
                // Right edge clipped — anchor at bottom-right of visible region
                anchorEffX = baseEffX + oldVisBounds.visibleW; anchorOffsetX = visBounds.visibleW
                anchorEffY = baseEffY + oldVisBounds.visibleH; anchorOffsetY = visBounds.visibleH
            } else {
                // Fully on-canvas — anchor at top-left of visible region
                anchorEffX = baseEffX; anchorOffsetX = 0
                anchorEffY = baseEffY; anchorOffsetY = 0
            }
        }

        let maxEffX = max(0, image.size.width - visBounds.visibleW)
        let maxEffY = max(0, image.size.height - visBounds.visibleH)

        let newEffX = clamp(anchorEffX - anchorOffsetX, min: 0, max: maxEffX)
        let newEffY = clamp(anchorEffY - anchorOffsetY, min: 0, max: maxEffY)

        let newOX = newEffX - visBounds.offsetX
        let newOY = newEffY - visBounds.offsetY

        setCropInfo(CropInfo(
            panelId: id,
            sourceRect: CGRect(x: newOX, y: newOY, width: scaledW, height: scaledH),
            destination: crop.destination
        ), panelId: id)

        if finish { endGesture() }
    }

    func resetCrop(panelId: UUID, panels: [ImagePanel], images: [ImageItem], panelAssignments: [UUID: Int] = [:]) {
        guard let panel = panels.first(where: { $0.id == panelId }) else { return }

        let imageIndex = panelAssignments[panelId] ?? panel.imageIndex
        guard imageIndex < images.count else { return }

        let image = images[imageIndex]
        let panelSize = panel.frame.size
        let cropRect = computeBestFitSource(imageSize: image.size, panelSize: panelSize)

        setCropInfo(CropInfo(
            panelId: panelId,
            sourceRect: cropRect,
            destination: panel.geometry
        ), panelId: panelId)
    }

    func resetAllCrops(panels: [ImagePanel], images: [ImageItem]) {
        computeInitialCrops(panels: panels, images: images)
    }

    // MARK: - Overlay Crop Adjustments (Static, Pure)

    /// Adjusts the crop source rectangle during a drag gesture in the overlay preview.
    /// Converts the container-space translation to image-space, applies it to the crop origin,
    /// and clamps to image bounds. Supports path panels via visible offset/size parameters.
    /// - Returns: The updated source rectangle in image coordinates.
    static func adjustCropDuringDrag(
        translation: CGSize,
        image: CGSize,
        crop: CGRect,
        container: CGSize,
        visOffset: CGPoint,
        visSize: CGSize
    ) -> CGRect {
        let (fittedSize, _) = FitMath.fit(image, into: container)
        let scaleX = image.width / fittedSize.width
        let scaleY = image.height / fittedSize.height

        let transX = translation.width * scaleX
        let transY = translation.height * scaleY

        let effectiveBaseX = crop.origin.x + visOffset.x
        let effectiveBaseY = crop.origin.y + visOffset.y

        let maxEffX = max(0, image.width - visSize.width)
        let maxEffY = max(0, image.height - visSize.height)

        let newEffX = max(0, min(effectiveBaseX + transX, maxEffX))
        let newEffY = max(0, min(effectiveBaseY + transY, maxEffY))

        let newOX = newEffX - visOffset.x
        let newOY = newEffY - visOffset.y

        return CGRect(x: newOX, y: newOY, width: crop.width, height: crop.height)
    }

    /// Handles a corner resize drag in the overlay preview.
    /// Computes the new crop rectangle based on the drag delta from the anchor corner,
    /// enforces panel aspect ratio, and clamps to image bounds.
    /// - Returns: The updated source rectangle in image coordinates.
    static func handleResize(
        cropBounds: CGRect,
        edge: CropResizeEdge,
        delta: CGSize,
        image: CGSize,
        crop: CGRect,
        container: CGSize,
        panelSize: CGSize,
        destRect: CGRect,
        isPathPanel: Bool = false
    ) -> CGRect {
        let anchor: CGPoint
        switch edge {
        case .bottomRight:
            anchor = cropBounds.origin
        case .topRight:
            anchor = CGPoint(x: cropBounds.minX, y: cropBounds.maxY)
        case .bottomLeft:
            anchor = CGPoint(x: cropBounds.maxX, y: cropBounds.minY)
        case .topLeft:
            anchor = CGPoint(x: cropBounds.maxX, y: cropBounds.maxY)
        }

        let panelAspect = panelSize.width / panelSize.height

        let rawW = abs(delta.width)
        let rawH = abs(delta.height)

        var newW: CGFloat
        var newH: CGFloat
        if rawW > panelAspect * rawH {
            newW = max(1, rawW)
            newH = newW / panelAspect
        } else {
            newH = max(1, rawH)
            newW = newH * panelAspect
        }

        var ox = anchor.x
        var oy = anchor.y

        switch edge {
        case .bottomRight:
            break
        case .topRight:
            oy = anchor.y - newH
        case .bottomLeft:
            ox = anchor.x - newW
        case .topLeft:
            ox = anchor.x - newW
            oy = anchor.y - newH
        }

        let clampedOX = max(0, min(ox, container.width - newW))
        let clampedOY = max(0, min(oy, container.height - newH))

        let (fittedSize, fitOffset) = FitMath.fit(image, into: container)

        var sourceOrigin = CGPoint(
            x: (clampedOX - fitOffset.x) / fittedSize.width * image.width,
            y: (clampedOY - fitOffset.y) / fittedSize.height * image.height
        )
        var sourceSize = CGSize(
            width: newW / fittedSize.width * image.width,
            height: newH / fittedSize.height * image.height
        )

        let maxSourceRect = FitMath.sourceRect(imageSize: image, panelSize: panelSize)
        let minSourceW = panelSize.width / 2
        let minSourceH = panelSize.height / 2

        sourceSize.width = Swift.max(minSourceW, Swift.min(maxSourceRect.width, sourceSize.width))
        sourceSize.height = Swift.max(minSourceH, Swift.min(maxSourceRect.height, sourceSize.height))

        // Path-panel compensation: adjust source origin to keep the non-dragged
        // parallelogram edge stable when source size changes.
        if isPathPanel, destRect.width > 0, destRect.height > 0 {
            let deltaW = sourceSize.width - crop.width
            let deltaH = sourceSize.height - crop.height

            if anchor.x <= cropBounds.minX + CGFloat.ulpOfOne {
                sourceOrigin.x += deltaW * (-destRect.minX) / destRect.width
            } else {
                sourceOrigin.x += deltaW * (destRect.minX + destRect.width) / destRect.width - deltaW
            }

            if anchor.y <= cropBounds.minY + CGFloat.ulpOfOne {
                sourceOrigin.y += deltaH * (-destRect.minY) / destRect.height
            } else {
                sourceOrigin.y += deltaH * (destRect.minY + destRect.height) / destRect.height - deltaH
            }
        }

        let clampedOriginX = Swift.max(0, Swift.min(sourceOrigin.x, max(0, image.width - sourceSize.width)))
        let clampedOriginY = Swift.max(0, Swift.min(sourceOrigin.y, max(0, image.height - sourceSize.height)))

        return CGRect(x: clampedOriginX, y: clampedOriginY, width: sourceSize.width, height: sourceSize.height)
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
        CoordinateConverter.hitTestPanel(
            at: location,
            panelFrames: panelFrames,
            panelGeometries: panelGeometries,
            previewSize: previewSize,
            canvasSize: SizeConstants.defaultCanvasSize
        )
    }

    static func translateZoom(magnification: CGFloat, baseZoom: CGFloat, imageSize: CGSize, panelSize: CGSize) -> CGFloat {
        let newZoom = baseZoom / magnification
        let maxZoomOut = Swift.min(imageSize.width / panelSize.width, imageSize.height / panelSize.height)
        return Swift.max(0.5, Swift.min(maxZoomOut, newZoom))
    }

    static func screenToCanvasPoint(_ screenPoint: CGPoint, in previewSize: CGSize) -> CGPoint {
        CoordinateConverter.screenToCanvasPoint(screenPoint, in: previewSize, canvasSize: SizeConstants.defaultCanvasSize)
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

    internal struct VisibleSourceBounds {
        let offsetX: CGFloat
        let offsetY: CGFloat
        let visibleW: CGFloat
        let visibleH: CGFloat
    }

    static func computeVisibleSourceBounds(destRect: CGRect, sourceW: CGFloat, sourceH: CGFloat) -> VisibleSourceBounds {
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

    /// Computes visible source bounds from the actual panel geometry.
    /// For `.rect` panels, delegates to the bounding-rect implementation.
    /// For `.path` panels, clips the polygon to canvas bounds first, producing
    /// accurate visible extents for edge panels whose parallelogram extends
    /// beyond the canvas (e.g., diagonal slices, hexagonal layouts).
    static func computeVisibleSourceBounds(destination: PanelGeometry, sourceW: CGFloat, sourceH: CGFloat) -> VisibleSourceBounds {
        switch destination {
        case .rect:
            return computeVisibleSourceBounds(destRect: destination.boundingRect, sourceW: sourceW, sourceH: sourceH)

        case .path(let cgPath, let boundingRect):
            let canvasSize = SizeConstants.defaultCanvasSize
            let canvasClipRect = CGRect(origin: .zero, size: canvasSize)

            var vertices = PanelGeometry.extractPathPoints(cgPath)
            vertices = PolygonClipper.clip(vertices, to: canvasClipRect)

            if vertices.isEmpty {
                return VisibleSourceBounds(offsetX: 0, offsetY: 0, visibleW: 0, visibleH: 0)
            }

            let clippedMinX = vertices.map { $0.x }.min()!
            let clippedMaxX = vertices.map { $0.x }.max()!
            let clippedMinY = vertices.map { $0.y }.min()!
            let clippedMaxY = vertices.map { $0.y }.max()!

            let dw = boundingRect.width
            let dh = boundingRect.height

            let offCanvasLeft = Swift.max(0, clippedMinX - boundingRect.minX)
            // Canvas Y is bottom-left origin; source Y is top-left origin.
            // The rendering pipeline flips Y: canvas bottom → source top,
            // canvas top → source bottom. The clamping logic treats offsetY
            // as "pixels to skip at the source top." A clip at the canvas
            // bottom (source top) must be expressed as a clip at the canvas
            // top to produce the correct source-top offset after the flip.
            let offCanvasTop = Swift.max(0, boundingRect.maxY - clippedMaxY)
            let clippedW = clippedMaxX - clippedMinX
            let clippedH = clippedMaxY - clippedMinY

            return VisibleSourceBounds(
                offsetX: dw > 0 ? offCanvasLeft / dw * sourceW : 0,
                offsetY: dh > 0 ? offCanvasTop / dh * sourceH : 0,
                visibleW: dw > 0 ? clippedW / dw * sourceW : sourceW,
                visibleH: dh > 0 ? clippedH / dh * sourceH : sourceH
            )
        }
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

    /// Converts a point from screen/preview coordinates (top-left origin) to canvas coordinates (bottom-left origin).
    static func screenToCanvasPoint(_ screenPoint: CGPoint, in previewSize: CGSize, canvasSize: CGSize) -> CGPoint {
        let (fittedSize, offset) = FitMath.fit(canvasSize, into: previewSize)

        let canvasX = (screenPoint.x - offset.x) / fittedSize.width * canvasSize.width
        let canvasY = canvasSize.height - (screenPoint.y - offset.y) / fittedSize.height * canvasSize.height

        return CGPoint(x: canvasX, y: canvasY)
    }

    /// Hit-tests a location against panel frames, with optional geometry-aware path testing.
    static func hitTestPanel(
        at location: CGPoint,
        panelFrames: [UUID: CGRect],
        panelGeometries: [UUID: PanelGeometry]? = nil,
        previewSize: CGSize,
        canvasSize: CGSize
    ) -> UUID? {
        let candidates = panelFrames.filter { $0.value.contains(location) }
        guard !candidates.isEmpty else { return nil }

        if let geometries = panelGeometries {
            let canvasPoint = screenToCanvasPoint(location, in: previewSize, canvasSize: canvasSize)
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

    /// Converts a point from Vision normalized coordinates (bottom-left origin, 0-1) to
    /// CoreGraphics pixel coordinates (top-left origin, 0-imageSize).
    /// - Parameters:
    ///   - visionPoint: Normalized point in Vision coordinate space (bottom-left origin).
    ///   - imageSize: Pixel dimensions of the source image.
    /// - Returns: Point in CG pixel coordinates (top-left origin).
    static func visionToCG(_ visionPoint: CGPoint, imageSize: CGSize) -> CGPoint {
        let cgX = visionPoint.x * imageSize.width
        let cgY = (1.0 - visionPoint.y) * imageSize.height
        return CGPoint(x: cgX, y: cgY)
    }

    /// Converts a rectangle from Vision normalized coordinates (bottom-left origin, 0-1) to
    /// CoreGraphics pixel coordinates (top-left origin, 0-imageSize).
    /// - Parameters:
    ///   - visionRect: Normalized rectangle in Vision coordinate space (bottom-left origin).
    ///   - imageSize: Pixel dimensions of the source image.
    /// - Returns: Rectangle in CG pixel coordinates (top-left origin).
    static func visionRectToCG(_ visionRect: CGRect, imageSize: CGSize) -> CGRect {
        let cgX = visionRect.origin.x * imageSize.width
        let cgY = (1.0 - visionRect.origin.y - visionRect.height) * imageSize.height
        let cgW = visionRect.width * imageSize.width
        let cgH = visionRect.height * imageSize.height
        return CGRect(x: cgX, y: cgY, width: cgW, height: cgH)
    }

}
