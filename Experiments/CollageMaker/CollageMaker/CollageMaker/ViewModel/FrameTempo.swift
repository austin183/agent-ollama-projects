import Foundation

/// Central timing constants for render throttles and preview debounces.
///
/// Adjust values here to tune FPS across all gesture types.
/// Reference table (fps = 1000 / ms):
///
/// | ms  | fps  | Typical use                              |
/// |-----|------|------------------------------------------|
/// | 0   | –    | Immediate dispatch, no delay             |
/// | 6   | ~167 | High-responsiveness live preview         |
/// | 10  | ~100 | Near-instant with slight coalescing      |
/// | 16  | ~60  | Display-native refresh rate              |
/// | 20  | ~50  | Smooth with reduced CPU load             |
/// | 33  | ~30  | Video-rate, noticeable vs 60fps          |
/// | 50  | ~20  | Functional but choppy                    |
/// | 150 | ~7   | Post-interaction settle before side effects |
/// | 300 | ~3   | Disk write throttle                      |
enum FrameTempo {
    // MARK: Gesture Render Throttles
    static let scrollRenderInterval: Duration = .milliseconds(20)
    static let overlayRenderInterval: Duration = .milliseconds(20)

    // MARK: Gesture Preview Debounces
    static let panPreviewDebounce: Duration = .milliseconds(20)
    static let pinchPreviewDebounce: Duration = .milliseconds(10)
    static let overlayRenderDebounce: Duration = .milliseconds(20)
    static let scrollPanPreviewDebounce: Duration = .milliseconds(20)

    // MARK: Post-Interaction Debounces
    static let layoutChangeDebounce: Duration = .milliseconds(20)
    static let backgroundColorDebounce: Duration = .milliseconds(20)
    static let fontSizeDebounce: Duration = .milliseconds(6)
    static let previewRenderDebounce: Duration = .milliseconds(20)
}
