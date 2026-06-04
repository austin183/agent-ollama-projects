import Combine
import CoreGraphics
import SwiftUI

@MainActor
final class GestureCoordinator: ObservableObject {
    @Published var pinchPanelId: UUID?
    @Published var dragTitleLocked: Bool = false
    @Published var titleResizeEdge: TitleResizeEdge = .none
    @Published var dragSourcePanelId: UUID?
    @Published var dragTargetPanelId: UUID?
    @Published var dragCursorLocation: CGPoint?
    @Published var dragSourceImageIndex: Int = 0
    @Published var oldTitleStyle: TitleStyle?
    @Published var dragTitleOffset: CGPoint = .zero

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
