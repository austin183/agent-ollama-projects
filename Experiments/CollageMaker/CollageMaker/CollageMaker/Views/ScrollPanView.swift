import AppKit
import SwiftUI

private let scrollThrottleInterval = Duration.milliseconds(16)

struct ScrollPanView: NSViewRepresentable {
    let selectedPanelId: UUID?
    let onPanBegan: (UUID) -> Bool
    let onPanChanged: (CGSize) -> Void
    let onPanEnded: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ScrollCaptureView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ScrollCaptureView else { return }
        view.selectedPanelId = selectedPanelId
        view.onPanBegan = onPanBegan
        view.onPanChanged = onPanChanged
        view.onPanEnded = onPanEnded
    }

    class ScrollCaptureView: NSView {
        var selectedPanelId: UUID?
        var onPanBegan: (UUID) -> Bool = { _ in false }
        var onPanChanged: (CGSize) -> Void = { _ in }
        var onPanEnded: () -> Void = {}
        private var activePanelId: UUID?
        private var lastScrollTime: ContinuousClock.Instant = ContinuousClock.now

        override func scrollWheel(with event: NSEvent) {
            guard event.type == .scrollWheel else {
                super.scrollWheel(with: event)
                return
            }

            let deltaX = event.scrollingDeltaX
            let deltaY = event.scrollingDeltaY

            let baseMultiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1.0 : 10.0

            switch event.phase {
            case .began:
                if activePanelId == nil,
                   let id = selectedPanelId, onPanBegan(id) {
                    activePanelId = id
                }
            case .changed:
                if activePanelId != nil {
                    let now = ContinuousClock.now
                    if now - lastScrollTime >= scrollThrottleInterval {
                        lastScrollTime = now
                        onPanChanged(CGSize(width: deltaX * baseMultiplier, height: deltaY * baseMultiplier))
                    }
                }
            case .ended, .cancelled:
                if activePanelId != nil {
                    onPanEnded()
                }
                activePanelId = nil
            default:
                break
            }
        }
    }
}
