import AppKit
import Foundation

final class ScrollPanManager {
    private var scrollPanPanelId: UUID?
    private var scrollPanAccumulator: CGSize = .zero
    private var scrollCommitTimer: DispatchWorkItem?
    private var pendingCommit: (() -> Void)?

    func beginScrollPan(
        panelId: UUID,
        beginCrop: @escaping (UUID) -> Void
    ) {
        scrollPanPanelId = panelId
        scrollPanAccumulator = .zero
        beginCrop(panelId)
    }

    func scrollPanDelta(
        _ delta: CGSize,
        sensitivity: CGFloat,
        applyLive: @escaping () -> Void,
        commit: @escaping () -> Void
    ) {
        guard scrollPanPanelId != nil else { return }
        scrollPanAccumulator.width += delta.width * sensitivity
        scrollPanAccumulator.height += delta.height * sensitivity
        applyLive()
        scheduleScrollCommit(commit: commit)
    }

    func endScrollPan() {
        scrollCommitTimer?.cancel()
        scrollCommitTimer = nil
        pendingCommit = nil
        scrollPanPanelId = nil
        scrollPanAccumulator = .zero
    }

    private func scheduleScrollCommit(commit: @escaping () -> Void) {
        pendingCommit = commit
        scrollCommitTimer?.cancel()
        scrollCommitTimer = DispatchWorkItem { [weak self] in
            self?.pendingCommit?()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: scrollCommitTimer!)
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
