# Performance Instrumentation and Profiling — Learnings 2026-05-27

**Purpose**: Capture learnings from Round 17 — attempting to add OSSignpost markers, performance tests, and Instruments profiling.

## What Worked

- **`Logger` + `ContinuousClock` for timing** — When `os_signpost` is unavailable, `Logger.debug` with `ContinuousClock.now` start + `defer` provides structured, filterable timing data in `log stream`. Pattern:

```swift
let start = ContinuousClock.now
defer { perfLogger.debug("Operation completed in \(ContinuousClock.now - start)") }
```

- **`perfLogger` with separate category** — Using a dedicated "performance" category (same subsystem as app) allows filtering `log stream --predicate 'category == "performance"'` to isolate timing events from regular app logs.

- **`TrackingAssembler` for scroll path test** — Reusing the existing `TrackingAssembler` mock from `ExportFlowTests.swift` to verify that scroll pan deltas trigger preview assembly. The `previewCalls` counter provides a simple regression signal.

- **`Task.sleep` for async task completion** — In performance tests where `#measure` is unavailable, `try? await Task.sleep(nanoseconds: 100_000_000)` after the work loop allows detached preview tasks to complete before assertions.

## What Didn't Work / Gaps

- **`OSSignposter.interval` not available** — In Xcode 26.5 / Swift 6.3.2 / macOS SDK 26.5, `OSSignposter` has no `interval`, `makeIntervalLogHandle`, or `logIntervalEnd` methods. These appear to be newer APIs not yet shipped in this SDK.

- **`os_signpost` C API segfaults** — The C API `os_signpost(.begin, dso:log:name:)` compiles successfully but crashes with segfault in both standalone `swiftc` binaries and the Xcode test harness. The crash occurs at the `os_signpost(.begin, ...)` call, not at `dlopen`. Using `dlopen(nil, 4)` for the DSO pointer. This makes the C API unusable for this project in the current toolchain.

- **SwiftUI Instruments template empty** — In Xcode 26.5, the SwiftUI Instruments template launched but showed no view body update data, no update groups, and no cause-and-effect graph. This may be an Xcode 26.5 issue or may require specific debug build flags. Time Profiler (`Product > Profile > Time Profiler`) worked normally and surfaced `drawPanels` as the CPU hot spot.

- **`#measure` macro unavailable** — Swift Testing's `#measure` macro (and `XCTClockMetric`, `XCTCPUMetric`) are not available in this Xcode version's Swift Testing framework. This is consistent with the earlier `tolerance:` limitation — this SDK ships an older Swift Testing version.

## What Was Confusing

- **`os_signpost` hangs standalone, crashes in tests** — A standalone `swiftc` binary calling `os_signpost(.begin, ...)` hangs at the call site (never reaches the next print). In the Xcode test harness, it crashes with `EXC_BAD_ACCESS` (segfault). The different failure modes suggest the DSO pointer or unified log subsystem behaves differently between standalone and test-bundle execution contexts.

- **`OSSignposter` type exists but has no methods** — `OSSignposter(logger:)` constructs successfully and `type(of:)` returns `OSSignposter`, but the type has no usable methods in this SDK. This suggests the type is a forward-declaration stub awaiting API implementation.

## What Stood Out During Profiling

- **`CollageAssembler.drawPanels` is the CPU hot spot** — During heavy scrolling with many images, Time Profiler showed `drawPanels` dominating CPU time. The method iterates panels, crops images, and draws to CGContext. Each scroll delta during panning triggers a full `updatePreview()` which re-composites all panels. The debounced preview in `applyPanLive()` (150ms) helps, but the scroll path calls `updatePreview()` synchronously inside the `applyLive` closure, meaning every scroll event triggers a full canvas re-composite.

## Skill Improvements

### Update `building-macos-apps` Skill — Performance Section

1. **Fallback timing pattern** — When `OSSignposter` APIs are unavailable, use `Logger` + `ContinuousClock`:

```swift
private let perfLogger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "performance")

func expensiveOperation() {
    let start = ContinuousClock.now
    defer { perfLogger.debug("Operation completed in \(ContinuousClock.now - start)") }
    // ... work ...
}
```

2. **`os_signpost` C API incompatibility** — In Xcode 26.5 / Swift 6.3.2, the `os_signpost` C API segfaults in test environments and hangs in standalone binaries. Avoid for now; use `Logger` + `ContinuousClock` as the portable alternative.

3. **SwiftUI Instruments may be empty** — The SwiftUI Instruments template may show no data in certain Xcode versions. Fall back to Time Profiler for CPU analysis and `log stream` for timing data.

### Update `macos-telemetry-instrumentation` Skill

4. **Signpost availability check** — Before committing to `OSSignposter` instrumentation, verify the API exists in the target SDK. The type may be a stub with no methods.

## Next Steps

- Monitor `os_signpost` availability in future Xcode releases
- Consider whether `drawPanels` needs optimization (e.g., incremental panel drawing, reduced-resolution scroll preview)
- Evaluate whether a reduced-resolution preview during scroll could reduce CPU pressure

---
**Status**: Completed
**Follow-up**: Monitor `os_signpost` API availability, evaluate `drawPanels` optimization opportunities
