# Performance Debugging — Instruments, Sanitizers, Signposts

## Contents

- Instruments templates by symptom
- Runtime sanitizers
- OSSignpost instrumentation
- Performance tests
- SwiftUI profiling

## Instruments Templates by Symptom

| Symptom | Template | What It Shows |
|---|---|---|
| Unresponsiveness / hangs | **Time Profiler** | Call tree and flame graph of main thread work |
| Memory growth / leaks | **Allocations** + **Leaks** | Allocation call stacks, live vs deallocated objects, leaked blocks |
| CPU bottlenecks | **CPU Counters** (mode: CPU Bottlenecks) | 4 categories: fetch stalls, decode stalls, non-progress, useful work |
| SwiftUI view updates | **SwiftUI** | View body calc times (>500μs orange, >1000μs red), update groups, cause-effect graphs |
| Animation hitches | **Animation Hitches** | Commit hitches (main thread) vs render hitches (render server) |
| Energy / power | **Energy Log** | Power impact of app activities |
| File I/O | **File Activity** | Disk reads/writes, synchronous I/O on main thread |

**Workflow:** Product > Profile → pick template → Record → exercise the feature → Stop → analyze timeline. Profile on a real device for higher-fidelity measurements.

### SwiftUI Template Details

- **View Body Updates lane:** Orange lines for >500μs, red for >1000μs
- **Update Groups timeline:** Identifies groups of short updates that accumulate
- **Cause-and-effect graph:** Click an update → "Show Causes" → blue nodes = your code, gray = system. Click edges to see which property changes triggered each update

To filter Time Profiler to a specific view: control-click `MyView.body` in detail view → "Show Calls Made by MyView.body". Reset with Callers/Callees → Clear Selection.

### CPU Counters (CPU Bottlenecks Mode)

1. Product > Profile → CPU Counters template → set mode to "CPU Bottlenecks"
2. Record and interact with the app
3. Click CPU Counters track → Summary: Metrics (fraction of time per category)
4. Expand thread timeline → bottleneck lanes per thread
5. Control-click a bottleneck → "Suggested Next" for detailed recording

## Runtime Sanitizers

Enable in scheme editor: Product > Scheme > Edit Scheme > Run/Test > Diagnostics.

| Tool | Detects | Overhead |
|---|---|---|
| **Address Sanitizer** | Use-after-free, buffer overflows, double-free | 2-3x memory, 2-5x slowdown |
| **Thread Sanitizer** | Data races, Swift access races, thread leaks | 5-10x memory, 2-20x slowdown (macOS only) |
| **Main Thread Checker** | AppKit/SwiftUI calls off main thread | 1-2% CPU, ~100ms launch |
| **Thread Performance Checker** | Priority inversions, non-UI work on main thread | Minimal (on by default) |
| **UB Sanitizer** | Divide-by-zero, misaligned pointers, integer overflow | ~20% CPU (C-based only) |

**Note:** ASan does NOT detect memory leaks — use Instruments Allocations/Leaks for that. TSan is macOS-only (not iOS devices).

## OSSignpost Instrumentation

Add signposts around expensive operations to make them visible in Instruments (Time Profiler, OS Logging, MetricKit):

```swift
import os.signpost

private let logger = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "performance")
private let signposter = OSSignposter(logger: logger)

func updatePreview() {
    let signpost = signposter.makeSignpostIdentifier()
    let interval = signposter.beginInterval("Preview Assembly", signpost)
    defer { signposter.endInterval("Preview Assembly", signpost, interval) }
    // ... work ...
}
```

**Signposts to add:**
- `updatePreview()` — CoreGraphics compositing time
- `regenerateLayout()` — layout math + panel generation
- `applyPanLive()` — pan application + debounce
- `analyzeSaliency()` — Vision analysis time

## Performance Tests

Use `XCTClockMetric` for wall-clock time and `XCTCPUMetric` for CPU activity:

```swift
import XCTest

@MainActor
final class PerformanceTests: XCTestCase {
    func testScrollPreviewUpdate() async throws {
        let vm = CollageViewModel(assembler: TrackingAssembler())
        vm.addImages([createTestImageItem()])

        measure(metrics: [
            XCTClockMetric(),
            XCTCPUMetric()
        ]) {
            // Simulate a scroll gesture: 20 pan deltas
            for _ in 0..<20 {
                vm.scrollPanDelta(by: CGSize(width: 5, height: 3))
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms for detached tasks
        }
    }
}
```

**Baselines:** Accept the first run as baseline, then lower as you optimize. Tests fail if runtime exceeds baseline by a significant margin.

## Test Plan Runtime Checking

Product > Test Plan > Edit Test Plan > Configurations > Runtime API Checking:

| Setting | Recommendation |
|---|---|
| Main Thread Checker | On (as Failure) |
| Address Sanitizer | On (as Warnings) during development |
| Thread Sanitizer | On (as Warnings) for concurrency-heavy code |

## Hitch vs Hang Detection in Instruments

| Tool | Detects | Threshold |
|---|---|---|
| **Hangs instrument** (in Time Profiler/CPU Profiler) | Main run loop unresponsive | >250ms default, configurable |
| **Animation Hitches template** | Late frames during scrolling/animation | Any missed deadline |
| **Xcode Organizer** | Field reports from shipping app | Population subsampling |

## Quick Profiling Checklist

When investigating a performance regression:

1. **Allocations** — Is memory growing? Check for retained undo entries, image caches, or task references
2. **SwiftUI template** — Are view bodies slow? Are update groups excessive?
3. **Time Profiler** — What code is running on the main thread during the slow interaction?
4. **Thread Performance Checker** — Is non-UI work blocking the main thread?
5. **CPU Counters** — Is the CPU bottlenecked by instruction fetch/decode stalls?

## Performance Budgets and Rules

### Operation Timing

- Vision analysis: 50-200ms per image (faster on Apple Silicon with Neural Engine)
- CGContext drawing at 1920x1080: < 100ms per element
- JPEG export at 0.92 quality: ~500KB-2MB
- Process images concurrently with `withThrowingTaskGroup`

### Main Thread Timing Budgets

| Interaction type | Budget | Exceeding causes |
|---|---|---|
| Discrete (tap, key press) | < 50ms main thread work | Hang (>100ms noticeable) |
| Continuous (scroll, drag, animation) at 60Hz | < 5ms per frame | Hitch (frame drop) |
| Continuous at 120Hz | < 5ms per frame | Hitch (frame drop) |

**Rule:** Main thread = UI work only. All computation, I/O, and networking goes to background.

### Rendering Performance Rules

- **CGImage caching** -- Extract `CGImage` from `NSImage` once at load time. Repeated `nsImage.cgImage(forProposedRect:)` calls are expensive
- **Background preview rendering** -- Move heavy CoreGraphics work to `Task.detached` with captured values, dispatch results back with `Task { @MainActor in self?.previewImage = result }`. Cancel stale tasks before starting new ones.
- **No computed NSImage in body** -- Never create `NSImage(cgImage:size:)` in a computed property accessed from `body`. SwiftUI calls `body` frequently during layout, allocating a new `NSImage` per render cycle. Pass as a stored `let` parameter from the parent view.
- **Never clear rendered state before async replacement** -- If a view depends on `someDict.isEmpty` to choose between rendering modes, clearing that dict before the async replacement arrives creates a blank frame. Keep stale content visible during the gap, then repopulate.
- **Conditional rendering needs symmetric cleanup** -- When a rendering method only updates state inside a conditional (`if let overlay = config.overlay { ... }`), removing the input leaves previously rendered state visible. Add an `else` branch that explicitly clears it. This applies to overlays, backgrounds, titles, per-panel renders, and any conditionally produced output:

```swift
if let overlay = config.overlay {
    previewManager.updateOverlay(overlay: overlay, canvasSize: ...)
} else {
    previewManager.overlayImage = nil
    previewManager.overlayBlendMode = nil
}
```

- **Multiple async rendering tasks race** -- When `updatePreview()`, `updateBackground()`, and `updatePanelPreview()` all run on separate `Task.detached` tasks, there's no ordering guarantee. If rendering mode depends on which task completed first, the mode can flip unpredictably during rapid interactions.
- **Composite-to-layered rendering transition** -- When splitting a full composite into individual layers, every element baked into the composite needs its own rendering path. Elements without a dedicated layer become invisible in layered mode. Render each element (title, panels, effects) separately and compose in a ZStack.
- **Property-level debounce for rapid controls** -- Slider and color picker `didSet` observers fire 30-60x/sec during drag. Use a debounced render method (cancel previous task, sleep 150ms, render) for continuous controls. Discrete controls (typing, enum picker, image selection) render immediately. Rule of thumb: >10 events/sec = debounce. See [../state/swift-concurrency.md](../state/swift-concurrency.md) for cross-boundary cancellation pattern.
- **Throttled `@Observable` invalidation** -- When a version counter triggers full view re-evaluation, throttle its increments during high-rate input (pan/zoom gestures). Throttle fires immediately on first event, then skips until interval elapses — preserving live feedback unlike debounce. Use `ContinuousClock` + `Duration`, never `mach_absolute_time()` (returns ticks, not nanoseconds):

```swift
private var lastNotifyTime: ContinuousClock.Instant = .now
private let notifyInterval: Duration = .milliseconds(30) // ~33fps

private func throttledNotify() {
    let now = ContinuousClock.now
    if now - lastNotifyTime >= notifyInterval {
        lastNotifyTime = now
        versionCounter += 1
    }
}
```

- **Gesture-end notification gap** -- When per-frame notification is deferred to a debounce callback, gesture-end paths (e.g., `onEnded`, `finish*`) that cancel the debounce task will never fire the notification. Add explicit notification calls in gesture-end methods to ensure final state is visible.
- **Dual-responsibility timer/task cleanup** -- When removing a timer or background task for performance, audit what else it did beyond its primary purpose. A timer that both commits accumulated state AND calls `endGesture()` (clearing `gestureActivePanelId`, etc.) will leave stale gesture state if only the commit is replaced. Move cleanup to the explicit gesture-end path.
- **Gesture-end task cancellation** -- When a gesture uses a background render task (e.g., `previewDebounceTask`), cancel it in `endGesture()`. A pending render can fire after gesture end and overwrite a subsequent gesture's result. Different gesture types use different task variables and won't cancel each other automatically.

### Timing API

Use `ContinuousClock.now` + `Duration` for time-based logic. `ContinuousClock.Instant` survives sleep/wake and `Duration.milliseconds(30)` is self-documenting. `mach_absolute_time()` returns clock **ticks** (not nanoseconds) — the tick-to-nanos ratio varies on Apple Silicon. Comparing against hardcoded nanosecond thresholds produces incorrect throttling.
