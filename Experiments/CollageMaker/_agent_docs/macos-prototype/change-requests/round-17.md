# Round 17 — Performance Instrumentation and Guardrails

**Context:** Rounds 15/16 fixed the known memory regressions (undo cap, gesture guard, debounced saves, concurrency modernization). The next step is adding instrumentation and automated guardrails so we can detect future regressions early and profile precisely when issues surface.

**Source:** Apple docs research (`_agent_docs/research/performance/apple-performance-debugging-and-optimization.md`)

---

## Change A: Add OSSignpost Markers

**Problem:** Expensive operations (`updatePreview()`, `regenerateLayout()`, `applyPanLive()`, `analyzeSaliency()`) are invisible in Instruments. Without signposts, the Time Profiler shows raw call stacks with no semantic grouping, making it hard to isolate bottlenecks.

**Fix:** Add `OSSignposter` intervals around each operation.

```swift
import os.signpost

// Shared signposter (add to a dedicated file or CollageViewModel)
private let perfLogger = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "performance")
private let signposter = OSSignposter(logger: perfLogger)
```

Wrap each method:
- `updatePreview()` → "Preview Assembly"
- `regenerateLayout()` → "Layout Regeneration"
- `applyPanLive()` → "Pan Application"
- `analyzeSaliency()` → "Saliency Analysis"

**Files changed:** `CollageViewModel.swift`, `CropManager.swift` (if `applyPanLive` lives there)

**Verification:** Build → Product > Profile → Time Profiler → verify signpost intervals appear in the OS Logging track.

---

## Change B: Performance Test for Scroll/Preview Path

**Problem:** No automated performance baseline. A future change could regress scroll responsiveness and we'd only discover it through user reports.

**Fix:** Add a performance test that exercises the scroll/pan gesture path with a mock assembler, measured with `XCTClockMetric` and `XCTCPUMetric`.

```swift
@MainActor
final class CollagePerformanceTests: XCTestCase {
    @Test func scrollPreviewUpdate() async throws {
        let vm = CollageViewModel(assembler: TrackingAssembler())
        vm.addImages([createTestImageItem()])

        measure(metrics: [
            XCTClockMetric(),
            XCTCPUMetric()
        ]) {
            for _ in 0..<20 {
                vm.scrollPanDelta(by: CGSize(width: 5, height: 3))
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
```

**Files changed:** New file `CollageMakerTests/CollagePerformanceTests.swift`

**Verification:** Run test, accept baseline. Subsequent runs should stay within margin.

---

## Change C: Verify Scheme Diagnostics Configuration

**Problem:** Thread Performance Checker and Address Sanitizer may not be enabled in the debug scheme. These are zero-effort tools that catch main-thread-blocking and memory corruption during development.

**Fix:** Open Product > Scheme > Edit Scheme > Run > Diagnostics and verify:
- [x] Thread Performance Checker (should be on by default)
- [x] Address Sanitizer
- [x] Main Thread Checker (should be on by default)

**No code changes.** This is a scheme configuration audit. Document the settings in AGENTS.md if they need to be set manually.

---

## Change D: SwiftUI Instruments Audit (One-Time Research)

**Problem:** Unknown whether any view body calculations exceed 500μs or whether update groups are excessive during scrolling.

**Fix:** One-time profiling pass:
1. Product > Profile → SwiftUI template
2. Add 5+ images, scroll and pan the canvas for 30 seconds
3. Stop recording
4. Check View Body Updates lane for orange (>500μs) or red (>1000μs) lines
5. Check Update Groups for long active groups not associated with long updates
6. Use cause-and-effect graph on any problematic update to identify the triggering property

**No code changes.** Document findings in a learnings file. If issues are found, file a follow-up change request.

---

## Priority and Order

1. **Change A** (signposts) — enables all subsequent profiling, do first
2. **Change C** (scheme audit) — zero code change, do alongside A
3. **Change B** (performance test) — requires TrackingAssembler to work, depends on existing test infrastructure
4. **Change D** (SwiftUI audit) — can be done anytime, informs future work

## Expected Impact

- **No user-facing performance change** — this round adds observability, not optimizations
- **Faster future debugging** — signposts make Instruments traces interpretable in seconds instead of minutes
- **Regression protection** — performance test catches scroll path regressions in CI
