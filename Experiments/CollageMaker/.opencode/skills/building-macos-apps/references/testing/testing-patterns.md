# Testing Patterns

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
- **`tolerance:` not available** — This Xcode version's Swift Testing doesn't support `tolerance:` on `#expect()`. Use range checks: `#expect(value > lower && value < upper)`, or exact equality for integer-valued `CGFloat`s
- **`import Foundation` required for `UUID`** — `CoreGraphics` and `Testing` don't transitively import `Foundation`. New test files need `import Foundation` explicitly

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

## Pitfalls

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
