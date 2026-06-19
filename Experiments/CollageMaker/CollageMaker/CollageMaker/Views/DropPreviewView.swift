import AppKit
import SwiftUI

/// Drag-and-drop preview overlays: source highlight, target highlight, cursor thumbnail.
struct DropPreviewView: View {
    let gestureCoordinator: GestureCoordinator
    let viewModel: CollageViewModel
    let panelFrames: [UUID: CGRect]
    let panelGeometries: [UUID: PanelGeometry]

    var body: some View {
        Group {
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
               gestureCoordinator.dragSourceImageIndex < viewModel.images.count {
                Image(nsImage: viewModel.images[gestureCoordinator.dragSourceImageIndex].thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .opacity(0.7)
                    .position(cursorLoc)
            }
        }
    }
}
