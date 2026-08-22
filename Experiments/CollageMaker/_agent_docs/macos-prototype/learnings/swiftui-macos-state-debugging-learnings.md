# SwiftUI macOS App Development — Debrief 2026-05-09

**Purpose**: Capture learnings from debugging the CollageMaker "sliders stop responding" bug, including SwiftUI state management pitfalls, integration testing with real images, and CLI build/launch workflows.

## What Worked

- **Integration tests with real images** — Loading actual photos via `NSImage(contentsOf:)` and exercising the `CollageViewModel` crop workflow through 7 focused tests effectively isolated the bug to the UI layer. All ViewModel tests passed, proving `updateCrop` handles repeated updates, resets, and post-reset updates correctly. This approach is invaluable when you cannot observe the running app directly.

- **`xcodebuild build` + `open` workflow** — Building from the command line with `xcodebuild -project ... -scheme ... -configuration Debug -destination 'platform=macOS' build` then launching with `open "<DerivedData>/Build/Products/Debug/CollageMaker.app"` provides a functional manual testing loop without Xcode IDE.

- **`@EnvironmentObject` pattern** — The Session 5 fix of moving from `@ObservedObject` stored properties to `@EnvironmentObject` injection eliminated the `MainActor.assumeIsolated` crashes, making the view hierarchy stable for this debugging session.

- **Swift Testing framework `@Test` + `#expect`** — The parameter-less `@Test` API with `#expect(message, condition)` assertions worked well for writing focused, self-documenting tests.

## What Didn't Work / Gaps

- **`@State` with `Timer?` — Silent, invisible failure** — `@State private var debounceTimer: Timer?` produced zero warnings, zero errors, and zero crashes. The timer simply stopped working after the first view re-render. This is because `@State` requires `Equatable` value types, and `Timer?` is a non-Equatable reference type. SwiftUI's `@State` wrapper lost the timer reference during struct recreation, causing all subsequent `scheduleUpdate()` calls to fire into deallocated memory.

- **`NSUnbufferedIO=YES open` — No useful stdout** — Setting `NSUnbufferedIO=YES` before `open` did not produce meaningful console output from the SwiftUI app. The app's internal operations (slider changes, crop updates, preview generation) don't emit logs by default.

- **`xcodebuild test` — Swift Testing tests not discovered by default** — Running `xcodebuild test` only ran the XCTest-based UI tests. The Swift Testing framework tests in `CollageMakerTests` were silently skipped. Required `xcodebuild test -only-testing:CollageMakerTests` to actually execute them.

- **Blind debugging without app visibility** — Since the agent cannot observe the running GUI, the only way to understand the bug flow was to write tests that exercise the same code paths. This is slower than watching the app but more systematic.

## What Was Confusing

- **Why sliders worked once then stopped** — The symptom (first slider change works, reset works once, then nothing) pointed to a state management issue, but without SwiftUI logging it's unclear which layer is broken. The ViewModel tests confirmed the logic layer is fine, narrowing it to the view layer.

- **`@State` doesn't warn about non-Equatable types** — Swift's compiler doesn't warn when you store a non-Equatable type in `@State`. It compiles cleanly but behaves incorrectly at runtime.

- **View struct recreation timing** — SwiftUI recreates `View` structs on every body invalidation. A `Timer?` stored in `@State` on a struct is subject to this lifecycle, which isn't obvious from the API surface.

## Key Learnings

### SwiftUI State Management

1. **`@State` requires `Equatable` value types only** — Never store reference types (`Timer?`, `NSObject`, custom classes) in `@State`. The `@State` property wrapper uses `Equatable` conformance to track changes, and reference types break this contract silently.

2. **`@StateObject` for objects that must survive re-renders** — When you need a reference type (like a `Timer`, or a class with mutable state) to persist across view body invalidations, use `@StateObject` with an `ObservableObject` class. The class instance is owned by the view and survives struct recreation.

   ```swift
   @MainActor
   final class CropEditorState: ObservableObject {
       @Published var offsetX: Double = 0
       @Published var offsetY: Double = 0
       @Published var zoom: Double = 1.0
       private var debounceTimer: Timer?  // Safe here — class persists

       func scheduleUpdate(action: @escaping () -> Void) {
           debounceTimer?.invalidate()
           debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
               action()
           }
       }
   }

   struct PanelCropEditor: View {
       @StateObject private var state = CropEditorState()
       // Use state.offsetX, state.offsetY, state.zoom
   }
   ```

3. **`@EnvironmentObject` for shared `@MainActor` view models** — When the `ObservableObject` is `@MainActor`-isolated, always use `@EnvironmentObject` rather than `@ObservedObject` with stored properties. Stored properties on `View` structs can cause `MainActor.assumeIsolated` crashes when closures capture stale `self`.

### Testing Strategy

4. **ViewModel integration tests isolate UI bugs** — When the app exhibits mysterious behavior, write tests that exercise the ViewModel with real data. If tests pass, the bug is in the view layer. This is especially valuable when you cannot observe the GUI directly.

5. **Real images in tests are practical** — Loading actual images from disk via `NSImage(contentsOf:)` works reliably in tests. No need for synthetic CGImage fixtures when testing high-level workflows like crop management.

6. **`xcodebuild test -only-testing:TargetName` for Swift Testing** — The Swift Testing framework is not auto-discovered by `xcodebuild test`. Use the `-only-testing:` flag to explicitly target the test bundle.

### Build and Launch

7. **CLI build and launch workflow**:
   ```bash
   # Build
   xcodebuild -project "Path/To/App.xcodeproj" -scheme AppName \
       -configuration Debug -destination 'platform=macOS,arch=arm64' build

   # Launch
   open "/Users/$USER/Library/Developer/Xcode/DerivedData/AppName-*/Build/Products/Debug/AppName.app"
   ```

8. **DerivedData path pattern** — Use glob `*/Build/Products/Debug/AppName.app` to find the built app, since the hash suffix varies.

## Skill Improvements

### Update `building-swiftui-macos-apps` Skill

1. **Add State Management Rules**:
   - `@State` for `Equatable` value types only (primitives, structs, enums)
   - `@StateObject` for `ObservableObject` classes with reference-type state (timers, network clients, etc.)
   - `@EnvironmentObject` for shared `@MainActor` view models across view hierarchies
   - Never store `Timer?`, `NSObject`, or class references in `@State`

2. **Add Debugging Patterns**:
   - When GUI behavior is unclear, write ViewModel integration tests with real data to isolate UI vs logic bugs
   - Use `@MainActor final class` for state holders that need `@Published` properties and reference-type members

3. **Add CLI Build/Launch section**:
   - Document the `xcodebuild` + `open` workflow for manual testing
   - Note that `NSUnbufferedIO=YES` doesn't produce useful output for SwiftUI apps
   - Document `-only-testing:` flag for Swift Testing framework

4. **Add Common Pitfalls**:
   - `@State` with non-Equatable types — silent failure, no warnings
   - `Timer` in `@State` — lost on view re-render, causes "works once then stops" behavior
   - `xcodebuild test` skips Swift Testing — need `-only-testing:` flag

## Next Steps

- Rebuild app with the `CropEditorState` fix and verify sliders work continuously
- Test Reset Crop followed by multiple slider adjustments
- Test switching between panels and adjusting each independently
- Add the integration tests to the permanent test suite
- Apply learnings to `building-swiftui-macos-apps` skill

---
**Status**: In Progress
**Follow-up**: Manual test of fix, skill update, remaining test coverage
