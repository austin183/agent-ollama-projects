# Testing Patterns

## Contents
- CGImage Test Fixtures — Use NSBitmapImageRep
- AppKit Initialization in Tests
- CGContext in Headless Test Environments
- CGPathApply Compiler Crash in Test Targets
- Transform Extraction for Testability
- Shadow Implementation Anti-Pattern
- Testing @Published State Changes
- Testing Gesture Operations
- Testing Timer/Debounce Chains
- Testing @MainActor ObservableObject
- Testing actor Services
- Protocol-Based Mocking
- Static Method Pattern for Testability
- TrackingAssembler Mock Pattern
- CoordinateConverter Pure Struct Pattern
- Eliminate Computed NSImage in SwiftUI Views
- Swift Testing Framework
- Running Tests via xcodebuild
- Testing `Task.detached` in ViewModel Tests
- Mock Method Symmetry
- Testing Extracted Pure-Math Utilities
- Aspect Ratio Math in Coordinate Tests
- Swift Testing Parallelism and `@Suite(.serialized)`
- 0.000s Cascade Failure Diagnostic
- Closed Range `(a+1)...b` Fatal Error
- Performance Tests with XCTClockMetric and XCTCPUMetric
- OSSignpost Markers for Profiling
- UserDefaults Test Suite Stability
- UserDefaults Test Isolation with UUID Suite Names
- App Sandbox Blocks Test File Access
- Pixel Sampling for Background Verification in Tests
- ImageItem.cgImage Is a Stored Property, Not a Method
- Canvas Coverage Thresholds by Layout Style
- Pitfalls
- Identity-Based Cache Testing
- Behavioral Cache Testing (Preferred)
- Testing Synchronous DispatchQueue Closures
- XCUIAutomation macOS API Gotchas
- UITest Bundle Resource Discovery
- UndoManager Coalescing in Tests

## CGImage Test Fixtures — Use NSBitmapImageRep

`CGContext.makeImage()` returns `nil` in the test environment with `[.byteOrder32Big]` (no alpha) bitmap info, even for small images. Use `NSBitmapImageRep` with RGBA instead:

```swift
private func createTestCGImage(color: CGColor, size: CGSize = CGSize(width: 100, height: 100)) -> CGImage {
    let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    )!
    bitmapRep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setFillColor(color)
    ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
    NSGraphicsContext.restoreGraphicsState()
    return bitmapRep.cgImage!
}
```

**Key points:**
- `samplesPerPixel: 4` with `hasAlpha: true` — RGBA works reliably in test environment
- `colorSpaceName: .deviceRGB` — `.sRGB` doesn't exist on `NSColorSpaceName`
- Always `saveGraphicsState()` / `restoreGraphicsState()` to avoid polluting the current context
- Use 100x100 for fast, low-memory test fixtures
- Add `assembleWithCGImages` methods to your assembler for testability (bypass NSImage→CGImage)

## AppKit Initialization in Tests

If tests use AppKit types (`NSImage`, `NSBitmapImageRep`, etc.), initialize the shared application before tests run:

```swift
@Suite struct AppKitInit {
    init() {
        _ = NSApplication.shared  // Runs before any @Test in the file
    }
}
```

Or use `@Test(.dependencies(AppKitInit.self))` on individual tests.

## CGContext in Headless Test Environments

`CGContext.makeImage()` may return `nil` with `[.byteOrder32Big]` in headless/CI environments.

**Root cause:** `.byteOrder32Big` specifies pixel byte ordering but **no alpha channel definition**. In headless environments, the graphics subsystem rejects undefined formats.

**Fix:** Combine byte order with alpha info:
```swift
let bitmapInfo: CGBitmapInfo = [.byteOrder32Big, .noneSkipLast]
```

Or use `NSBitmapImageRep` with RGBA as fallback (see above).

## CGPathApply Compiler Crash in Test Targets

`CGPath.apply(info:)` with a closure that accesses `element.pointee.type` can crash the swift-frontend compiler in a test target. The crash is at compile time, not runtime.

**Workaround:** Test `CGAffineTransform` logic by applying the transform to known `CGPoint` coordinates instead of iterating path elements:

```swift
let transform = PanelGeometry.transformForPanel(boundingRect: boundingRect, targetRect: targetRect)
let mappedPoint = CGPoint(x: 50, y: 0).applying(transform)
#expect(mappedPoint.y == 100)
```

Avoid `CGPathApply` in test targets entirely.

## Transform Extraction for Testability

When a SwiftUI `Shape` contains `CGAffineTransform` logic, the transform math is inseparable from the SwiftUI `Path` type — and the test target cannot import SwiftUI. Extract the transform computation to a static method on a model type that only depends on `CoreGraphics`:

```swift
// In a model file (no SwiftUI dependency):
enum PanelGeometry {
    static func transformForPanel(boundingRect: CGRect, targetRect: CGRect) -> CGAffineTransform {
        // Pure CG math — testable without SwiftUI
    }
}

// In a SwiftUI view:
struct PanelShape: Shape {
    func path(in rect: CGRect) -> Path {
        let transform = PanelGeometry.transformForPanel(...)
        return Path(cgPath.copy(using: &transform)!)
    }
}
```

This is a specific instance of the broader static method pattern: extract pure-function logic from UI types to make it testable.

## Shadow Implementation Anti-Pattern

When testing a `private` type or method, duplicating the logic locally in the test file provides zero regression protection — if the actual code changes, the shadow continues to pass against its own (stale) logic.

**Fix:** Extract the testable unit to `internal` visibility or a static method on a model type. If the test file contains more than a few lines of logic that mirrors the code under test, the test is checking itself, not the implementation.

## Testing @Published State Changes

```swift
@Test func cropUpdateTriggersPreview() async throws {
    let vm = CollageViewModel()
    vm.addImages([createTestImageItem()])

    var previewChanged = false
    let cancellable = vm.objectWillChange.sink { _ in
        previewChanged = true
    }

    vm.updateCrop(for: vm.panels[0].id, sourceRect: CGRect(x: 10, y: 10, width: 80, height: 80), zoom: 1.0)
    try await Task.sleep(for: .milliseconds(100))

    #expect(previewChanged == true)
    _ = cancellable
}
```

## Testing Gesture Operations

Test the ViewModel's gesture methods directly (UI-level gesture tests are not practical):

```swift
@Test func panCropMovesSourceRect() async throws {
    let vm = CollageViewModel()
    vm.addImages([createTestImageItem()])

    let panelId = vm.panels[0].id
    vm.panCrop(panelId: panelId, by: CGSize(width: 10, height: 20))
    vm.applyPanCrop(panelId: panelId)

    // Verify crop was applied
    #expect(vm.cropMap[panelId]?.sourceRect.origin.x == 10)
}

@Test func panCropClampsToBounds() async throws {
    let vm = CollageViewModel()
    vm.addImages([createTestImageItem(size: CGSize(width: 100, height: 100))])

    let panelId = vm.panels[0].id
    vm.panCrop(panelId: panelId, by: CGSize(width: -5000, height: -5000))
    vm.applyPanCrop(panelId: panelId)

    // Should be clamped to 0
    #expect(vm.cropMap[panelId]?.sourceRect.origin.x >= 0)
}
```

## Testing Timer/Debounce Chains

`Timer.scheduledTimer` with `Task { @MainActor in ... }` requires `Task.sleep` in tests (not `RunLoop.run`):

```swift
@Test func debounceTimerFires() async throws {
    let vm = CollageViewModel()
    vm.cropOffsetX = 5  // Schedules debounce timer
    try await Task.sleep(for: .milliseconds(500))  // Wait for timer

    // Verify the debounced action executed
    #expect(vm.previewImage != nil)
}
```

## Testing @MainActor ObservableObject

When your `@testable` module has `@MainActor`-isolated types, annotate the test struct with `@MainActor` to avoid Swift 6 concurrency warnings:

```swift
@MainActor
struct ViewModelTests {
    @Test func addItemTriggersComputation() async throws {
        let vm = AppViewModel()
        vm.addItem(createTestItem())
        #expect(vm.items.count == 1)
        #expect(vm.results.count == 1)
    }
}
```

## Testing actor Services

```swift
@Test func analyzeThrowsForInvalidImage() async throws {
    let analyzer = SaliencyAnalyzer()
    let empty = NSImage(size: CGSize(width: 1, height: 1))
    #throw(try await analyzer.analyze(empty))
}
```

## Protocol-Based Mocking

Extract protocol for dependency injection:

```swift
protocol SaliencyAnalysis {
    func analyze(_ image: NSImage) async throws -> SaliencyResult
}
actor SaliencyAnalyzer: SaliencyAnalysis { ... }

// In ViewModel:
init(saliencyAnalyzer: SaliencyAnalysis = SaliencyAnalyzer()) {
    self.analyzer = saliencyAnalyzer
}
```

## Static Method Pattern for Testability

When a `@MainActor` class contains pure computation (no state access), add `static func` variants that take all inputs as parameters. This allows testing without actor isolation. Keep thin instance method wrappers for view call sites.

```swift
@MainActor final class CropManager {
    // Instance wrapper — for view call sites
    func canvasToPreviewFrame(_ canvasFrame: CGRect) -> CGRect {
        Self.canvasToPreviewFrame(canvasFrame, canvasSize: canvasSize, previewSize: previewSize)
    }

    // Static — testable outside @MainActor
    static func canvasToPreviewFrame(_ canvasFrame: CGRect, canvasSize: CGSize, previewSize: CGSize) -> CGRect {
        // pure computation
    }
}
```

**Warning:** When both static and instance methods share a name, the instance method must call `Self.method()` explicitly. The compiler does not warn — it will silently recurse if the instance method calls itself.

## TrackingAssembler Mock Pattern

For ViewModel integration tests, create a protocol mock that records parameters instead of returning fixed values. Each method captures inputs into stored properties for assertion:

```swift
final class TrackingAssembler: CollageAssembly {
    var lastCanvasSize: CGSize = .zero
    var lastPanelCount: Int = 0
    var assembleCalled = false

    func assembleWithCGImages(_ images: [CGImage], canvasSize: CGSize) -> Data? {
        assembleCalled = true
        lastCanvasSize = canvasSize
        lastPanelCount = images.count
        return Data()  // Must use explicit `return`
    }
}
```

**Key points:**
- Protocol methods with non-void return types require explicit `return` — expression statements like `Data()` are not implicit returns
- Records enough state to assert ViewModel behavior without running the actual CoreGraphics pipeline

## CoordinateConverter Pure Struct Pattern

When coordinate conversion logic is duplicated between views and ViewModels, extract to a pure `struct` with static methods. No state, no actor isolation, fully testable:

```swift
struct CoordinateConverter {
    static func canvasToPreview(_ frame: CGRect, canvasSize: CGSize, previewSize: CGSize) -> CGRect {
        // aspectRatio(.fit) math
    }
}
```

## Eliminate Computed NSImage in SwiftUI Views

Never create `NSImage` in a computed property accessed from `body`. SwiftUI calls `body` frequently during layout, so `NSImage(cgImage:size:)` allocates a new image per render cycle. Pass `nsImage` as a stored `let` parameter from the parent view.

## Swift Testing Framework

- `#expect(condition)` — assertion
- `#throw(expression)` — expect error
- `Issue.record("message")` — conditional failure
- `@Test("param: ", [values])` — parameterized tests
- Test resources: `Bundle.module.url(forResource:withExtension:)`
- **`.timeLimit()` requires minutes** — Swift Testing's `.timeLimit()` trait requires time values in **minutes**, not seconds. `.seconds(30)` is unavailable. Use `.minutes(1)` or fractional minutes like `.minutes(0.5)` for 30 seconds: `@Test(.timeLimit(.minutes(1)))`
- **`tolerance:` not available** — This Xcode version's Swift Testing doesn't support `tolerance:` on `#expect()`. Use range checks: `#expect(value > lower && value < upper)`, or exact equality for integer-valued `CGFloat`s
- **`import Foundation` required for `UUID`** — `CoreGraphics` and `Testing` don't transitively import `Foundation`. New test files need `import Foundation` explicitly
- **Weak switch assertions** — A `switch` in a test that ignores one case with `break` passes silently even if the decoder returns the wrong case. Record an issue in unexpected branches:

```swift
switch decoded.destination {
case .rect:
    Issue.record("Expected .path geometry after round-trip")
case .path(_, let rect):
    #expect(rect == boundingRect)
}
```

Every branch of a `switch` in a test should either assert something or explain why that branch is acceptable. An empty branch is a latent bug.

## Running Tests via xcodebuild

```bash
xcodebuild test -project App.xcodeproj -scheme App -destination 'platform=macOS,arch=arm64' -only-testing:AppTests
```

- Parse results: `grep -E "Test case.*passed|Test case.*failed"`
- `EXC_BREAKPOINT` in crash reports = Swift `fatalError`, not memory crash
- Use `guard let` over force-unwraps in tests to prevent cascading crashes

## Testing `Task.detached` in ViewModel Tests

When a ViewModel method fires work inside `Task.detached`, the method returns immediately and the test process reaches its synchronous assertions before the detached task completes. Mock tracking fields will still be at their initial values.

**Fix:** Add `try? await Task.sleep(nanoseconds: 50_000_000)` (50ms) before assertions. The mock returns immediately — the sleep only needs to yield control so the detached task can run.

```swift
@Test func regenerateLayoutTriggersPreview() async throws {
    let vm = CollageViewModel(assembler: trackingAssembler)
    vm.addImages([createTestImageItem()])
    vm.regenerateLayout()

    // Yield to let the Task.detached inside updatePreview() run
    try? await Task.sleep(nanoseconds: 50_000_000)

    #expect(trackingAssembler.lastPreviewPanels.count == 1)
}
```

**Anti-pattern:** Calling `regenerateLayout()` then immediately asserting on assembler state. `regenerateLayout()` calls `updatePreview()`, which fires off the detached task and returns.

**Better alternative (for future):** Have `updatePreview()` return a `Task<Void, Never>` and have tests `await` it, or add a `previewCompletion: CheckedContinuation?` pattern. The sleep approach works for mocks but would be unreliable with real CoreGraphics rendering.

### Race Condition Checklist

When a ViewModel method uses `Task.detached`, ask:

1. Does the test assert on state set inside the detached task? → Add `await Task.sleep`
2. Does the test assert on state set synchronously before the task? → No await needed
3. Does the mock track the method the ViewModel actually calls? → Verify method name match

## Mock Method Symmetry

When a protocol has multiple methods (e.g., `assembleWithCGImages` for export, `assemblePreviewWithCGImages` for preview), the tracking mock must record fields on **every method the ViewModel actually calls**.

If `updatePreview()` calls `assemblePreviewWithCGImages`, but the mock only populates `lastAssemblePanels` in `assembleWithCGImages`, tests asserting `lastAssemblePanels` are checking the wrong method's tracking data.

**Rule:** If a test calls ViewModel method X, and X delegates to protocol method Y, the mock must track on Y, not on sibling method Z.

```swift
final class TrackingAssembler: CollageAssembly {
    // Tracked by assembleWithCGImages (export path)
    var lastAssemblePanels: [LayoutPanel] = []

    // Tracked by assemblePreviewWithCGImages (preview path)
    var lastPreviewPanels: [LayoutPanel] = []

    func assembleWithCGImages(_ panels: [LayoutPanel], ...) -> Data? {
        lastAssemblePanels = panels
        return Data()
    }

    func assemblePreviewWithCGImages(_ panels: [LayoutPanel], ...) -> NSImage? {
        lastPreviewPanels = panels
        return NSImage(size: .zero)
    }
}
```

## Testing Extracted Pure-Math Utilities

When extracting shared math from duplicated code paths (e.g., fit calculations, coordinate transforms), write a dedicated test file for the utility **before** refactoring the call sites. Test with concrete known values to catch branch-direction bugs:

```swift
@Test func fitLandscapeIntoPortrait() {
    let result = FitMath.fit(CGSize(width: 1920, height: 1080), into: CGSize(width: 746, height: 821))
    #expect(result.fittedSize.width == 746)  // width constrains
    #expect(result.fittedSize.height == 418)  // derived from aspect
}
```

Call-site tests (e.g., CropManager, CoordinateConverter) exercise the utility indirectly but won't catch implementation bugs in the utility itself — they'll only surface as downstream failures (broken hit-testing, wrong overlays).

## Aspect Ratio Math in Coordinate Tests

When writing tests for coordinate conversion that implements `.aspectRatio(contentMode: .fit)` math, expected values depend entirely on the relative aspect ratios of image and container:

- **Image wider than container** (landscape image, square container): constrains by width, letterboxes top/bottom
- **Image taller than container** (portrait image, square container): constrains by height, letterboxes left/right
- **Image square, container widescreen** (200x200 in 800x600): constrains by height (600), fitted = 600x600, offset = (100, 0)

**Rule:** Always compute the fitted dimensions first, then the offset, then the mapped rect. Never assume which axis constrains.

### Scale Factor Verification

When image and container share the same aspect ratio (e.g., 200x200 image in 800x800 container = 4x scale), crop coordinates multiply directly by the scale factor. Crop `(50, 50, 20, 20)` → `(200, 200, 80, 80)`.

**Rule:** When image and container share the same aspect ratio, `scaleX = containerW / imageW` and `scaleY = containerH / imageH` should be equal. Use this as a sanity check in tests.

## Swift Testing Parallelism and `@Suite(.serialized)`

Swift Testing parallelizes test suites across multiple processes. When test fixtures modify shared global state (e.g., `NSGraphicsContext.current`), concurrent access causes cascade failures where tests fail at 0.000s without executing.

**Fix:** Analyze which suites use shared mutable state, and annotate them with `@Suite(.serialized)` to serialize tests within each process:

```swift
@Suite(.serialized) struct CollageViewModelTests {
    @Test func myTest() { ... }
}
```

**Applies to suites that:**
- Create test `CGImage` via `NSBitmapImageRep` + `NSGraphicsContext.current`
- Use `NSGraphicsContext.saveGraphicsState()` / `restoreGraphicsState()`
- Modify any other global AppKit state

**Note:** `.serialized` only serializes within a single process. Swift Testing may still split your suite across processes. If you need full serialization, run tests with `-only-testing:TargetName/SuiteName` to constrain to one process.

## 0.000s Cascade Failure Diagnostic

When `xcodebuild test` reports tests failing at exactly `0.000 seconds`, the test never executed. The test process was killed by a fatal error (e.g., `fatalError`, out-of-bounds access, broken precondition) in a different test running in the same process.

**Diagnostic pattern:**
- Some tests pass with real timing (e.g., `0.012 seconds`)
- Remaining tests all fail at `0.000 seconds`
- The first failing test in chronological order is the actual culprit
- Tests after it are cascade victims

**Fix approach:**
1. Identify the first 0.000s failure — it's often the fatal error source
2. Run that test in isolation with `-only-testing:Suite/testName` to get the real error
3. If it passes in isolation, the fatal error is in a preceding test in the same process

## Closed Range `(a+1)...b` Fatal Error

Swift's closed range operator `...` requires `lowerBound <= upperBound`. When `a >= b`, `(a+1)...b` panics at runtime with `Fatal error: Range requires lowerBound <= upperBound`.

**Example from `buildMoveMapping`:**
```swift
// When fromFirst == to (e.g., single element, moving index 0 to position 0):
for i in (fromFirst + 1)...to {  // (0+1)...0 = 1...0 → FATAL
    oldPos[i - 1] = i
}
```

**Fix:** Guard the no-op case:
```swift
guard to != fromFirst else { return oldPos }
```

**Alternative:** Use half-open range `..<` where semantically appropriate — `(a+1)..<b` produces an empty range when `a+1 >= b`, which is safe. But this changes loop semantics (excludes the upper bound), so verify correctness.

## Performance Tests with XCTClockMetric and XCTCPUMetric

Write performance tests to establish baselines and catch regressions:

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
            for _ in 0..<20 {
                vm.scrollPanDelta(by: CGSize(width: 5, height: 3))
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
```

**Key points:**
- Accept first run as baseline, then lower as you optimize
- Tests fail if runtime exceeds baseline by a significant margin
- Use mocks (TrackingAssembler) for deterministic measurements
- Include `await Task.sleep` after `Task.detached` work to let it complete before the measure block ends

## OSSignpost Markers for Profiling

Add `OSSignposter` intervals around expensive operations to make them visible in Instruments:

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

See [references/tooling/performance-debugging.md](../tooling/performance-debugging.md) for signpost placement guidance.

## UserDefaults Test Suite Stability

A computed property that creates a new `UserDefaults(suiteName: UUID())` on each access produces a different suite per read. Save and load go to different suites, causing every test assertion to fail.

**Fix:** Store the suite as a stable instance property initialized in `init`:

```swift
// WRONG — new suite per access, save/load go to different suites
class TestPersistence {
    var userDefaults: UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!  // Different UUID each call
    }
}

// CORRECT — stable suite for the lifetime of the instance
class TestPersistence {
    private let userDefaults: UserDefaults

    init() {
        userDefaults = UserDefaults(suiteName: UUID().uuidString)!  // One UUID, stable
    }
}
```

## UserDefaults Test Isolation with UUID Suite Names

When tests create ViewModel instances that load from `UserDefaults`, debounced saves from one test can pollute the next test's initial state. Each test needs an isolated `UserDefaults` suite.

**Pattern:**
```swift
private func makeViewModel() -> CollageViewModel {
    let suiteName = "Tests.\(UUID().uuidString)"
    let testDefaults = UserDefaults(suiteName: suiteName)!
    let persistence = UserDefaultsPersistence(defaults: testDefaults)
    return CollageViewModel(saliencyAnalyzer: ..., assembler: ..., persistence: persistence)
}
```

The UUID ensures each ViewModel gets a fresh, empty `UserDefaults` that no other test can access. No cleanup needed — the suite is abandoned after the test completes.

## App Sandbox Blocks Test File Access

A sandboxed macOS app (`ENABLE_APP_SANDBOX = YES`) cannot read arbitrary directories via `FileManager`, even when the path is valid. The call silently returns `nil` with no error or crash. This blocks test infrastructure that loads fixtures from environment variables (e.g., `COLLAGEMAKER_TEST_IMAGES_DIR=/path/to/TestImages`).

**Fix:** Disable the sandbox for Debug builds in `project.pbxproj`:
```
/* Debug */ = {
    isa = XCBuildConfiguration;
    buildSettings = {
        ENABLE_APP_SANDBOX = NO;
        ...
    }
};
```
Release builds retain the sandbox for production safety.

**Debugging clues:**
- `FileManager.default.contentsOfDirectory(at:)` returns `nil` for a verified path
- No crash, no exception — just silent `nil`
- `os_sandbox` subsystem in `log stream` may show access denied events

**Prevention:**
- Disable sandbox for Debug builds when test infrastructure reads files from arbitrary paths
- Use absolute paths in environment variables — `open` launches with `~` as the working directory
- Add `OSLog` at the file discovery boundary to distinguish "path wrong" from "path correct but sandbox blocked"

## Pixel Sampling for Background Verification in Tests

When verifying background colors render correctly in headless test environment:

1. **Don't sample panel centers** — they show panel content (white from `createTestImageItem`), not background.
2. **Don't use full-canvas solid fill with no panels** — produces all-black output in headless JPEG roundtrip via `NSImage(data:)`.
3. **Use gutter-region sampling** — create a layout with multiple small panels and large gutters (e.g., 4 images, gutter=20), then sample the canvas center which falls in the gap between panels.

```swift
let panels = LayoutGenerator.generate(
    numImages: 4, canvasSize: canvasSize, gutter: 20, style: .uniform
)
// ... set up crops with small source rects (50x50) ...
// Sample center pixel — falls in gutter between the 2×2 panel grid

let width = Int(canvasSize.width)
let height = Int(canvasSize.height)
let idx = ((height / 2) * width + width / 2) * 4
let r = Int(pixels[idx])
let g = Int(pixels[idx + 1])
let b = Int(pixels[idx + 2])
// Verify color matches expected background
```

## ImageItem.cgImage Is a Stored Property, Not a Method

`createTestImageItem(...)` returns `ImageItem`, which has `let cgImage: CGImage` as a stored property. Do NOT call it as a method:

```swift
// ❌ WRONG — "cannot call value of non-function type 'CGImage'"
let cg = createTestImageItem(color: .white).cgImage(forProposedRect: nil, context: nil, hints: nil)

// ✅ CORRECT — cgImage is already a CGImage property
let cg = createTestImageItem(color: .white).cgImage
```

## Canvas Coverage Thresholds by Layout Style

Sum-of-bounding-boxes coverage varies significantly by layout geometry. Use these relaxed thresholds for fitness functions:

| Layout | Typical Coverage (10 images) | Recommended Minimum | Reason |
|---|---|---|---|
| `.uniform` | 65–99% | ≥25% | Empty grid cells when N ≠ C×R |
| `.hero` | 70–95% | ≥25% | Hero panel + side strip leaves gaps |
| `.mosaic` | 60–90% | ≥25% | Random split ratios leave unused space |
| `.diagonalSlices` | 40–80% | ≥10% | Shear-transformed parallelograms don't fill corners |
| `.hexagonal` | 10–60% | ≥10% | Circle-packed hexagons have inherent spacing gaps |

**Rule:** Coverage thresholds should be fitness-function level (catch total regressions), not precision requirements. The plan's "≥95%" is unrealistic for most layouts.

## Pitfalls
- **Background style parameter mismatch** — `makeAssemblyConfig()` reads `backgroundColor:` for `.solid`/`.image` styles and `gradientStartColor:`/`gradientEndColor:` only for `.gradient`. Passing gradient colors with `.solid` produces silent full-canvas black. See § "Pixel Sampling for Background Verification in Tests" for the gutter-region sampling pattern to verify backgrounds render correctly.
- **ImageItem.cgImage is a stored property** — `createTestImageItem(color:).cgImage` returns `CGImage`. Do NOT call `.cgImage(forProposedRect:context:hints:)` on it — that's `NSImage.cgImage`, not `CGImage.cgImage`. Calling it as a method produces "cannot call value of non-function type 'CGImage'".
- **Shadow implementation** — Duplicating production logic in a test file to verify `private` code provides zero regression protection. Extract to `internal` or a static model method.
- **`xcodebuild test` skips Swift Testing** — use `-only-testing:TargetName` flag
- **`@MainActor` test struct** — annotate test structs when testing `@testable` imports with `@MainActor` types
- **`NSGraphicsContext` state** — always `saveGraphicsState()` / `restoreGraphicsState()` for test image creation
- **`@Suite(.serialized)` for shared state** — When test fixtures modify global AppKit state (`NSGraphicsContext.current`, etc.), annotate the suite with `@Suite(.serialized)` to prevent cross-process parallelization from causing 0.000s cascade failures
- **0.000s failures are cascades** — Tests failing at exactly 0.000s never executed. The process was killed by a fatal error in a preceding test. Run tests in isolation to find the real culprit
- **`EXC_BREAKPOINT`** — means Swift `fatalError`, not a memory crash
- **Static/instance method recursion** — If a class has both `static func foo` and `func foo`, the instance method must call `Self.foo()` to reach the static version. Calling `foo()` from the instance method recurses silently
- **Unused parameters in private methods** — Swift doesn't warn about unused parameters in private methods. If a parameter is no longer needed, either remove it or use `_ = param` to suppress linter complaints
- **Mock return types require explicit `return`** — Protocol methods with non-void return types don't allow implicit returns from expression statements. Must write `return Data()`, not just `Data()`
- **`Task.detached` races** — ViewModel methods that fire `Task.detached` return before the task runs. Tests asserting on mock state from inside the task need `await Task.sleep(nanoseconds: 50_000_000)` before assertions
- **Mock method symmetry** — If the protocol has multiple methods (e.g., export vs preview assembler), the mock must track fields on every method the ViewModel actually calls. Asserting on the wrong method's tracking data produces silently passing tests
- **Aspect ratio assumption** — When testing coordinate math, never assume which axis constrains. Compute fitted dimensions first, then offset, then mapped rect
- **`sed` for bulk test fixes** — When Swift Testing version doesn't support `tolerance:`, `find -exec sed -i '' 's/, tolerance: 0\.01//g' {} +'` across the test directory is the fastest way to fix many occurrences
- **UserDefaults test suite instability** — A computed property that creates `UserDefaults(suiteName: UUID())` each access generates a different suite per read, so save/load go to different suites. Store as a stable instance property initialized in `init`.
- **Identity-based cache tests are fragile** — `===` on cached `@Observable` objects can fail due to macro re-creation or test ordering. Prefer behavioral tests: compare computed values (e.g., `minWidth`, `frame.origin.x`) to verify cache hit/miss outcomes.
- **XCUIAutomation macOS APIs differ from iOS** — `setEnvironment`, `menuItem`, `typeKeyword`, `focus()`, and `wait(for:)` return type all behave differently or don't exist. See § "XCUIAutomation macOS API Gotchas"
- **UndoManager coalescing in tests** — Consecutive `registerUndo` calls for the same target within a Swift Testing `@MainActor` context are merged into one entry. Test single undo actions in isolation; cover multi-action sequences with integration gauntlets. See § "UndoManager Coalescing in Tests"
- **Walking up from `bundleURL` to find resources** — Never chain `deletingLastPathComponent()` from `Bundle(for:).bundleURL` to locate test fixtures. The UITest bundle lives in DerivedData, so path walking never reaches source files. Use `Bundle(for:).url(forResource:withExtension: nil)` instead, with the resource added to the UITest target's Resources build phase. See § "UITest Bundle Resource Discovery"
- **`.timeLimit()` syntax** — Swift Testing's `.timeLimit()` trait requires time values in **minutes**, not seconds. Use `.minutes(1)` or fractional minutes like `.minutes(0.5)`. `.seconds(N)` is unavailable and causes compilation errors.

## Identity-Based Cache Testing

Use `===` on cached reference-type objects to distinguish cache hits from misses. Each recomputation produces a new instance, so identity comparison is a reliable signal:

```swift
@Test func positionChangeDoesNotInvalidateMetrics() {
    let first = vm.titleMetrics?.preparedString
    vm.titleStyle.positionX = 0.25  // shouldn't invalidate layout cache
    let second = vm.titleMetrics?.preparedString
    #expect(first === second)  // same instance = cache hit
}

@Test func fontChangeInvalidatesMetrics() {
    let first = vm.titleMetrics?.preparedString
    vm.titleStyle.fontFamily = "Helvetica"  // should invalidate
    let second = vm.titleMetrics?.preparedString
    #expect(first !== second)  // different instance = cache miss + recompute
}
```

**Caveat:** Identity comparison is fragile with `@Observable` — the macro may re-create underlying objects, and test ordering can affect identity. Prefer behavioral tests when possible.

## Behavioral Cache Testing (Preferred)

Test the *outcome* of caching (expensive computation skipped, cheap math still runs) rather than object identity. Behavioral tests are more resilient to `@Observable` internals and test ordering:

```swift
@Test func positionChangeReusesCachedBounds() {
    let minWidthBefore = vm.cachedTitleMinWidth
    let frameBefore = vm.cachedTitleCanvasFrame
    vm.titleStyle.positionX = 0.75  // position-only change

    #expect(vm.cachedTitleMinWidth == minWidthBefore)  // bounds unchanged = cache hit
    #expect(vm.cachedTitleCanvasFrame?.origin.x != frameBefore?.origin.x)  // frame math updated
}

@Test func layoutChangeInvalidatesCache() {
    let minWidthBefore = vm.cachedTitleMinWidth
    vm.titleStyle.fontFamily = "Helvetica"  // layout-affecting change

    #expect(vm.cachedTitleMinWidth != minWidthBefore)  // bounds changed = cache miss + recompute
}
```

Behavioral tests verify that the expensive computation (bounds) is reused while cheap math (frame position) still runs — without depending on object identity.

## Testing Synchronous DispatchQueue Closures

When testing an actor that bridges async/await to synchronous `DispatchQueue` work (e.g., `RenderScheduler`), the closure is **synchronous** — `await` is illegal, and mutating captured `var` fails under Swift 6 strict concurrency.

**Pattern — ThreadSafeArray:**
```swift
final class ThreadSafeArray<Element: Sendable>: @unchecked Sendable {
    private var items: [Element] = []
    private let lock = NSLock()

    func append(_ item: Element) { lock.lock(); defer { lock.unlock() }; items.append(item) }
    func getItems() -> [Element] { lock.lock(); defer { lock.unlock() }; items }
}

@Test func renderClosureExecutes() async throws {
    let tracker = ThreadSafeArray<String>()
    await scheduler.render {
        tracker.append("enter")
        Thread.sleep(forTimeInterval: 0.001)  // Sync sleep, not Task.sleep
        tracker.append("exit")
        return ()
    }
    #expect(tracker.getItems() == ["enter", "exit"])
}
```

**Why not alternatives:**
- `actor` + `await` — closure is synchronous, `await` is a compile error
- `NSLock` on local `var` — Swift 6 forbids mutation of captured vars in concurrent code
- `@MainActor` — queue runs on background thread

See [references/state/swift-concurrency.md](../state/swift-concurrency.md) § "Synchronous Closures Inside withCheckedContinuation".

## XCUIAutomation macOS API Gotchas

Several XCUIAutomation APIs referenced in Apple documentation and online examples do not exist in the macOS SDK. Verify API availability against the actual SDK — iOS APIs differ.

### Passing Configuration to the Test Target

`XCUIApplication.setEnvironment(_:forVariable:)` does not exist. Use `launchArguments`:

```swift
app.launchArguments = ["COLLAGEMAKER_TEST_IMAGES_DIR=/path/to/TestImages"]
```

Read from `CommandLine.arguments` in the app:

```swift
let dirPath = ProcessInfo.processInfo.environment["COLLAGEMAKER_TEST_IMAGES_DIR"]
    ?? CommandLine.arguments.first(where: { $0.hasPrefix("COLLAGEMAKER_TEST_IMAGES_DIR=") })?
    .components(separatedBy: "=").last
```

### Querying Menu Items

`app.menus.menuItem["Item Name"]` is a compile error. Use `app.menuItems` directly:

```swift
let uniformItem = app.menuItems["Uniform"]
XCTAssertTrue(uniformItem.exists)
```

### Text Input

`element.typeKeyword(.a)` does not exist. Use `typeText(_:)`:

```swift
element.typeText("Test Title")
```

### Focus

`element.focus()` does not exist. `typeText(_:)` works without an explicit focus call — XCUIAutomation handles focus automatically.

### Waiting for Conditions

`wait(for:timeout:)` on `XCTestCase` returns `Void` in some SDK versions, not `DispatchTimeoutResult`. Comparing against `.timedOut` is a compile error. Use a polling loop:

```swift
private func waitForImagesLoaded(timeout: TimeInterval = 60) {
    let deadline = Date().addingTimeInterval(timeout)
    let exportButton = app.buttons["Export collage as JPEG"]

    while Date() < deadline {
        if exportButton.exists && exportButton.isEnabled {
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    XCTFail("Timed out waiting for images to load")
}
```

### Compiler Error Quick Reference

| Error | Fix |
|---|---|
| `'XCUIApplication' has no member 'setEnvironment'` | Use `launchArguments` |
| `'XCUIElementQuery' has no member 'menuItem'` | Use `app.menuItems[]` |
| `cannot convert 'Void' to 'DispatchTimeoutResult'` | Use `RunLoop` polling loop |

## UITest Bundle Resource Discovery

XCUIAutomation tests need test fixture files (images, data, etc.) accessible to the launched app. Resources are **not automatically copied** into UITest bundles — the UITest target starts with an empty Resources build phase.

### The Anti-Pattern: Walking Up from bundleURL

```swift
// ❌ NEVER DO THIS — always fails
let bundleURL = Bundle(for: Self.self).bundleURL
let candidates = [
    bundleURL.deletingLastPathComponent().deletingLastPathComponent()...,
]
```

This fails because:
1. The UITest bundle lives in DerivedData, not the source tree
2. Walking up from DerivedData never reaches source files
3. The path depth varies by Xcode version and project configuration

### Step 1: Add a Folder Reference to project.pbxproj

Four edits are needed to copy resources into the UITest bundle:

1. **PBXFileReference** — Add a folder reference to the resource directory:
```
TESTIMAGES_REF /* TestImages */ = {isa = PBXFileReference; lastKnownFileType = folder; name = TestImages; path = ../TestImages; sourceTree = "<group>"; };
```

2. **PBXBuildFile** — Create a build file for the reference:
```
TESTIMAGES_BUILD /* TestImages in Resources */ = {isa = PBXBuildFile; fileRef = TESTIMAGES_REF /* TestImages */; };
```

3. **PBXGroup** — Add to the project's main group children for Xcode navigator visibility.

4. **PBXResourcesBuildPhase** — Add the build file to the UITest target's Resources phase:
```
UITests_Resources /* Resources */ = {
    isa = PBXResourcesBuildPhase;
    files = (
        TESTIMAGES_BUILD /* TestImages in Resources */,
    );
};
```

### Step 2: Use Bundle API to Discover Resources

```swift
// ✅ Correct — works regardless of DerivedData path structure
let testImagesPath = Bundle(for: Self.self).url(forResource: "TestImages", withExtension: nil)!.path
```

**Key:** `withExtension: nil` finds a folder resource, not a file with an extension.

### Verification

After `project.pbxproj` edits, verify with `build-for-testing` (not just `build`):

```bash
xcodebuild build-for-testing -project App.xcodeproj -scheme App -destination 'platform=macOS,arch=arm64'
```

Then check the built bundle:
```bash
ls ~/Library/Developer/Xcode/DerivedData/App-*/Build/Products/Debug/UITestRunner.app/Contents/PlugIns/UITests.xctest/Contents/Resources/TestImages/
```

### Debugging Clues

- `FileManager.default.fileExists(atPath:)` returns `false` for paths built from `bundleURL.deletingLastPathComponent()` chains
- A fallback path in a `candidates` array is always the last tried and always wrong
- `ls` on the built test bundle's `Contents/Resources/` shows no resource directory if the build phase is misconfigured
- `build` alone does not compile the UITest target — use `build-for-testing`

## UndoManager Coalescing in Tests

`UndoManager` coalesces consecutive undo registrations targeting the same object within a single run loop cycle. In Swift Testing with `@MainActor`, the Cocoa run loop is not active — all work goes through Swift's task scheduler, which never creates the event boundaries `UndoManager` needs to separate actions.

**Result:** Two consecutive `registerUndo` calls for the same property (e.g., `setLayoutStyle(.grid)` then `setLayoutStyle(.freeform)`) are merged into one undo entry. Only the last registration survives.

### What Does NOT Work

None of these create a new run loop cycle in Swift Testing environments:

```swift
// ❌ DispatchQueue.main.async — not drained by the run loop in test context
DispatchQueue.main.async { undoManager.registerUndo(...) }

// ❌ Task on MainActor — Swift scheduler, not Cocoa event loop
let task = Task { @MainActor in undoManager.registerUndo(...) }
await task.value

// ❌ RunLoop.main.run(until:) — drains NSRunLoop sources, not libdispatch
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

// ❌ beginUndoGrouping/endUndoGrouping — coalescing is per-target, not per-group
undoManager.beginUndoGrouping()
undoManager.registerUndo(...)
undoManager.endUndoGrouping()
```

### What Works

**Test single undo actions in isolation** — Each test exercises one operation + one `undo()`. Coalescing only occurs with consecutive registrations on the same target:

```swift
@Test func undoLayoutStyleRestoresPrevious() async throws {
    let vm = makeViewModel()
    vm.setLayoutStyle(.grid)
    vm.undoManager.undo()
    #expect(vm.layoutStyle == .freeform)
}
```

**Cover multi-action sequences with integration tests** — A gauntlet test (e.g., `undoMultiStepSequence`) validates undo works across a real sequence of different operations without testing consecutive changes to the same property:

```swift
@Test func undoMultiStepSequence() async throws {
    let vm = makeViewModel()
    vm.addImages([createTestImageItem()])
    vm.setLayoutStyle(.grid)
    vm.removeImage(at: 0)
    vm.setBackgroundStyle(.color(.red))

    // Each undo reverses the preceding distinct action
    vm.undoManager.undo()
    #expect(vm.backgroundStyle == .default)

    vm.undoManager.undo()
    #expect(vm.images.count == 1)

    vm.undoManager.undo()
    #expect(vm.layoutStyle == .freeform)
}
```

**Accept coalescing as expected in production** — In the real app, consecutive calls to the same setter are separated by user interactions (run loop cycles), so coalescing never occurs. The test environment is the anomaly.
