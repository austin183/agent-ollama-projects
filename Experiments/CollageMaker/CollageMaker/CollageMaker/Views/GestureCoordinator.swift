import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class GestureCoordinator {
    var pinchPanelId: UUID?
    var dragTitleLocked: Bool = false
    var titleResizeEdge: TitleResizeEdge = .none
    var dragSourcePanelId: UUID?
    var dragTargetPanelId: UUID?
    var dragCursorLocation: CGPoint?
    var dragSourceImageIndex: Int = 0
    var oldTitleStyle: TitleStyle?
    var dragTitleOffset: CGPoint = .zero

    private var lastPinchTime: ContinuousClock.Instant = .now
    private let pinchThrottleInterval: Duration = .milliseconds(16)

    func shouldProcessPinch() -> Bool {
        let now = ContinuousClock.now
        if now - lastPinchTime >= pinchThrottleInterval {
            lastPinchTime = now
            return true
        }
        return false
    }
}
