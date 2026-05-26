import SwiftUI

struct PanelCropEditor: View {
    let panel: ImagePanel
    @Bindable var viewModel: CollageViewModel
    @State private var overlayDragMode: OverlayDragMode = .none
    @State private var dragBaseOrigin: CGPoint = .zero
    @State private var dragBaseSize: CGSize = .zero
    @State private var dragBaseSourceRect: CGRect = .zero
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
                                crop: viewModel.cropMap[panel.id],
                                containerSize: geo.size
                            )
                            .accessibilityLabel("Crop preview")
                            .accessibilityHint("Shows the portion of the image visible in the panel")
                        }
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 5)
                                .onChanged { value in
                                    guard let crop = currentCrop else { return }

                                    if overlayDragMode == .none {
                                        let visRect = computeVisibleRect(
                                            crop,
                                            imageSize: image.size,
                                            container: geo.size
                                        )
                                        overlayDragMode = CropPreviewView.detectDragMode(
                                            visibleRect: visRect,
                                            startLocation: value.startLocation
                                        )
                                        dragBaseOrigin = visRect.origin
                                        dragBaseSize = visRect.size
                                        dragBaseSourceRect = crop.sourceRect
                                        if overlayDragMode != .none {
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

    // MARK: - Coordinate Conversion

    private func computeVisibleRect(_ crop: CropInfo, imageSize: CGSize, container: CGSize) -> CGRect {
        CropManager.sourceRectInContainer(crop, imageSize: imageSize, container: container)
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

            viewModel.applyOverlayCrop(
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

        viewModel.applyOverlayCrop(
            panelId: panel.id,
            sourceRect: CGRect(x: clampedOriginX, y: clampedOriginY, width: sourceSize.width, height: sourceSize.height)
        )
    }
}

enum OverlayDragMode {
    case none, drag, resizeBottomRight, resizeTopRight, resizeBottomLeft, resizeTopLeft
}

struct CropPreviewView: View {
    let nsImage: NSImage
    let imageSize: CGSize
    let crop: CropInfo?
    let containerSize: CGSize

    var body: some View {
        ZStack {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: containerSize.width, height: containerSize.height)
                .clipped()

            if let crop {
                dimOverlay(crop: crop, container: containerSize)
            }
        }
    }

    private func dimOverlay(crop: CropInfo, container: CGSize) -> some View {
        let visible = CropManager.sourceRectInContainer(crop, imageSize: imageSize, container: container)

        return ZStack {
            Path { path in
                path.addRect(CGRect(x: 0, y: 0, width: container.width, height: container.height))
                path.addRect(visible)
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))

            Path { path in
                path.addRect(visible)
            }
            .stroke(Color.white.opacity(0.8), lineWidth: 1.5)

            cornerHandles(for: visible)
        }
        .allowsHitTesting(false)
    }

    private func cornerHandles(for visible: CGRect) -> some View {
        let handleSize: CGFloat = 10

        return ZStack {
            ForEach(Corners.allCases, id: \.self) { corner in
                Rectangle()
                    .fill(Color.orange.opacity(0.3))
                    .frame(width: handleSize, height: handleSize)
                    .position(corner.position(for: visible, handleSize: handleSize))
            }
        }
    }

    // MARK: - Static Helpers

    static func computeVisibleRect(_ crop: CropInfo, imageSize: CGSize, container: CGSize) -> CGRect {
        CropManager.sourceRectInContainer(crop, imageSize: imageSize, container: container)
    }

    static func detectDragMode(
        visibleRect: CGRect,
        startLocation: CGPoint
    ) -> OverlayDragMode {
        let handleThreshold: CGFloat = 16

        let brDist = hypot(
            startLocation.x - visibleRect.maxX,
            startLocation.y - visibleRect.maxY
        )
        if brDist <= handleThreshold {
            return .resizeBottomRight
        }

        let trDist = hypot(
            startLocation.x - visibleRect.maxX,
            startLocation.y - visibleRect.minY
        )
        if trDist <= handleThreshold {
            return .resizeTopRight
        }

        let blDist = hypot(
            startLocation.x - visibleRect.minX,
            startLocation.y - visibleRect.maxY
        )
        if blDist <= handleThreshold {
            return .resizeBottomLeft
        }

        let tlDist = hypot(
            startLocation.x - visibleRect.minX,
            startLocation.y - visibleRect.minY
        )
        if tlDist <= handleThreshold {
            return .resizeTopLeft
        }

        if visibleRect.contains(startLocation) {
            return .drag
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
