# Performance Debugging and Optimization — Apple Docs Research

**Date:** 2026-05-27
**Sources:** Apple Developer Documentation (Xcode, Instruments, SwiftUI, Responsiveness)
**Context:** CollageMaker performance degradation (sessions 045, 054): memory growing 250MB to 500-780MB, progressive slowdown during editing

---

## Pinpointing Bottlenecks: Instruments Templates

Apple recommends a scientific, iterative approach: gather data, measure, plan one change, implement, observe, repeat. Use the following Instruments templates to diagnose specific symptoms:

| Symptom | Instruments Template | What It Shows |
|---|---|---|
| Unresponsiveness / hangs | **Time Profiler** | Call tree and flame graph of main thread work. Identify long-running functions. |
| Memory growth / leaks | **Allocations** and **Leaks** | Allocation call stacks, live vs. deallocated objects, leaked blocks. |
| CPU bottlenecks | **CPU Counters** (mode: CPU Bottlenecks) | Four bottleneck categories: instruction fetch stalls, instruction decode stalls, non-progress instructions, and no-bottleneck (useful work). |
| SwiftUI view updates | **SwiftUI** template | View body calculation times (>500μs orange, >1000μs red), update groups, cause-and-effect graphs. |
| Animation hitches | **Animation Hitches** | Commit hitches (main thread misses deadline) vs. render hitches (render server misses deadline). |
| Energy / power | **Energy Log** | Power impact of app activities. |
| File I/O | **File Activity** | Disk reads/writes, synchronous I/O on main thread. |

### Profiling Workflow

1. **In Xcode,** Control-click the test indicator next to a relevant test → choose "Profile <test name>"
2. **Or:** Product > Profile to launch Instruments manually
3. Select the appropriate template, click Record
4. Interact with the app to reproduce the issue
5. Click Stop, then analyze the timeline

For higher-fidelity measurements, profile on a real device rather than the Simulator.

### SwiftUI-Specific Profiling

The SwiftUI Instruments template provides:
- **View Body Updates lane:** Orange lines for >500μs calculations, red for >1000μs
- **Update Groups timeline:** Identifies groups of short updates that accumulate into long activity
- **Cause-and-effect graph:** Shows which observable properties trigger which view updates. Blue nodes = your code, gray nodes = system. Click edges to see which property changes caused each update.

To filter the Time Profiler call tree to a specific view update:
1. Control-click on `MySwiftUIView.body` in the detail view
2. Choose "Show Calls Made by MySwiftUIView.body"
3. To reset: click Callers/Callees → Clear Selection

---

## Runtime Sanitizers (Build-Time Diagnostics)

Enable these in the scheme editor (Product > Scheme > Edit Scheme > Run/Test > Diagnostics):

| Tool | Detects | Overhead | Relevant to CollageMaker |
|---|---|---|---|
| **Address Sanitizer (ASan)** | Use-after-free, buffer overflows, double-free | 2-3x memory, 2-5x slowdown | Memory corruption from undo stack capturing `self` |
| **Thread Sanitizer (TSan)** | Data races, Swift access races, thread leaks | 5-10x memory, 2-20x slowdown | Concurrency issues in `addImages(from:)`, saliency analysis |
| **Main Thread Checker** | AppKit/SwiftUI calls off main thread | 1-2% CPU, ~100ms launch | `NSImage(data:)` off-main (Change A, session 054) |
| **Thread Performance Checker** | Priority inversions, non-UI work on main thread | Minimal | Detects synchronous I/O or networking on main thread |
| **Undefined Behavior Sanitizer** | Divide-by-zero, misaligned pointers, integer overflow | ~20% CPU (debug) | Integer overflow in layout math |

**Note:** TSan is macOS-only (not available on iOS devices). ASan does NOT detect memory leaks — use Instruments Allocations/Leaks for that.

---

## Memory: Understanding Growth and Leaks

### Memory Metrics

- **Peak memory use:** Highest memory observed in periodic samples (MetricKit / Xcode Organizer)
- **Memory at suspension:** Memory when app enters background
- macOS measures memory as dirty pages × page size (typically 16 KB). Writing a single byte to allocated memory can increase usage by 16 KB if a new page is needed.

### CollageMaker-Specific Memory Issues (from sessions 045/054)

**Root cause 1: Unbounded undo stack**
- `UndoManager` with no `levelsOfUndo` limit
- Every `didSet` mutation registered an undo operation capturing `self` (entire view model with all loaded images)
- Accumulated indefinitely with no trimming
- **Fix applied:** `self.undoManager.levelsOfUndo = 60` in initializer

**Root cause 2: Excessive undo during gestures**
- `titleStyle.didSet` registered undo on every mouse move during title drag
- 50-200+ undo entries per single drag gesture
- **Fix applied:** Guarded with `if !isDraggingTitle { ... }`

**Root cause 3: Synchronous persistence saves**
- 13 `persistence.save(self)` calls fired on every slider drag, color change, etc.
- **Fix applied:** Debounced to 300ms with `Task.sleep` + cancel-previous pattern

### Preventing Memory Regressions

1. **Write performance tests** using `XCTCPUMetric` and `XCTClockMetric` to establish baselines
2. **Use the Allocations instrument** to track allocation call stacks during editing sessions
3. **Monitor memory in Xcode Organizer** — compare peak memory across releases by device model and percentile
4. **Test with Address Sanitizer** enabled during development to catch use-after-free

---

## CPU Bottlenecks

### What CPU Bottlenecks Are

Modern processors optimize instruction flow through pipelining, out-of-order execution, branch prediction, and cache hierarchies. Bottlenecks occur when the CPU cannot run at maximum efficiency:

1. **Instruction fetch stalls:** CPU fetches instructions slower than it completes them (many branch mispredictions, large jumps)
2. **Instruction decode stalls:** CPU completes instructions slower than it fetches them (memory-dependent instructions, cache misses)
3. **Non-progress instructions:** CPU does work that gets discarded (incorrect branch predictions)
4. **No bottleneck:** CPU completes useful instructions efficiently

### Detecting CPU Bottlenecks

Use the **CPU Counters instrument** in CPU Bottlenecks mode:
1. Product > Profile → CPU Counters template
2. Set mode to "CPU Bottlenecks"
3. Record and interact with the app
4. Click the CPU Counters track to see Summary: Metrics (fraction of time in each category)
5. Expand thread timeline to see bottleneck lanes per thread
6. Control-click a bottleneck → "Suggested Next" to gather more detail

### Design Principles to Avoid Bottlenecks

- **Use system frameworks** — Apple's implementations are optimized for the device's CPU
- **Prefer dynamic task allocation** over static thread pools — let the system schedule based on core availability
- **Indicate quality-of-service** for background tasks — use `DispatchQoS` or `Task.detached(priority:)`
- **Remove algorithmic inefficiencies first** before investigating CPU bottlenecks

### CollageMaker CPU Considerations

- **CoreGraphics compositing** at 1920x1080 is <100ms per skill notes — this is likely efficient
- **Vision saliency analysis** should be on a background thread (actor isolation handles this)
- **Layout math** (`LayoutGenerator`) should be lightweight; profile if it becomes a bottleneck
- **Avoid synchronous work on main thread** — the Thread Performance Checker will flag this

---

## SwiftUI Performance

### Key Principles

1. **Keep view bodies fast** — limited dependencies, no expensive calculations
2. **Move business logic to model types** — SwiftUI recreates views and recalculates bodies frequently
3. **Avoid storing closures in views** — closures capture parent state, causing excessive updates
4. **Consider complex layout impact** — `GeometryReader` and `ScrollViewReader` observe parent layout changes

### Long-Running View Body Computations

**Anti-pattern:** Expensive calculations in `var body`
**Fix:** Perform calculation asynchronously, cache the result

**Detection:** SwiftUI Instruments template → View Body Updates lane (orange >500μs, red >1000μs)

### Too-Frequent View Updates

Not all problems are long updates. A sequence of short updates can accumulate into significant work.

**Causes:**
- View observes properties on an object with other observable properties; updates when unrelated properties change
- Parent view update causes child views to update without meaningful UI changes
- Custom layout with `GeometryReader` recalculating scroll geometry for non-scroll updates

**Fixes:**
- Migrate to `@Observable` macro — tracks which properties a view reads, only emits changes for those properties
- Identify a different view in the hierarchy to receive the update, making only relevant changes
- Use the cause-and-effect graph in Instruments to trace which property changes trigger which updates

### CollageMaker SwiftUI Considerations

- **`@Observable` on `CollageViewModel`** — already using the right pattern
- **`GeometryReader` in `CollageEditorView`** — the session 054 fix replaced `@State` caching with on-the-fly computed `let` bindings, which is the correct approach
- **Avoid closures in panel views** — ensure gesture handlers don't capture unnecessary state
- **`@Bindable` for two-way bindings** — use sparingly to limit update scope

---

## Main Thread Responsiveness

### Hangs vs. Hitches

| | Hang | Hitch |
|---|---|---|
| **Interaction type** | Discrete (tap, key press) | Continuous (scroll, drag, animation) |
| **Threshold** | >100ms noticeable, >250ms reported | >5ms can cause frame drop |
| **Root cause** | Main thread blocked | Main thread misses commit deadline, or render server misses render deadline |
| **Detection** | Hangs instrument, Thread Performance Checker | Animation Hitches template |

### Timing Budgets

- **Discrete interaction:** <100ms total, assume <50ms available for main thread work
- **Continuous interaction at 60Hz:** <16.7ms per frame, aim for <5ms main thread work
- **Continuous interaction at 120Hz:** <8.3ms per frame, aim for <5ms main thread work

### Keeping the Main Thread Free

**Rule:** Use main thread ONLY for UI work (AppKit, SwiftUI). All other work goes to background.

**Swift concurrency pitfalls:**
- `Task { longRunningSyncWork() }` — still runs on MainActor (inherits context)
- `Task { await longRunningAsyncWork() }` — correct (nonisolated async runs off-main)
- `Task.detached { longRunningSyncWork() }` — correct (opts out of actor inheritance)

**CollageMaker considerations:**
- **Gesture handling** (scroll, pan, drag) — must be fast, <5ms per event
- **`updatePreview()`** — already uses `previewTask?.cancel()` pattern for stale task cancellation
- **`regenerateLayout()`** — should be fast; if layout math is expensive, consider background computation
- **Persistence saves** — now debounced, but ensure the save operation itself is non-blocking
- **Image loading** — session 054 Change A moved `NSImage(data:)` to `MainActor.run { }`, which is correct

### Render Loop Deadlines

For each frame, the render loop has three deadlines:
1. **Begin time:** Earliest the app can commit a UI update
2. **Commit deadline:** When the app must finish UI changes and commit to Core Animation
3. **Presentation time:** When the frame must be ready for display (vsync)

Missing the commit deadline causes a **commit hitch**. Missing the render deadline causes a **render hitch**.

---

## Actionable Recommendations for CollageMaker

### Immediate (Low Effort, High Impact)

1. **Enable Thread Performance Checker** in the debug scheme — will flag any remaining main-thread-blocking calls
2. **Enable Address Sanitizer** during development — will catch use-after-free from undo stack or image handling
3. **Profile with Allocations instrument** during a 10-minute editing session — verify the undo cap at 60 is sufficient, check for image retention
4. **Add `OSSignpost` markers** around `updatePreview()`, `regenerateLayout()`, and `applyPanLive()` — enables signpost-based measurement in Instruments and MetricKit

### Short-Term (Medium Effort)

5. **Write a performance test** for the scroll/pan gesture path — use `XCTClockMetric` to measure time from gesture start to preview update, establish a baseline
6. **Profile with SwiftUI Instruments template** — identify any view body calculations exceeding 500μs, check for excessive update groups during scrolling
7. **Review `@Observable` property granularity** — ensure views only observe the properties they need; consider splitting `CollageViewModel` into smaller observable objects if a single property change triggers unnecessary view updates
8. **Audit closure captures** in `CollageEditorView` — ensure gesture handler closures don't capture `self` or large view state

### Medium-Term (Higher Effort)

9. **Implement MetricKit reporting** for shipping builds — track peak memory, hitch ratio, and launch time in the field
10. **Profile with CPU Counters** if scroll/pan feels sluggish — identify if CoreGraphics compositing or layout math is causing instruction stalls
11. **Consider lazy image loading** — if the collage has many high-resolution images, load full-resolution images on-demand rather than at startup
12. **Evaluate `Task.detached` for saliency analysis** — ensure Vision framework work runs at appropriate priority without blocking the main actor

### Testing Configuration

For the test plan (Product > Test Plan > Edit Test Plan > Configurations):
- Set Runtime API Checking → Main Thread Checker to "On (as Failure)"
- Set Address Sanitizer to "On (as Warnings)" during development
- Add a performance test target with `XCTCPUMetric` and `XCTClockMetric` baselines

---

## References

- Apple: "Improving your app's performance" — developer.apple.com/documentation/xcode/improving-your-app-s-performance
- Apple: "Addressing CPU bottlenecks" — developer.apple.com/documentation/xcode/addressing-cpu-bottlenecks
- Apple: "Reducing your app's memory use" — developer.apple.com/documentation/xcode/reducing-your-app-s-memory-use
- Apple: "Understanding and improving SwiftUI performance" — developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance
- Apple: "Improving app responsiveness" — developer.apple.com/documentation/xcode/improving-app-responsiveness
- Apple: "Understanding hitches in your app" — developer.apple.com/documentation/xcode/understanding-hitches-in-your-app
- Apple: "Understanding hangs in your app" — developer.apple.com/documentation/xcode/understanding-hangs-in-your-app
- Apple: "Diagnosing performance issues early" — developer.apple.com/documentation/xcode/diagnosing-performance-issues-early
- Apple: "Diagnosing memory, thread, and crash issues early" — developer.apple.com/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early
