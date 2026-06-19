import SwiftUI

/// Title interaction overlay: bounding frame and resize handles.
struct TitleInteractionOverlay: View {
    let scaledFrame: CGRect
    let isLiveGesturing: Bool

    var body: some View {
        if !isLiveGesturing {
            Rectangle()
                .fill(Color.clear)
                .stroke(Color.orange, lineWidth: 1.5)
                .frame(width: scaledFrame.width, height: scaledFrame.height)
                .position(x: scaledFrame.midX, y: scaledFrame.midY)
                .contentShape(Rectangle())
                .help("Drag to reposition title")

            Rectangle()
                .fill(Color.orange.opacity(0.3))
                .frame(width: 8, height: scaledFrame.height)
                .position(x: scaledFrame.minX, y: scaledFrame.midY)
                .help("Drag to resize title width")
                .accessibilityLabel("Resize title left edge")
                .accessibilityAddTraits(.isButton)

            Rectangle()
                .fill(Color.orange.opacity(0.3))
                .frame(width: 8, height: scaledFrame.height)
                .position(x: scaledFrame.maxX, y: scaledFrame.midY)
                .help("Drag to resize title width")
                .accessibilityLabel("Resize title right edge")
                .accessibilityAddTraits(.isButton)
        }
    }
}
