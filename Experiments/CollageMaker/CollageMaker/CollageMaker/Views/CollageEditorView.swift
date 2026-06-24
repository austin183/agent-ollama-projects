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

    var body: some View {
        if viewModel.isLayeredMode || viewModel.previewImage != nil {
            GeometryReader { geometry in
                let panelFrames = viewModel.computePanelFrames(previewSize: geometry.size)
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
                        panelGeometries: viewModel.panelGeometries
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
                    TitleDragGestureBuilder(
                        coordinator: gestureCoordinator,
                        viewModel: viewModel,
                        titleCanvasFrame: titleCanvasFrame,
                        previewSize: geometry.size
                    ).build()
                )
                .simultaneousGesture(
                    PanelSwapGestureBuilder(
                        coordinator: gestureCoordinator,
                        viewModel: viewModel,
                        titleCanvasFrame: titleCanvasFrame,
                        previewSize: geometry.size
                    ).build()
                )
                .simultaneousGesture(
                    PinchGestureBuilder(
                        coordinator: gestureCoordinator,
                        viewModel: viewModel
                    ).build()
                )
                .onTapGesture { location in
                    if let titleFrame, titleFrame.contains(location) {
                        return
                    }
                    if let id = viewModel.hitPanel(at: location, previewSize: geometry.size) {
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
    var panelIndex: Int?

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
                .accessibilityLabel({
                    var label = "Image panel"
                    if let idx = panelIndex {
                        label = "Panel \(idx + 1)"
                        if let imageIndex, imageIndex < viewModel.images.count {
                            label += ", \(viewModel.images[imageIndex].filename)"
                        }
                    }
                    return label
                }())
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
