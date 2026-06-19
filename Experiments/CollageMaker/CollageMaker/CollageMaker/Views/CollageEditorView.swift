import AppKit
import CoreGraphics
import OSLog
import SwiftUI

private let logger = Logger(
    subsystem: "austin183.indie.CollageMaker",
    category: "Editor"
)

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
                let panelFrames = viewModel.computePanelFrames(previewSize: geometry.size)
                let panelGeometries = Dictionary(uniqueKeysWithValues: viewModel.panels.map { ($0.id, $0.geometry) })
                let titleFrame = titleCanvasFrame.map { CoordinateConverter.canvasToPreviewFrame($0, in: geometry.size, canvasSize: SizeConstants.defaultCanvasSize) }
                let canvasPreviewFrame = CoordinateConverter.canvasToPreviewFrame(CGRect(origin: .zero, size: SizeConstants.defaultCanvasSize), in: geometry.size, canvasSize: SizeConstants.defaultCanvasSize)

                ZStack {
                    CanvasBackgroundView(viewModel: viewModel, geometrySize: geometry.size)

                    PanelsOverlayView(viewModel: viewModel, panelFrames: panelFrames, geometrySize: geometry.size)

                    if let scaled = titleFrame, !viewModel.title.isEmpty {
                        TitleInteractionOverlay(
                            scaledFrame: scaled,
                            isLiveGesturing: viewModel.isLiveGesturing
                        )
                    }

                    DropPreviewView(
                        gestureCoordinator: gestureCoordinator,
                        viewModel: viewModel,
                        panelFrames: panelFrames,
                        panelGeometries: panelGeometries
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 0))
                .frame(width: canvasPreviewFrame.width, height: canvasPreviewFrame.height)
                .position(x: canvasPreviewFrame.midX, y: canvasPreviewFrame.midY)
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
                            let panelId = self.viewModel.scrollPanActivePanelId
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
                                     switch viewModel.titleManager.hitTestTitle(location: value.startLocation, previewSize: geometry.size) {
                                     case .resize(let edge):
                                      gestureCoordinator.dragTitleLocked = true
                                      gestureCoordinator.titleResizeEdge = edge
                                      viewModel.isDraggingTitle = true
                                      gestureCoordinator.oldTitleStyle = viewModel.titleStyle
                                      return
                                     case .drag:
                                      gestureCoordinator.dragTitleOffset = viewModel.titleManager.computeTitleDragOffset(
                                          startLocation: value.startLocation,
                                          previewSize: geometry.size
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
                                let (newWidth, posDelta) = viewModel.titleManager.computeTitleResize(
                                    screenLocation: value.location,
                                    edge: gestureCoordinator.titleResizeEdge,
                                    previewSize: geometry.size
                                )
                                var style = viewModel.titleStyle
                                style.width = newWidth
                                style.positionX = style.positionX + posDelta
                                viewModel.titleStyle = style
                            } else {
                                guard let tf = titleCanvasFrame else { return }
                                let (positionX, positionY) = viewModel.titleManager.computeTitleDragPosition(
                                    screenLocation: value.location,
                                    offset: gestureCoordinator.dragTitleOffset,
                                    previewSize: geometry.size
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
                                    if viewModel.titleManager.hitTestTitle(location: value.startLocation, previewSize: geometry.size) == .none {
                                        return
                                    }
                                    return
                                }
                                if let id = hitPanel(at: value.startLocation, panelFrames: panelFrames, panelGeometries: panelGeometries, previewSize: geometry.size) {
                                    gestureCoordinator.dragSourcePanelId = id
                                    if let imgIdx = viewModel.getEffectiveImageIndex(for: id) {
                                        gestureCoordinator.dragSourceImageIndex = imgIdx
                                    }
                                }
                            }
                            if gestureCoordinator.dragSourcePanelId != nil {
                                gestureCoordinator.dragTargetPanelId = hitPanel(at: value.location, panelFrames: panelFrames, panelGeometries: panelGeometries, previewSize: geometry.size)
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
                                let targetId = hitPanel(at: value.location, panelFrames: panelFrames, panelGeometries: panelGeometries, previewSize: geometry.size),
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
                    if let id = hitPanel(at: location, panelFrames: panelFrames, panelGeometries: panelGeometries, previewSize: geometry.size) {
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

    private func hitPanel(at location: CGPoint, panelFrames: [UUID: CGRect], panelGeometries: [UUID: PanelGeometry], previewSize: CGSize) -> UUID? {
        if let id = CoordinateConverter.hitTestPanel(at: location, panelFrames: panelFrames, panelGeometries: panelGeometries, previewSize: previewSize, canvasSize: SizeConstants.defaultCanvasSize),
            let panel = viewModel.panels.first(where: { $0.id == id }),
           let frame = panelFrames[id] {
            logger.debug("hitPanel: idx=\(panel.imageIndex) frame=\(DebugHelpers.rectStr(frame)) tap=\(DebugHelpers.pointStr(location)) hits=true")
            return id
        }
        return nil
    }
}

struct PanelShape: Shape {
    let geometry: PanelGeometry

    func path(in rect: CGRect) -> Path {
        switch geometry {
        case .rect:
            return Path(rect)
        case .path(let cgPath, let boundingRect):
            var transform = PanelGeometry.transformForPanel(boundingRect: boundingRect, targetRect: rect)
            if let transformed = cgPath.copy(using: &transform) {
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

struct PanelOverlay: View {
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

func overlayBlendMode(from cgBlendMode: CGBlendMode?) -> BlendMode {
    guard let mode = cgBlendMode else { return .multiply }
    switch mode {
    case .multiply: return .multiply
    case .screen: return .screen
    case .overlay: return .overlay
    case .darken: return .darken
    case .colorDodge: return .colorDodge
    case .colorBurn: return .colorBurn
    case .hardLight: return .hardLight
    case .softLight: return .softLight
    case .difference: return .difference
    case .exclusion: return .exclusion
    default: return .multiply
    }
}
