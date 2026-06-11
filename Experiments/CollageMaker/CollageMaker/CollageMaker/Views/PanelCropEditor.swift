import SwiftUI

struct PanelCropEditor: View {
    let panel: ImagePanel
    @Bindable var viewModel: CollageViewModel
    @State private var overlayDragMode: OverlayDragMode = .none
    @State private var dragBaseOrigin: CGPoint = .zero
    @State private var dragBaseSize: CGSize = .zero
    @State private var dragBaseSourceRect: CGRect = .zero
    @State private var dragBaseQuad: [CGPoint] = []
    @State private var containerSize: CGSize = .zero

    private var currentImage: ImageItem? {
        guard let idx = viewModel.getEffectiveImageIndex(for: panel.id),
               idx < viewModel.imageLibrary.images.count else { return nil }
        return viewModel.imageLibrary.images[idx]
    }

    private var currentCrop: CropInfo? {
        viewModel.cropMap[panel.id]
    }

    var body: some View {
        // Establish @Observable dependency at top of body so crop map
        // changes from canvas gestures trigger re-evaluation.
        let crop = viewModel.cropMap[panel.id]

        VStack(alignment: .leading, spacing: 12) {
            Text("Panel Editor")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 8) {
                if let image = currentImage {
                    GeometryReader { geo in
                        ZStack {
                            CropPreviewView(
                                nsImage: image.nsImage,
                                imageSize: image.size,
                                crop: crop,
                                containerSize: geo.size,
                                panelGeometry: panel.geometry
                            )
                            .accessibilityLabel("Crop preview")
                            .accessibilityHint("Shows the portion of the image visible in the panel")
                        }
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 5)
                                .onChanged { value in
                                    guard let crop = currentCrop else { return }

                                    if overlayDragMode == .none {
                                        let visibleRegion: VisibleRegion
                                        switch panel.geometry {
                                        case .rect:
                                            let visRect = computeVisibleRect(
                                                crop,
                                                imageSize: image.size,
                                                container: geo.size
                                            )
                                            visibleRegion = .rect(visRect)
                                        case .path:
                                            let quad = computeQuadInContainer(
                                                crop,
                                                imageSize: image.size,
                                                container: geo.size
                                            )
                                            visibleRegion = .quad(quad)
                                        }
                                        overlayDragMode = CropPreviewView.detectDragMode(
                                            visibleRegion: visibleRegion,
                                            startLocation: value.startLocation
                                        )
                                        if case .rect(let visRect) = visibleRegion {
                                            dragBaseOrigin = visRect.origin
                                            dragBaseSize = visRect.size
                                        }
                                        if case .quad(let quad) = visibleRegion {
                                            dragBaseQuad = quad
                                        }
                                        dragBaseSourceRect = crop.sourceRect
                                        if overlayDragMode != .none {
                                            viewModel.isLiveGesturing = true
                                            viewModel.beginOverlayCropUndo(panelId: panel.id)
                                        }
                                    }

                                    if overlayDragMode != .none {
                                        adjustCropDuringDrag(
                                            value: value,
                                            image: image,
                                            crop: crop,
                                            container: geo.size
                                        )
                                    }
                                }
                                .onEnded { _ in
                                if overlayDragMode != .none {
                                    viewModel.isLiveGesturing = false
                                    viewModel.finishOverlayCrop(panelId: panel.id)
                                    viewModel.endOverlayCropUndo()
                                }
                                    overlayDragMode = .none
                                }
                        )
                    }
                    .frame(height: 140)
                    .clipped()
                }

                HStack {
                    Text("Position:")
                    Text(String(format: "%.0f, %.0f", panel.frame.origin.x, panel.frame.origin.y))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Panel position")

                HStack {
                    Text("Size:")
                    Text(String(format: "%.0f x %.0f", panel.frame.width, panel.frame.height))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Panel size")

            }

            Divider()

            VStack(spacing: 4) {
                Button("Reset Crop") {
                    viewModel.resetCrop(panelId: panel.id)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Reset crop")
                .accessibilityHint("Restores the default crop for this image")

                Text("Drag to move\(panel.geometry.isRect ? " · Corner drag to zoom (proportional)" : "")")
                    .accessibilityHidden(true)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .id(panel.id)
    }

    // MARK: - Coordinate Conversion

    private func computeVisibleRect(_ crop: CropInfo, imageSize: CGSize, container: CGSize) -> CGRect {
        CropManager.sourceRectInContainer(crop, imageSize: imageSize, container: container)
    }

    private func computeQuadInContainer(_ crop: CropInfo, imageSize: CGSize, container: CGSize) -> [CGPoint] {
        let (fittedSize, fitOffset) = FitMath.fit(imageSize, into: container)
        let boundingRect = crop.destination.boundingRect
        guard boundingRect.width > 0, boundingRect.height > 0,
              let cgPath = crop.destination.cgPath else {
            let vis = CropManager.sourceRectInContainer(crop, imageSize: imageSize, container: container)
            return [
                CGPoint(x: vis.minX, y: vis.minY),
                CGPoint(x: vis.maxX, y: vis.minY),
                CGPoint(x: vis.minX, y: vis.maxY),
                CGPoint(x: vis.maxX, y: vis.maxY)
            ]
        }

        let corners = extractPathPoints(cgPath)
        guard corners.count == 4 else {
            let vis = CropManager.sourceRectInContainer(crop, imageSize: imageSize, container: container)
            return [
                CGPoint(x: vis.minX, y: vis.minY),
                CGPoint(x: vis.maxX, y: vis.minY),
                CGPoint(x: vis.minX, y: vis.maxY),
                CGPoint(x: vis.maxX, y: vis.maxY)
            ]
        }

        return corners.map { corner in
            let relX = (corner.x - boundingRect.minX) / boundingRect.width
            let relY_topLeft = 1.0 - (corner.y - boundingRect.minY) / boundingRect.height
            return CGPoint(
                x: fitOffset.x + (crop.sourceRect.minX + relX * crop.sourceRect.width) / imageSize.width * fittedSize.width,
                y: fitOffset.y + (crop.sourceRect.minY + relY_topLeft * crop.sourceRect.height) / imageSize.height * fittedSize.height
            )
        }
    }

    private func extractPathPoints(_ cgPath: CGPath) -> [CGPoint] {
        class PointCollector { var points: [CGPoint] = [] }
        let collector = PointCollector()
        cgPath.apply(info: Unmanaged.passUnretained(collector).toOpaque()) { info, element in
            let c = Unmanaged<PointCollector>.fromOpaque(info!).takeUnretainedValue()
            let elem = element.pointee
            switch elem.type {
            case .moveToPoint:
                c.points.append(elem.points.pointee)
            case .addLineToPoint:
                c.points.append(elem.points.pointee)
            case .addQuadCurveToPoint:
                c.points.append(elem.points.pointee)
                c.points.append(elem.points.advanced(by: 1).pointee)
            case .addCurveToPoint:
                c.points.append(elem.points.pointee)
                c.points.append(elem.points.advanced(by: 1).pointee)
                c.points.append(elem.points.advanced(by: 2).pointee)
            case .closeSubpath:
                break
            @unknown default:
                break
            }
        }
        return collector.points
    }

    private func adjustCropDuringDrag(
        value: DragGesture.Value,
        image: ImageItem,
        crop: CropInfo,
        container: CGSize
    ) {
        let (fittedSize, fitOffset) = FitMath.fit(image.size, into: container)

        let fittedW = fittedSize.width
        let fittedH = fittedSize.height

        let scaleX = image.size.width / fittedW
        let scaleY = image.size.height / fittedH

        switch overlayDragMode {
        case .drag:
            let transX = value.translation.width * scaleX
            let transY = value.translation.height * scaleY

            let maxOX = max(0, image.size.width - crop.sourceRect.width)
            let maxOY = max(0, image.size.height - crop.sourceRect.height)

            let newOX = max(0, min(dragBaseSourceRect.origin.x + transX, maxOX))
            let newOY = max(0, min(dragBaseSourceRect.origin.y + transY, maxOY))

            viewModel.applyOverlayCropLive(
                panelId: panel.id,
                sourceRect: CGRect(x: newOX, y: newOY, width: crop.sourceRect.width, height: crop.sourceRect.height)
            )

        case .resizeBottomRight:
            handleResize(
                value: value,
                anchor: dragBaseOrigin,
                image: image,
                crop: crop,
                container: container,
                fittedW: fittedW,
                fittedH: fittedH,
                fitOffset: fitOffset,
                baseSourceRect: dragBaseSourceRect
            )

        case .resizeTopRight:
            handleResize(
                value: value,
                anchor: CGPoint(x: dragBaseOrigin.x, y: dragBaseOrigin.y + dragBaseSize.height),
                image: image,
                crop: crop,
                container: container,
                fittedW: fittedW,
                fittedH: fittedH,
                fitOffset: fitOffset,
                baseSourceRect: dragBaseSourceRect
            )

        case .resizeBottomLeft:
            handleResize(
                value: value,
                anchor: CGPoint(x: dragBaseOrigin.x + dragBaseSize.width, y: dragBaseOrigin.y),
                image: image,
                crop: crop,
                container: container,
                fittedW: fittedW,
                fittedH: fittedH,
                fitOffset: fitOffset,
                baseSourceRect: dragBaseSourceRect
            )

        case .resizeTopLeft:
            handleResize(
                value: value,
                anchor: CGPoint(x: dragBaseOrigin.x + dragBaseSize.width, y: dragBaseOrigin.y + dragBaseSize.height),
                image: image,
                crop: crop,
                container: container,
                fittedW: fittedW,
                fittedH: fittedH,
                fitOffset: fitOffset,
                baseSourceRect: dragBaseSourceRect
            )

        case .none:
            break
        }
    }

    private func handleResize(
        value: DragGesture.Value,
        anchor: CGPoint,
        image: ImageItem,
        crop: CropInfo,
        container: CGSize,
        fittedW: CGFloat,
        fittedH: CGFloat,
        fitOffset: CGPoint,
        baseSourceRect: CGRect
    ) {
        let panelAspect = panel.frame.width / panel.frame.height

        let rawW = abs(value.location.x - anchor.x)
        let rawH = abs(value.location.y - anchor.y)

        var newW: CGFloat
        var newH: CGFloat
        if rawW / rawH > panelAspect {
            newW = max(1, rawW)
            newH = newW / panelAspect
        } else {
            newH = max(1, rawH)
            newW = newH * panelAspect
        }

        let newMinX = min(anchor.x, value.location.x)
        let newMinY = min(anchor.y, value.location.y)

        var clampedOX = max(0, min(newMinX, container.width - newW))
        var clampedOY = max(0, min(newMinY, container.height - newH))

        if clampedOX + newW > container.width {
            clampedOX = container.width - newW
        }
        if clampedOY + newH > container.height {
            clampedOY = container.height - newH
        }

        let sourceOrigin = CGPoint(
            x: (clampedOX - fitOffset.x) / fittedW * image.size.width,
            y: (clampedOY - fitOffset.y) / fittedH * image.size.height
        )
        var sourceSize = CGSize(
            width: newW / fittedW * image.size.width,
            height: newH / fittedH * image.size.height
        )

        let maxSourceRect = FitMath.sourceRect(imageSize: image.size, panelSize: panel.frame.size)
        let maxSourceW = maxSourceRect.width
        let maxSourceH = maxSourceRect.height
        let minSourceW = panel.frame.width / 2
        let minSourceH = panel.frame.height / 2

        sourceSize.width = Swift.max(minSourceW, Swift.min(maxSourceW, sourceSize.width))
        sourceSize.height = Swift.max(minSourceH, Swift.min(maxSourceH, sourceSize.height))

        let clampedOriginX = Swift.max(0, Swift.min(sourceOrigin.x, max(0, image.size.width - sourceSize.width)))
        let clampedOriginY = Swift.max(0, Swift.min(sourceOrigin.y, max(0, image.size.height - sourceSize.height)))

        viewModel.applyOverlayCropLive(
            panelId: panel.id,
            sourceRect: CGRect(x: clampedOriginX, y: clampedOriginY, width: sourceSize.width, height: sourceSize.height)
        )
    }
}

enum OverlayDragMode {
    case none, drag, resizeBottomRight, resizeTopRight, resizeBottomLeft, resizeTopLeft
}

enum VisibleRegion {
    case rect(CGRect)
    case quad([CGPoint])
}

struct CropPreviewView: View {
    let nsImage: NSImage
    let imageSize: CGSize
    let crop: CropInfo?
    let containerSize: CGSize
    let panelGeometry: PanelGeometry

    var body: some View {
        ZStack {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: containerSize.width, height: containerSize.height)
                .clipped()

            if let crop {
                let region = computeVisibleRegion(crop, container: containerSize)
                dimOverlay(region: region, container: containerSize)
                strokeVisibleRegion(region)
                visibleRegionHandles(region)
            }
        }
    }

    private func computeVisibleRegion(_ crop: CropInfo, container: CGSize) -> VisibleRegion {
        switch crop.destination {
        case .rect:
            return .rect(CropManager.sourceRectInContainer(crop, imageSize: imageSize, container: container))
        case .path:
            return .quad(computeQuadInContainer(crop, container: container))
        }
    }

    private func computeQuadInContainer(_ crop: CropInfo, container: CGSize) -> [CGPoint] {
        let (fittedSize, fitOffset) = FitMath.fit(imageSize, into: container)
        let boundingRect = crop.destination.boundingRect
        guard boundingRect.width > 0, boundingRect.height > 0,
              let cgPath = crop.destination.cgPath else {
            let vis = CropManager.sourceRectInContainer(crop, imageSize: imageSize, container: container)
            return [
                CGPoint(x: vis.minX, y: vis.minY),
                CGPoint(x: vis.maxX, y: vis.minY),
                CGPoint(x: vis.minX, y: vis.maxY),
                CGPoint(x: vis.maxX, y: vis.maxY)
            ]
        }

        let corners = extractPathPoints(cgPath)
        guard corners.count == 4 else {
            let vis = CropManager.sourceRectInContainer(crop, imageSize: imageSize, container: container)
            return [
                CGPoint(x: vis.minX, y: vis.minY),
                CGPoint(x: vis.maxX, y: vis.minY),
                CGPoint(x: vis.minX, y: vis.maxY),
                CGPoint(x: vis.maxX, y: vis.maxY)
            ]
        }

        return corners.map { corner in
            let relX = (corner.x - boundingRect.minX) / boundingRect.width
            let relY_topLeft = 1.0 - (corner.y - boundingRect.minY) / boundingRect.height
            return CGPoint(
                x: fitOffset.x + (crop.sourceRect.minX + relX * crop.sourceRect.width) / imageSize.width * fittedSize.width,
                y: fitOffset.y + (crop.sourceRect.minY + relY_topLeft * crop.sourceRect.height) / imageSize.height * fittedSize.height
            )
        }
    }

    private func extractPathPoints(_ cgPath: CGPath) -> [CGPoint] {
        class PointCollector { var points: [CGPoint] = [] }
        let collector = PointCollector()
        cgPath.apply(info: Unmanaged.passUnretained(collector).toOpaque()) { info, element in
            let c = Unmanaged<PointCollector>.fromOpaque(info!).takeUnretainedValue()
            let elem = element.pointee
            switch elem.type {
            case .moveToPoint:
                c.points.append(elem.points.pointee)
            case .addLineToPoint:
                c.points.append(elem.points.pointee)
            case .addQuadCurveToPoint:
                c.points.append(elem.points.pointee)
                c.points.append(elem.points.advanced(by: 1).pointee)
            case .addCurveToPoint:
                c.points.append(elem.points.pointee)
                c.points.append(elem.points.advanced(by: 1).pointee)
                c.points.append(elem.points.advanced(by: 2).pointee)
            case .closeSubpath:
                break
            @unknown default:
                break
            }
        }
        return collector.points
    }

    private func dimOverlay(region: VisibleRegion, container: CGSize) -> some View {
        Path { path in
            path.addRect(CGRect(x: 0, y: 0, width: container.width, height: container.height))
            switch region {
            case .rect(let r):
                path.addRect(r)
            case .quad(let vertices):
                path.move(to: vertices[0])
                for i in 1..<vertices.count {
                    path.addLine(to: vertices[i])
                }
                path.closeSubpath()
            }
        }
        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    private func strokeVisibleRegion(_ region: VisibleRegion) -> some View {
        Group {
            switch region {
            case .rect(let r):
                Path { path in
                    path.addRect(r)
                }
                .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
            case .quad(let vertices):
                Path { path in
                    path.move(to: vertices[0])
                    for i in 1..<vertices.count {
                        path.addLine(to: vertices[i])
                    }
                    path.closeSubpath()
                }
                .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
            }
        }
        .allowsHitTesting(false)
    }

    private func visibleRegionHandles(_ region: VisibleRegion) -> some View {
        let handleSize: CGFloat = 10
        let vertices: [CGPoint]

        switch region {
        case .rect(let r):
            vertices = [
                CGPoint(x: r.minX, y: r.minY),
                CGPoint(x: r.maxX, y: r.minY),
                CGPoint(x: r.minX, y: r.maxY),
                CGPoint(x: r.maxX, y: r.maxY)
            ]
        case .quad(let v):
            vertices = v
        }

        return ZStack {
            ForEach(vertices.indices, id: \.self) { i in
                Rectangle()
                    .fill(Color.orange.opacity(0.3))
                    .frame(width: handleSize, height: handleSize)
                    .position(vertices[i])
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Static Helpers

    static func computeVisibleRect(_ crop: CropInfo, imageSize: CGSize, container: CGSize) -> CGRect {
        CropManager.sourceRectInContainer(crop, imageSize: imageSize, container: container)
    }

    static func detectDragMode(visibleRegion: VisibleRegion, startLocation: CGPoint) -> OverlayDragMode {
        let handleThreshold: CGFloat = 16

        switch visibleRegion {
        case .rect(let visibleRect):
            let brDist = hypot(startLocation.x - visibleRect.maxX, startLocation.y - visibleRect.maxY)
            if brDist <= handleThreshold { return .resizeBottomRight }

            let trDist = hypot(startLocation.x - visibleRect.maxX, startLocation.y - visibleRect.minY)
            if trDist <= handleThreshold { return .resizeTopRight }

            let blDist = hypot(startLocation.x - visibleRect.minX, startLocation.y - visibleRect.maxY)
            if blDist <= handleThreshold { return .resizeBottomLeft }

            let tlDist = hypot(startLocation.x - visibleRect.minX, startLocation.y - visibleRect.minY)
            if tlDist <= handleThreshold { return .resizeTopLeft }

            if visibleRect.contains(startLocation) { return .drag }

        case .quad(let vertices):
            guard vertices.count == 4 else { break }
            let tlDist = hypot(startLocation.x - vertices[0].x, startLocation.y - vertices[0].y)
            if tlDist <= handleThreshold { return .resizeTopLeft }

            let trDist = hypot(startLocation.x - vertices[1].x, startLocation.y - vertices[1].y)
            if trDist <= handleThreshold { return .resizeTopRight }

            let blDist = hypot(startLocation.x - vertices[2].x, startLocation.y - vertices[2].y)
            if blDist <= handleThreshold { return .resizeBottomLeft }

            let brDist = hypot(startLocation.x - vertices[3].x, startLocation.y - vertices[3].y)
            if brDist <= handleThreshold { return .resizeBottomRight }

            var p = Path()
            p.move(to: vertices[0])
            p.addLine(to: vertices[1])
            p.addLine(to: vertices[2])
            p.addLine(to: vertices[3])
            p.closeSubpath()
            if p.contains(startLocation) { return .drag }
        }

        return .none
    }
}

enum Corners: CaseIterable, Hashable {
    case topLeft, topRight, bottomLeft, bottomRight

    func position(for rect: CGRect, handleSize: CGFloat) -> CGPoint {
        switch self {
        case .topLeft:
            return CGPoint(x: rect.minX + handleSize / 2, y: rect.minY + handleSize / 2)
        case .topRight:
            return CGPoint(x: rect.maxX - handleSize / 2, y: rect.minY + handleSize / 2)
        case .bottomLeft:
            return CGPoint(x: rect.minX + handleSize / 2, y: rect.maxY - handleSize / 2)
        case .bottomRight:
            return CGPoint(x: rect.maxX - handleSize / 2, y: rect.maxY - handleSize / 2)
        }
    }
}
