import SwiftUI

struct PanelCropEditor: View {
    let panel: ImagePanel
    @Bindable var viewModel: CollageViewModel
    @State private var overlayDragMode: OverlayDragMode = .none
    @State private var dragBaseOrigin: CGPoint = .zero
    @State private var dragBaseSize: CGSize = .zero
    @State private var dragBaseSourceRect: CGRect = .zero
    @State private var dragVisibleOffset: CGPoint = .zero
    @State private var dragVisibleSize: CGSize = .zero
    @State private var containerSize: CGSize = .zero

    private var currentImage: ImageItem? {
        guard let idx = viewModel.getEffectiveImageIndex(for: panel.id),
                idx < viewModel.images.count else { return nil }
        return viewModel.images[idx]
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
                                panelGeometry: panel.geometry,
                                panelFrame: panel.frame
                            )
                            .accessibilityLabel("Crop preview")
                            .accessibilityHint("Shows the portion of the image visible in the panel")
                        }
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 5)
                                .onChanged { value in
                                    guard let crop = currentCrop else { return }

                                    if overlayDragMode == .none {
                                        let sourceRectProj = CropPreviewView.computeVisibleRect(
                                            crop,
                                            imageSize: image.size,
                                            container: geo.size
                                        )

                                        let visibleRegion: VisibleRegion
                                        switch panel.geometry {
                                        case .rect:
                                            visibleRegion = .rect(sourceRectProj)
                                        case .path:
                                            let quad = CropPreviewView.computeQuadInContainer(
                                                crop,
                                                imageSize: image.size,
                                                container: geo.size,
                                                panelFrame: panel.frame
                                            )
                                            visibleRegion = .quad(quad)
                                        }

                                        overlayDragMode = CropPreviewView.detectDragMode(
                                            visibleRegion: visibleRegion,
                                            startLocation: value.startLocation
                                        )

                                        switch panel.geometry {
                                        case .rect:
                                            dragBaseOrigin = sourceRectProj.origin
                                            dragBaseSize = sourceRectProj.size
                                            dragVisibleOffset = .zero
                                            dragVisibleSize = crop.sourceRect.size
                                        case .path:
                                            if case .quad(let vertices) = visibleRegion, vertices.count >= 3 {
                                                let minX = vertices.map { $0.x }.min()!
                                                let maxX = vertices.map { $0.x }.max()!
                                                let minY = vertices.map { $0.y }.min()!
                                                let maxY = vertices.map { $0.y }.max()!
                                                dragBaseOrigin = CGPoint(x: minX, y: minY)
                                                dragBaseSize = CGSize(width: maxX - minX, height: maxY - minY)
                                            }
                                        let visBounds = CropManager.computeVisibleSourceBounds(
                                                  destination: crop.destination,
                                                  sourceW: crop.sourceRect.width,
                                                  sourceH: crop.sourceRect.height
                                              )
                                             dragVisibleOffset = CGPoint(x: visBounds.offsetX, y: visBounds.offsetY)
                                             dragVisibleSize = CGSize(width: visBounds.visibleW, height: visBounds.visibleH)
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

                Text("Drag to move · Corner drag to zoom (proportional)")
                    .accessibilityHidden(true)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .id(panel.id)
    }

    // MARK: - Crop Adjustments (Delegate to CropManager)

    private func adjustCropDuringDrag(
        value: DragGesture.Value,
        image: ImageItem,
        crop: CropInfo,
        container: CGSize
    ) {
        switch overlayDragMode {
        case .drag:
            let visOffset = panel.geometry.isRect ? CGPoint.zero : dragVisibleOffset
            let visSize = panel.geometry.isRect ? crop.sourceRect.size : dragVisibleSize

            let newSourceRect = CropManager.adjustCropDuringDrag(
                translation: value.translation,
                image: image.size,
                crop: dragBaseSourceRect,
                container: container,
                visOffset: visOffset,
                visSize: visSize
            )
            viewModel.applyOverlayCropLive(panelId: panel.id, sourceRect: newSourceRect)

        case .resizeBottomRight, .resizeTopRight, .resizeBottomLeft, .resizeTopLeft:
            let edge: CropResizeEdge
            let anchor: CGPoint
            switch overlayDragMode {
            case .resizeBottomRight:
                edge = .bottomRight
                anchor = dragBaseOrigin
            case .resizeTopRight:
                edge = .topRight
                anchor = CGPoint(x: dragBaseOrigin.x, y: dragBaseOrigin.y + dragBaseSize.height)
            case .resizeBottomLeft:
                edge = .bottomLeft
                anchor = CGPoint(x: dragBaseOrigin.x + dragBaseSize.width, y: dragBaseOrigin.y)
            case .resizeTopLeft:
                edge = .topLeft
                anchor = CGPoint(x: dragBaseOrigin.x + dragBaseSize.width, y: dragBaseOrigin.y + dragBaseSize.height)
            default: return
            }

            let cropBounds = CGRect(origin: dragBaseOrigin, size: dragBaseSize)
            let delta = CGSize(
                width: value.location.x - anchor.x,
                height: value.location.y - anchor.y
            )

            let newSourceRect = CropManager.handleResize(
                cropBounds: cropBounds,
                edge: edge,
                delta: delta,
                image: image.size,
                crop: crop.sourceRect,
                container: container,
                panelSize: panel.frame.size,
                destRect: crop.destinationRect,
                isPathPanel: !panel.geometry.isRect
            )
            viewModel.applyOverlayCropLive(panelId: panel.id, sourceRect: newSourceRect)

        case .none:
            break
        }
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
    let panelFrame: CGRect

    var body: some View {
        ZStack {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: containerSize.width, height: containerSize.height)
                .clipped()

            if let crop {
                let region = computeVisibleRegion(crop, container: containerSize)
                ZStack {
                    dimOverlay(region: region, container: containerSize)
                    strokeVisibleRegion(region)
                    visibleRegionHandles(region)
                }
                .frame(width: containerSize.width, height: containerSize.height)
                .clipped()
            }
        }
    }

    private func computeVisibleRegion(_ crop: CropInfo, container: CGSize) -> VisibleRegion {
        switch crop.destination {
        case .rect:
            return .rect(CropManager.sourceRectInContainer(crop, imageSize: imageSize, container: container))
        case .path:
            return .quad(Self.computeQuadInContainer(crop, imageSize: imageSize, container: container, panelFrame: panelFrame))
        }
    }

    private func dimOverlay(region: VisibleRegion, container: CGSize) -> some View {
        Path { path in
            path.addRect(CGRect(x: 0, y: 0, width: container.width, height: container.height))
            switch region {
            case .rect(let r):
                path.addRect(r)
            case .quad(let vertices):
                guard !vertices.isEmpty else { break }
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
                    guard !vertices.isEmpty else { return }
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

    static func computeQuadInContainer(_ crop: CropInfo, imageSize: CGSize, container: CGSize, panelFrame: CGRect) -> [CGPoint] {
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

        var corners = PanelGeometry.extractPathPoints(cgPath)

        // Clip polygon vertices to canvas bounds.
        // extractPathPoints returns points in canvas coordinates (verified against
        // LayoutGenerator: DiagonalSlicesLayoutStrategy uses unshearedRect.origin.x,
        // HexagonalLayoutStrategy uses canvasCenter.x), so clip directly to canvas.
        let canvasSize = SizeConstants.defaultCanvasSize
        let canvasClipRect = CGRect(origin: .zero, size: canvasSize)
        corners = PolygonClipper.clip(corners, to: canvasClipRect)
        guard !corners.isEmpty else {
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
            guard vertices.count >= 3 else { break }

            // Classify each vertex by its position relative to the bounding box center
            let centerX = (vertices.map { $0.x }.min()! + vertices.map { $0.x }.max()!) / 2
            let centerY = (vertices.map { $0.y }.min()! + vertices.map { $0.y }.max()!) / 2

            for v in vertices {
                let dist = hypot(startLocation.x - v.x, startLocation.y - v.y)
                guard dist <= handleThreshold else { continue }

                let isLeft = v.x <= centerX
                let isTop = v.y <= centerY

                if isTop && isLeft { return .resizeTopLeft }
                if isTop && !isLeft { return .resizeTopRight }
                if !isTop && isLeft { return .resizeBottomLeft }
                if !isTop && !isLeft { return .resizeBottomRight }
            }

            // Build path from all vertices for containment test
            var p = Path()
            p.move(to: vertices[0])
            for i in 1..<vertices.count {
                p.addLine(to: vertices[i])
            }
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
