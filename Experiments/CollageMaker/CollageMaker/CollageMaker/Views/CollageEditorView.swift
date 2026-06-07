import AppKit
import CoreGraphics
import OSLog
import SwiftUI

private let logger = Logger(
    subsystem: "austin183.indie.CollageMaker",
    category: "Editor"
)

enum TitleResizeEdge: Equatable {
    case none, left, right
}

struct CollageEditorView: View {
    @Bindable var viewModel: CollageViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gestureCoordinator = GestureCoordinator()


    private var titleCanvasFrame: CGRect? {
        viewModel.cachedTitleCanvasFrame
    }

    private var titleMinWidth: CGFloat {
        viewModel.cachedTitleMinWidth
    }

    private var layoutTitleFrame: CGRect {
        titleCanvasFrame ?? CGRect.zero
    }

    var body: some View {
        if viewModel.isLayeredMode || viewModel.previewImage != nil {
            GeometryReader { geometry in
                let panelFrames = viewModel.panels.reduce(into: [UUID: CGRect]()) { dict, panel in
                    dict[panel.id] = canvasToPreviewFrame(panel.frame, in: geometry.size)
                }
                let panelGeometries = Dictionary(uniqueKeysWithValues: viewModel.panels.map { ($0.id, $0.geometry) })
                let titleFrame = titleCanvasFrame.map { canvasToPreviewFrame($0, in: geometry.size) }

                ZStack {
                    if viewModel.isLayeredMode {
                        if let bg = viewModel.previewBackgroundImage {
                            Image(nsImage: bg)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        }

                        ForEach(viewModel.panels) { panel in
                            PanelOverlay(
                                panel: panel,
                                scaledFrame: panelFrames[panel.id],
                                viewModel: viewModel
                            )
                        }

                        if let titleImg = viewModel.titleImage {
                            Image(nsImage: titleImg)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        }
                    } else if let previewImage = viewModel.previewImage {
                        Image(nsImage: previewImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .id("preview")
                    }

                    if !viewModel.isLiveGesturing, let scaled = titleFrame, !viewModel.title.isEmpty {
                        Rectangle()
                            .fill(Color.clear)
                            .stroke(Color.orange, lineWidth: 1.5)
                            .frame(width: scaled.width, height: scaled.height)
                            .position(x: scaled.midX, y: scaled.midY)
                            .contentShape(Rectangle())
                            .help("Drag to reposition title")

                        Rectangle()
                            .fill(Color.orange.opacity(0.3))
                            .frame(width: 8, height: scaled.height)
                            .position(x: scaled.minX, y: scaled.midY)
                            .help("Drag to resize title width")

                        Rectangle()
                            .fill(Color.orange.opacity(0.3))
                            .frame(width: 8, height: scaled.height)
                            .position(x: scaled.maxX, y: scaled.midY)
                            .help("Drag to resize title width")
                    }

                    if let sourceId = gestureCoordinator.dragSourcePanelId,
                        let scaledFrame = panelFrames[sourceId],
                        let sourcePanel = viewModel.panels.first(where: { $0.id == sourceId }) {
                        PanelShape(geometry: sourcePanel.geometry)
                            .fill(Color.clear)
                            .stroke(Color.cyan, lineWidth: 2.5)
                            .frame(width: scaledFrame.width, height: scaledFrame.height)
                            .position(x: scaledFrame.midX, y: scaledFrame.midY)
                    }

                    if let targetId = gestureCoordinator.dragTargetPanelId,
                        let scaledFrame = panelFrames[targetId],
                        targetId != gestureCoordinator.dragSourcePanelId,
                        let targetPanel = viewModel.panels.first(where: { $0.id == targetId }) {
                        PanelShape(geometry: targetPanel.geometry)
                            .fill(Color.clear)
                            .stroke(Color.green, lineWidth: 2.5)
                            .frame(width: scaledFrame.width, height: scaledFrame.height)
                            .position(x: scaledFrame.midX, y: scaledFrame.midY)
                    }

                    if let cursorLoc = gestureCoordinator.dragCursorLocation,
                       gestureCoordinator.dragSourcePanelId != nil,
                        gestureCoordinator.dragSourceImageIndex < viewModel.imageLibrary.images.count {
                        Image(nsImage: viewModel.imageLibrary.images[gestureCoordinator.dragSourceImageIndex].thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                            .opacity(0.7)
                            .position(cursorLoc)
                    }
                }
                .overlay {
                    ScrollPanView(
                        selectedPanelId: viewModel.selectedPanelId,
                        onPanBegan: { id in
                            self.viewModel.beginGestureUndo()
                            self.viewModel.isLiveGesturing = true
                            self.viewModel.beginScrollPan(panelId: id)
                            return true
                        },
                        onPanChanged: { delta in
                            self.viewModel.scrollPanDelta(delta)
                        },
                        onPanEnded: {
                            self.viewModel.isLiveGesturing = false
                            self.viewModel.endGestureUndo(actionName: "Adjust Crop")
                            let panelId = self.viewModel.cropManager.scrollPanActivePanelId
                            self.viewModel.endScrollPan()
                            if let panelId {
                                self.viewModel.updatePanelPreview(panelId: panelId)
                            }
                        }
                    )
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { value in
                            if !gestureCoordinator.dragTitleLocked {
                                guard let titleCanvas = titleCanvasFrame else { return }
                                let handler = TitleDragHandler(
                                    titleCanvasFrame: titleCanvas,
                                    previewSize: geometry.size
                                )
                                switch handler.hitTest(at: value.startLocation) {
                                case .resize(let edge):
                                    gestureCoordinator.dragTitleLocked = true
                                    gestureCoordinator.titleResizeEdge = edge
                                    viewModel.isDraggingTitle = true
                                    gestureCoordinator.oldTitleStyle = viewModel.titleStyle
                                    return
                                case .drag:
                                    gestureCoordinator.dragTitleOffset = handler.computeDragOffset(
                                        startLocation: value.startLocation
                                    )
                                    gestureCoordinator.dragTitleLocked = true
                                    gestureCoordinator.titleResizeEdge = .none
                                    viewModel.isDraggingTitle = true
                                    gestureCoordinator.oldTitleStyle = viewModel.titleStyle
                                    return
                                case .none:
                                    break
                                }
                                return
                            }

                            let canvasSize = SizeConstants.defaultCanvasSize
                            if gestureCoordinator.titleResizeEdge != .none,
                               let tf = titleCanvasFrame {
                                let handler = TitleDragHandler(
                                    titleCanvasFrame: tf,
                                    previewSize: geometry.size
                                )
                                let (newWidth, posDelta) = handler.computeResizeWidth(
                                    screenLocation: value.location,
                                    edge: gestureCoordinator.titleResizeEdge,
                                    currentFrame: tf,
                                    minWidth: titleMinWidth,
                                    canvasSize: canvasSize
                                )
                                var style = viewModel.titleStyle
                                style.width = newWidth
                                style.positionX = style.positionX + posDelta
                                viewModel.titleStyle = style
                            } else {
                                guard let tf = titleCanvasFrame else { return }
                                let handler = TitleDragHandler(
                                    titleCanvasFrame: tf,
                                    previewSize: geometry.size
                                )
                                let (positionX, positionY) = handler.computeDragPosition(
                                    screenLocation: value.location,
                                    offset: gestureCoordinator.dragTitleOffset,
                                    canvasSize: canvasSize
                                )
                                var style = viewModel.titleStyle
                                style.positionX = positionX
                                style.positionY = positionY
                                viewModel.titleStyle = style
                            }
                        }
                        .onEnded { _ in
                            if gestureCoordinator.dragTitleLocked {
                                if let oldStyle = gestureCoordinator.oldTitleStyle {
                                    viewModel.registerTitleStyleUndo(oldStyle: oldStyle)
                                }
                                gestureCoordinator.oldTitleStyle = nil
                                viewModel.isDraggingTitle = false
                                gestureCoordinator.dragTitleLocked = false
                                gestureCoordinator.titleResizeEdge = .none
                                gestureCoordinator.dragTitleOffset = .zero
                                viewModel.finishTitleDrag()
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { value in
                            guard !viewModel.isDraggingTitle else { return }

                            if gestureCoordinator.dragSourcePanelId == nil {
                                if let tc = titleCanvasFrame {
                                    let handler = TitleDragHandler(
                                        titleCanvasFrame: tc,
                                        previewSize: geometry.size
                                    )
                                    if handler.hitTest(at: value.startLocation) != .none {
                                        return
                                    }
                                }
                                if let id = panelAt(location: value.startLocation, panelFrames: panelFrames, panelGeometries: panelGeometries, previewSize: geometry.size) {
                                    gestureCoordinator.dragSourcePanelId = id
                                    if let imgIdx = viewModel.getEffectiveImageIndex(for: id) {
                                        gestureCoordinator.dragSourceImageIndex = imgIdx
                                    }
                                }
                            }
                            if gestureCoordinator.dragSourcePanelId != nil {
                                gestureCoordinator.dragTargetPanelId = panelAt(location: value.location, panelFrames: panelFrames, panelGeometries: panelGeometries, previewSize: geometry.size)
                                gestureCoordinator.dragCursorLocation = value.location
                            }
                        }
                        .onEnded { value in
                            guard !viewModel.isDraggingTitle else {
                                gestureCoordinator.dragSourcePanelId = nil
                                gestureCoordinator.dragTargetPanelId = nil
                                gestureCoordinator.dragCursorLocation = nil
                                return
                            }
                            if let sourceId = gestureCoordinator.dragSourcePanelId,
                                let targetId = panelAt(location: value.location, panelFrames: panelFrames, panelGeometries: panelGeometries, previewSize: geometry.size),
                               sourceId != targetId {
                                viewModel.swapPanelImages(sourceId: sourceId, targetId: targetId)
                            }
                            gestureCoordinator.dragSourcePanelId = nil
                            gestureCoordinator.dragTargetPanelId = nil
                            gestureCoordinator.dragCursorLocation = nil
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            if gestureCoordinator.pinchPanelId == nil, let id = viewModel.selectedPanelId {
                                gestureCoordinator.pinchPanelId = id
                                viewModel.beginPinch(panelId: id)
                                viewModel.beginGestureUndo()
                                viewModel.isLiveGesturing = true
                            }
                            if gestureCoordinator.pinchPanelId != nil {
                                viewModel.pinch(magnification: value)
                                if gestureCoordinator.shouldProcessPinch() {
                                    viewModel.applyPinchLive()
                                }
                            }
                        }
                        .onEnded { _ in
                            viewModel.isLiveGesturing = false
                            if let id = gestureCoordinator.pinchPanelId {
                                viewModel.applyPinch(panelId: id)
                                viewModel.endGestureUndo(actionName: "Adjust Crop")
                            }
                            gestureCoordinator.pinchPanelId = nil
                        }
                )
                .onTapGesture { location in
                    if let titleFrame, titleFrame.contains(location) {
                        return
                    }
                    if let id = panelAt(location: location, panelFrames: panelFrames, panelGeometries: panelGeometries, previewSize: geometry.size) {
                        viewModel.selectedPanelId = id
                        if let panel = viewModel.panels.first(where: { $0.id == id }),
                           let frame = panelFrames[id] {
                            logger.info("Selected panel idx=\(panel.imageIndex), canvas=\(DebugHelpers.rectStr(panel.frame)), scaled=\(DebugHelpers.rectStr(frame)), tap=\(DebugHelpers.pointStr(location)), contains=\(frame.contains(location))")
                        }
                    } else {
                        viewModel.selectedPanelId = nil
                                logger.info("Deselected panel, tap=\(DebugHelpers.pointStr(location))")
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "No Images",
                systemImage: "photo.badge.plus",
                description: Text("Add images to get started")
            )
        }
    }

    private func panelAt(location: CGPoint, panelFrames: [UUID: CGRect], panelGeometries: [UUID: PanelGeometry], previewSize: CGSize) -> UUID? {
        if let id = CropManager.hitTestPanel(at: location, panelFrames: panelFrames, panelGeometries: panelGeometries, previewSize: previewSize),
           let panel = viewModel.panels.first(where: { $0.id == id }),
           let frame = panelFrames[id] {
            logger.debug("panelAt: idx=\(panel.imageIndex) frame=\(DebugHelpers.rectStr(frame)) tap=\(DebugHelpers.pointStr(location)) hits=true")
            return id
        }
        return nil
    }

    private func canvasToPreviewFrame(_ canvasRect: CGRect, in previewSize: CGSize) -> CGRect {
        CropManager.canvasToPreviewFrame(canvasRect, in: previewSize)
    }
}

private struct PanelShape: Shape {
    let geometry: PanelGeometry

    func path(in rect: CGRect) -> Path {
        switch geometry {
        case .rect:
            return Path(rect)
        case .path(let cgPath, let boundingRect):
            guard boundingRect.width > 0, boundingRect.height > 0 else {
                return Path(rect)
            }
            let scaleX = rect.width / boundingRect.width
            let scaleY = rect.height / boundingRect.height
            var t = CGAffineTransform(translationX: -boundingRect.origin.x * scaleX, y: -boundingRect.origin.y * scaleY)
            t = t.scaledBy(x: scaleX, y: scaleY)
            if let transformed = cgPath.copy(using: &t) {
                return Path(transformed)
            }
            return Path(rect)
        }
    }
}

private struct PanelHitArea: View {
    let panel: ImagePanel
    let frame: CGRect
    let viewModel: CollageViewModel
    let imageIndex: Int?

    var body: some View {
        PanelShape(geometry: panel.geometry)
            .fill(Color.clear)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }
}

private struct PanelOverlay: View {
    let panel: ImagePanel
    let scaledFrame: CGRect?
    let viewModel: CollageViewModel

    var body: some View {
        ZStack {
            if viewModel.isLayeredMode,
               let renderedImage = viewModel.panelRenderedImages[panel.id],
               let frame = scaledFrame {
                Image(nsImage: renderedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }

            if let frame = scaledFrame {
                let imageIndex = viewModel.getEffectiveImageIndex(for: panel.id)
                PanelHitArea(
                    panel: panel,
                    frame: frame,
                    viewModel: viewModel,
                    imageIndex: imageIndex
                )
                .accessibilityLabel("Image panel")
                .accessibilityAddTraits(viewModel.selectedPanelId == panel.id ? [.isSelected] : [])
                .contextMenu {
                    Button("Reset Crop") {
                        viewModel.resetCrop(panelId: panel.id)
                    }
                    Divider()
                    if let idx = imageIndex {
                        Button("Remove Image", role: .destructive) {
                            viewModel.removeImage(at: idx)
                        }
                    }
                }
            }

            if viewModel.selectedPanelId == panel.id, let frame = scaledFrame {
                PanelShape(geometry: panel.geometry)
                    .fill(Color.clear)
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
    }
}
