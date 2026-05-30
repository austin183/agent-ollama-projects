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
}
