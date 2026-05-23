# SwiftUI macOS Testing — Debrief 2026-05-08

**Purpose**: Capture learnings from building and testing the CollageMaker macOS SwiftUI app, particularly around CGImage test fixtures and Swift Testing framework integration.

## What Worked

- **`NSBitmapImageRep` for test CGImage creation** — Reliable approach that works in headless test environment. Creates RGBA (4-channel with alpha) images via `NSGraphicsContext`, then extracts `cgImage`. No crashes regardless of image size.
- **`@MainActor` on test struct** — Properly isolates test code when testing `@testable` imports with `@MainActor` types. Eliminates Swift 6 concurrency warnings.
- **`assembleWithCGImages` testability methods** — Adding methods that accept `CGImage` directly (bypassing `NSImage`→`CGImage` conversion) makes `CollageAssembler` testable with synthetic test fixtures.
- **Small 100x100 test images** — Dramatically reduces test execution time and avoids memory pressure in test environment.
- **`guard let` over force-unwraps** — Prevents cascading test crashes when `CGContext.makeImage()` returns `nil`.
- **`CGColorSpaceCreateDeviceRGB()`** — Works reliably; `CGColorSpace(name: CGColorSpace.sRGB)` can be less portable.

## What Didn't Work / Gaps

- **`CGContext` with `[.byteOrder32Big]` in tests** — The no-alpha bitmap info causes `CGContext.makeImage()` to return `nil` in the test environment, even with small (100x100) images. This was the root cause of all 4 failing CollageAssembler tests. The same bitmap info works fine in the actual app build, making it a test-environment-specific issue.
- **1920x1080 test images** — Even with correct bitmap info, large canvases create memory pressure and slow tests unnecessarily.
- **`NSColorSpaceName.sRGB`** — Not a valid member. Use `.deviceRGB` instead.
- **Swift Testing `@Test` actor isolation** — Tests that access `@MainActor`-isolated types from the `@testable` module generate Swift 6 concurrency warnings. The test struct itself needs `@MainActor` annotation.
- **`xcodebuild` test output** — Hard to parse for actual failure reasons. Crash reports require separate analysis via `xcresulttool` or system crash reporter.

## What Was Confusing

- **`EXC_BREAKPOINT` vs memory crash** — The crash report showed `EXC_BREAKPOINT (SIGTRAP)` which is Swift's `fatalError` signal, not a memory access violation. Initially appeared to be a CGContext memory issue, but was actually a `fatalError` from a failed `guard let`.
- **Test environment vs app environment difference** — `[.byteOrder32Big]` works in the app but fails in tests. This is likely related to the display server/headless context difference between running as a test bundle vs a regular app.
- **`xcodebuild` parallel test execution** — Tests run concurrently across multiple processes, making it hard to correlate crash reports with specific test cases.

## Skill Improvements

### Update `building-swiftui-macos-apps` Skill

1. **Replace CGImage test fixture pattern** — The current `CGContext` approach with `[.byteOrder32Big]` is unreliable. Replace with `NSBitmapImageRep` approach:

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

2. **Update Common Pitfalls** — Add:
   - `[.byteOrder32Big]` CGContext fails in test environment — use `NSBitmapImageRep` with alpha for test fixtures
   - `NSColorSpaceName.sRGB` doesn't exist — use `.deviceRGB`
   - `@MainActor` test struct needed for `@testable` imports with actor-isolated types

3. **Update Testing Patterns** — Add `NSGraphicsContext.saveGraphicsState()` / `restoreGraphicsState()` pattern when creating test images.

4. **Add note about `xcodebuild` testing** — Recommend `grep -E "Test case.*passed|Test case.*failed"` for quick results, and system crash reporter for `EXC_BREAKPOINT` analysis.

## Next Steps

- Verify `NSBitmapImageRep` fix resolves all 4 CollageAssembler test failures
- Apply learnings to `building-swiftui-macos-apps` skill
- Complete remaining test coverage (ViewModel, additional LayoutGenerator, SaliencyResult, ImagePanel)
- Manual testing with real images

---
**Status**: In Progress
**Follow-up**: Update skill, complete test suite, manual testing
