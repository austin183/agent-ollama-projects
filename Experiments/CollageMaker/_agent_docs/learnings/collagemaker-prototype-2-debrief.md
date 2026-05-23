# CollageMaker Prototype 2 — Debrief 2026-05-10

**Purpose**: Capture learnings from building Prototype 2 (Phases 1-6), including 16 source files, 7 test files, 64 passing tests, and all build/test issues encountered.

## What Worked

- **Protocol-based DI from day 1** — `SaliencyAnalysis` and `CollageAssembly` protocols made mocking trivial. `MockSaliencyAnalyzer` and `MockAssembler` were straightforward to write and immediately useful for ViewModel tests.

- **`NSBitmapImageRep` with RGBA for context creation** — Works in both production and test environments, completely eliminating the `[.byteOrder32Big]` test-only failure discovered in Prototype 1. The production `CollageAssembler` was refactored to use this approach.

- **File-by-file test writing order** — Helpers → pure functions (LayoutGenerator) → simple models (SaliencyResult) → services with CG (Assembler) → actors (SaliencyAnalyzer) → managers (CropManager) → view model. Each layer built on the previous one's fixtures.

- **Extracted helper methods during test fixes** — `createBitmapContext()` and `drawPanels()` improved `CollageAssembler` readability while fixing the test issue.

- **`@MainActor` on test structs** — Eliminated all Swift 6 concurrency warnings when testing `@MainActor` types.

## What Didn't Work / Gaps

- **`#throw` macro not available** — The Swift Testing `#throw` macro is not available in all Xcode versions. Required `do/catch` + `Issue.record("Expected error")` workaround.

- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` build setting** — Caused protocol isolation conflicts with explicit `@MainActor` annotations on `CollageViewModel` and `CropManager`. Had to be removed from `project.pbxproj`.

- **`xcresulttool get` deprecated** — The command requires `--legacy` flag now. The JSON structure uses `_type`, `_values`, `_value` wrappers everywhere, making it painful to parse programmatically.

- **Pan crop test with full-coverage image** — When the test image fills the panel completely (1:1 aspect ratio), there's no room to pan. Had to add `beginPinch` → `pinch(0.5)` → `applyPinch` before the pan to create room.

- **`CGBitmapInfo.noneSkipLast` not available** — Swift 6 doesn't expose this. Tried `.alphaInfoNone` (doesn't exist), `.alphaNoneSkipLast` (doesn't exist). Solution was to abandon raw `CGContext` entirely and use `NSBitmapImageRep`.

- **`CGImage.imageOrientation` doesn't exist** — CGImage has no `imageOrientation` property. Orientation is handled by the containing `NSImage`. Used `CGImagePropertyOrientation.up` instead.

- **`SimultaneousGesture` API** — Can't nest `DragGesture` + `MagnificationGesture` inside a single `SimultaneousGesture(...)`. Requires separate `.simultaneousGesture()` modifiers on the view.

- **`MagnificationGesture.Value` is `CGFloat`** — Not an object with a `.magnification` property. The value itself is the magnification factor.

## What Was Confusing

- **`CGContext` parameter order** — `LayoutGenerator.generate(numImages:heroIndex:gutter:style:)` requires `gutter` before `style`. Swift's labeled arguments enforce this, but it's easy to get wrong.

- **`xcresulttool` JSON structure** — Every field is wrapped in `_type`/`_values`/`_value` objects. Parsing requires navigating 5+ levels of nesting to reach actual test failure messages.

- **`xcodebuild` parallel test execution** — Tests run across multiple processes, making output interleaved and hard to correlate with specific test cases.

- **`CGBitmapInfo` alpha options availability** — The available options differ between Swift versions. `.noneSkipLast` worked in Swift 5 but not Swift 6. No clear documentation of what's available.

## Skill Improvements

### Update `building-swiftui-macos-apps` Skill

1. **Add to Common Pitfalls**:
   - `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` build setting conflicts with explicit `@MainActor` — avoid it
   - `#throw` macro not available in all Xcode versions — use `do/catch` + `Issue.record`
   - `xcresulttool get` deprecated — use `--legacy` flag
   - `CGImage.imageOrientation` doesn't exist — use `CGImagePropertyOrientation.up`
   - `CGBitmapInfo.noneSkipLast` not available in Swift 6 — use `NSBitmapImageRep` with RGBA
   - `SimultaneousGesture` requires separate `.simultaneousGesture()` modifiers
   - `MagnificationGesture.Value` is `CGFloat`, not an object

2. **Update Testing Patterns**:
   - Recommend `NSBitmapImageRep` with RGBA for ALL context creation (both test and production)
   - Add `do/catch` + `Issue.record` pattern for testing async throwing functions
   - Add `xcresulttool --legacy` note

3. **Update Concurrency section**:
   - Note that `SWIFT_DEFAULT_ACTOR_ISOLATION` build setting causes more problems than it solves
   - Explicit `@MainActor` annotations are more reliable

### Update `testing-patterns.md` Reference

4. **Add error testing pattern**:
```swift
@Test func throwsForInvalidInput() async {
    do {
        _ = try await service.method(invalidInput)
        Issue.record("Expected error")
    } catch {
        #expect(error is ExpectedErrorType)
    }
}
```

5. **Add `xcresulttool` deprecation note** — Use `--legacy` flag or prefer `grep` on xcodebuild output

## Next Steps

- Phase 7: Manual testing (build, launch, verify all features)
- Apply skill improvements from this debrief
- Consider adding integration tests with real images for gesture workflow

---
**Status**: Open
**Follow-up**: Phase 7 manual testing, skill updates
