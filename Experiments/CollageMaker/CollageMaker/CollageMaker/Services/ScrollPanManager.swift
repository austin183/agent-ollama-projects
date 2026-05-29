import AppKit
import Foundation

final class ScrollPanManager {
    private var scrollPanPanelId: UUID?
    private var scrollPanAccumulator: CGSize = .zero

    func beginScrollPan(
        panelId: UUID,
        beginCrop: @escaping (UUID) -> Void
    ) {
        scrollPanPanelId = panelId
        scrollPanAccumulator = .zero
        beginCrop(panelId)
    }

    func accumulateDelta(_ delta: CGSize, sensitivity: CGFloat) {
        guard scrollPanPanelId != nil else { return }
        scrollPanAccumulator.width += delta.width * sensitivity
        scrollPanAccumulator.height += delta.height * sensitivity
    }

    func endScrollPan() {
        scrollPanPanelId = nil
        scrollPanAccumulator = .zero
    }

    var hasActivePan: Bool {
        scrollPanPanelId != nil
    }

    var activePanelId: UUID? {
        scrollPanPanelId
    }

    var accumulator: CGSize {
        scrollPanAccumulator
    }
}
