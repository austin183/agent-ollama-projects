import AppKit
import CoreGraphics
import OSLog
import SwiftUI

private let logger = Logger(
    subsystem: "austin183.indie.CollageMaker",
    category: "Editor"
)

private enum TitleResizeEdge {
    case none, left, right
}

private let resizeHandleWidth: CGFloat = 8

struct CollageEditorView: View {
    @Bindable var viewModel: CollageViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pinchPanelId: UUID?
    @State private var scaledPanelFrames: [UUID: CGRect] = [:]
    @State private var scaledTitleFrame: CGRect?
    @State private var dragTitleLocked = false
    @State private var titleResizeEdge: TitleResizeEdge = .none
    @State private var dragSourcePanelId: UUID?
    @State private var dragTargetPanelId: UUID?
    @State private var dragCursorLocation: CGPoint?
    @State private var dragSourceImageIndex: Int = 0
    @State private var oldTitleStyle: TitleStyle?
    @State private var dragTitleOffset = CGPoint.zero

    private struct LayoutKey: Equatable {
        let width: Double
        let height: Double
        let panelIds: [UUID]
        let cropKeys: [UUID]
        let titleFrameX: Double
        let titleFrameY: Double
        let titleFrameW: Double
        let titleFrameH: Double
    }

    private var titleCanvasFrame: CGRect? {
        guard !viewModel.titleAttrString.string.isEmpty else { return nil }
        let style = viewModel.titleStyle
        let canvasSize = CanvasConfig.defaultCanvasSize

        let metrics = TitleMetrics(
            preparedString: TitleMetrics.prepare(viewModel.titleAttrString, style: style),
            style: style
        )

        let drawWidth = style.effectiveWidth(canvasWidth: canvasSize.width)
        let boundingBox = metrics.boundingBox

        let anchorX = style.positionX * canvasSize.width
        let drawX = anchorX - drawWidth / 2
        let anchorYcg = canvasSize.height - style.positionY * canvasSize.height
        let baselineY = anchorYcg - boundingBox.height
        let textTop = baselineY + boundingBox.origin.y

        return CGRect(
            x: drawX,
            y: textTop - 12,
            width: drawWidth,
            height: boundingBox.height + 24
        )
    }

    private var titleMinWidth: CGFloat {
        guard !viewModel.titleAttrString.string.isEmpty else { return 0 }
        let metrics = TitleMetrics(
            preparedString: TitleMetrics.prepare(viewModel.titleAttrString, style: viewModel.titleStyle),
            style: viewModel.titleStyle
        )
        return metrics.minNaturalWidth
    }

    private var layoutTitleFrame: CGRect {
        titleCanvasFrame ?? CGRect.zero
    }

    var body: some View {
        if let previewImage = viewModel.previewImage {
            GeometryReader { geometry in
                ZStack {
                    Image(nsImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .id("preview")

                    ForEach(viewModel.panels) { panel in
                        if let scaledFrame = scaledPanelFrames[panel.id] {
                            let imageIndex = viewModel.getEffectiveImageIndex(for: panel.id)
                            PanelHitArea(
                                panel: panel,
                                frame: scaledFrame,
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
                    }

                    if let scaled = scaledTitleFrame, !viewModel.title.isEmpty {
                        Rectangle()
                            .fill(Color.clear)
                            .stroke(Color.orange, lineWidth: 1.5)
                            .frame(width: scaled.width, height: scaled.height)
                            .position(x: scaled.midX, y: scaled.midY)
                            .contentShape(Rectangle())
                            .help("Drag to reposition title")

                        Rectangle()
                            .fill(Color.orange.opacity(0.3))
                            .frame(width: resizeHandleWidth, height: scaled.height)
                            .position(x: scaled.minX, y: scaled.midY)
                            .help("Drag to resize title width")

                        Rectangle()
                            .fill(Color.orange.opacity(0.3))
                            .frame(width: resizeHandleWidth, height: scaled.height)
                            .position(x: scaled.maxX, y: scaled.midY)
                            .help("Drag to resize title width")
                    }

                    if let sourceId = dragSourcePanelId,
                       let scaledFrame = scaledPanelFrames[sourceId] {
                        Rectangle()
                            .fill(Color.clear)
                            .stroke(Color.cyan, lineWidth: 2.5)
                            .frame(width: scaledFrame.width, height: scaledFrame.height)
                            .position(x: scaledFrame.midX, y: scaledFrame.midY)
                    }

                    if let targetId = dragTargetPanelId,
                       let scaledFrame = scaledPanelFrames[targetId],
                       targetId != dragSourcePanelId {
                        Rectangle()
                            .fill(Color.clear)
                            .stroke(Color.green, lineWidth: 2.5)
                            .frame(width: scaledFrame.width, height: scaledFrame.height)
                            .position(x: scaledFrame.midX, y: scaledFrame.midY)
                    }

                    if let cursorLoc = dragCursorLocation,
                       dragSourcePanelId != nil,
                       dragSourceImageIndex < viewModel.images.count {
                        Image(nsImage: viewModel.images[dragSourceImageIndex].thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                            .opacity(0.7)
                            .position(cursorLoc)
                    }

                    if let selectedId = viewModel.selectedPanelId,
                        let selectedPanel = viewModel.panels.first(where: { $0.id == selectedId }),
                        let scaledFrame = scaledPanelFrames[selectedId] {
                        Rectangle()
                            .fill(Color.clear)
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: scaledFrame.width, height: scaledFrame.height)
                            .position(x: scaledFrame.midX, y: scaledFrame.midY)
                            .onAppear {
                                logger.info("Highlight: panel \(DebugHelpers.rectStr(selectedPanel.frame)), scaled \(DebugHelpers.rectStr(scaledFrame)), preview \(DebugHelpers.sizeStr(geometry.size))")
                            }
                    } else if let selectedId = viewModel.selectedPanelId {
                        Rectangle()
                            .fill(Color.clear)
                            .onAppear {
                                logger.info("Highlight: panel id \(selectedId.uuidString) NOT FOUND in panels (count \(viewModel.panels.count))")
                            }
                    }
                }
                .overlay {
                    ScrollPanView(
                        selectedPanelId: viewModel.selectedPanelId,
                        onPanBegan: { id in
                            self.viewModel.undoManager.beginUndoGrouping()
                            self.viewModel.beginScrollPan(panelId: id)
                            return true
                        },
                        onPanChanged: { delta in
                            self.viewModel.scrollPanDelta(delta)
                        },
                        onPanEnded: {
                            self.viewModel.undoManager.setActionName("Adjust Crop")
                            self.viewModel.undoManager.endUndoGrouping()
                            self.viewModel.endScrollPan()
                        }
                    )
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { value in
                            if !dragTitleLocked {
                                if let tf = scaledTitleFrame {
                                    let handleThreshold = resizeHandleWidth + 2
                                    if tf.minX - handleThreshold <= value.startLocation.x,
                                       value.startLocation.x <= tf.minX + handleThreshold,
                                       tf.minY <= value.startLocation.y, value.startLocation.y <= tf.maxY {
                                         dragTitleLocked = true
                                         titleResizeEdge = .left
                                         viewModel.isDraggingTitle = true
                                         oldTitleStyle = viewModel.titleStyle
                                         return
                                    } else if tf.maxX - handleThreshold <= value.startLocation.x,
                                               value.startLocation.x <= tf.maxX + handleThreshold,
                                               tf.minY <= value.startLocation.y, value.startLocation.y <= tf.maxY {
                                         dragTitleLocked = true
                                         titleResizeEdge = .right
                                         viewModel.isDraggingTitle = true
                                         oldTitleStyle = viewModel.titleStyle
                                         return
                                } else if tf.contains(value.startLocation) {
                                      let startCanvas = CropManager.screenToCanvasPoint(value.startLocation, in: geometry.size)
                                      if let tfCanvas = titleCanvasFrame {
                                          let titleCenterCanvasY = tfCanvas.minY + tfCanvas.height / 2
                                          dragTitleOffset = CGPoint(
                                              x: tfCanvas.midX - startCanvas.x,
                                              y: titleCenterCanvasY - startCanvas.y
                                          )
                                      }
                                      dragTitleLocked = true
                                      titleResizeEdge = .none
                                      viewModel.isDraggingTitle = true
                                      oldTitleStyle = viewModel.titleStyle
                                    }
                                }
                                return
                            }

                            let canvasSize = CanvasConfig.defaultCanvasSize
                            let canvasPoint = CropManager.screenToCanvasPoint(value.location, in: geometry.size)

                            if titleResizeEdge != .none {
                                let canvasX = canvasPoint.x
                                var style = viewModel.titleStyle
                                let minX = titleMinWidth
                                if titleResizeEdge == .right {
                                    if let tf = titleCanvasFrame {
                                        let newWidth = max(minX, canvasX - tf.minX)
                                        style.width = newWidth
                                    }
                                } else {
                                    if let tf = titleCanvasFrame {
                                        let newWidth = max(minX, tf.maxX - canvasX)
                                        let dx = (tf.width - newWidth) / 2
                                        style.width = newWidth
                                        style.positionX = style.positionX + dx / canvasSize.width
                                    }
                                }
                                viewModel.titleStyle = style
                            } else {
                                var style = viewModel.titleStyle
                                style.positionX = (canvasPoint.x + dragTitleOffset.x) / canvasSize.width
                                style.positionY = 1.0 - (canvasPoint.y + dragTitleOffset.y) / canvasSize.height
                                viewModel.titleStyle = style
                            }
                        }
                        .onEnded { _ in
                            if dragTitleLocked {
                                if let oldStyle = oldTitleStyle {
                                    viewModel.undoManager.registerUndo(withTarget: viewModel) { target in
                                        target.titleStyle = oldStyle
                                    }
                                    viewModel.undoManager.setActionName("Move Title")
                                }
                                oldTitleStyle = nil
                                viewModel.isDraggingTitle = false
                                dragTitleLocked = false
                                titleResizeEdge = .none
                                dragTitleOffset = .zero
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { value in
                            guard !viewModel.isDraggingTitle else { return }

                            if dragSourcePanelId == nil {
                                if let titleFrame = scaledTitleFrame {
                                    let handleThreshold = resizeHandleWidth + 2
                                    let inResizeHandle = (titleFrame.minX - handleThreshold <= value.startLocation.x &&
                                        value.startLocation.x <= titleFrame.minX + handleThreshold &&
                                        titleFrame.minY <= value.startLocation.y &&
                                        value.startLocation.y <= titleFrame.maxY) ||
                                        (titleFrame.maxX - handleThreshold <= value.startLocation.x &&
                                        value.startLocation.x <= titleFrame.maxX + handleThreshold &&
                                        titleFrame.minY <= value.startLocation.y &&
                                        value.startLocation.y <= titleFrame.maxY)
                                    if titleFrame.contains(value.startLocation) || inResizeHandle {
                                        return
                                    }
                                }
                                if let id = panelAt(location: value.startLocation, in: geometry.size) {
                                    dragSourcePanelId = id
                                    if let imgIdx = viewModel.getEffectiveImageIndex(for: id) {
                                        dragSourceImageIndex = imgIdx
                                    }
                                }
                            }
                            if dragSourcePanelId != nil {
                                dragTargetPanelId = panelAt(location: value.location, in: geometry.size)
                                dragCursorLocation = value.location
                            }
                        }
                        .onEnded { value in
                            guard !viewModel.isDraggingTitle else {
                                dragSourcePanelId = nil
                                dragTargetPanelId = nil
                                dragCursorLocation = nil
                                return
                            }
                            if let sourceId = dragSourcePanelId,
                               let targetId = panelAt(location: value.location, in: geometry.size),
                               sourceId != targetId {
                                viewModel.swapPanelImages(sourceId: sourceId, targetId: targetId)
                            }
                            dragSourcePanelId = nil
                            dragTargetPanelId = nil
                            dragCursorLocation = nil
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            if pinchPanelId == nil, let id = viewModel.selectedPanelId {
                                pinchPanelId = id
                                viewModel.beginPinch(panelId: id)
                                viewModel.undoManager.beginUndoGrouping()
                            }
                            if pinchPanelId != nil {
                                viewModel.pinch(magnification: value)
                                viewModel.applyPinchLive()
                            }
                        }
                        .onEnded { _ in
                            if let id = pinchPanelId {
                                viewModel.applyPinch(panelId: id)
                                viewModel.undoManager.setActionName("Adjust Crop")
                                viewModel.undoManager.endUndoGrouping()
                            }
                            pinchPanelId = nil
                        }
                )
                .onTapGesture { location in
                    if let titleFrame = scaledTitleFrame, titleFrame.contains(location) {
                        return
                    }
                    if let id = panelAt(location: location, in: geometry.size) {
                        viewModel.selectedPanelId = id
                        if let panel = viewModel.panels.first(where: { $0.id == id }),
                           let sf = scaledPanelFrames[id] {
                            logger.info("Selected panel idx=\(panel.imageIndex), canvas=\(DebugHelpers.rectStr(panel.frame)), scaled=\(DebugHelpers.rectStr(sf)), tap=\(DebugHelpers.pointStr(location)), contains=\(sf.contains(location))")
                        }
                    } else {
                        viewModel.selectedPanelId = nil
                                logger.info("Deselected panel, tap=\(DebugHelpers.pointStr(location))")
                    }
                }
                .onChange(of: LayoutKey(width: Double(geometry.size.width), height: Double(geometry.size.height), panelIds: viewModel.panels.map { $0.id }, cropKeys: Array(viewModel.cropMap.keys), titleFrameX: layoutTitleFrame.origin.x, titleFrameY: layoutTitleFrame.origin.y, titleFrameW: layoutTitleFrame.width, titleFrameH: layoutTitleFrame.height)) { _, _ in
                    scaledPanelFrames = viewModel.panels.reduce(into: [:]) { dict, panel in
                        dict[panel.id] = canvasToPreviewFrame(panel.frame, in: geometry.size)
                    }
                    if let titleFrame = titleCanvasFrame {
                        scaledTitleFrame = canvasToPreviewFrame(titleFrame, in: geometry.size)
                    } else {
                        scaledTitleFrame = nil
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

    private func panelAt(location: CGPoint, in previewSize: CGSize) -> UUID? {
        _ = previewSize
        if let id = CropManager.hitTestPanel(at: location, panelFrames: scaledPanelFrames) {
            if let panel = viewModel.panels.first(where: { $0.id == id }),
               let frame = scaledPanelFrames[id] {
                logger.debug("panelAt: idx=\(panel.imageIndex) frame=\(DebugHelpers.rectStr(frame)) tap=\(DebugHelpers.pointStr(location)) hits=true")
                return id
            }
        }
        return nil
    }

    private func canvasToPreviewFrame(_ canvasRect: CGRect, in previewSize: CGSize) -> CGRect {
        CropManager.canvasToPreviewFrame(canvasRect, in: previewSize)
    }
}

private struct PanelHitArea: View {
    let panel: ImagePanel
    let frame: CGRect
    let viewModel: CollageViewModel
    let imageIndex: Int?

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }
}
