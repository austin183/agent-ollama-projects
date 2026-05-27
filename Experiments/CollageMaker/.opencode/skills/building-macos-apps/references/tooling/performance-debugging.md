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
