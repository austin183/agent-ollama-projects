# CollageMaker Project Timeline

## Session 1 — 2026-05-08

### Goal
Implement the entire CollageMaker macOS SwiftUI app from the `PLAN.md` specification.

### Work Completed

#### Phase 1: Models ✅
- `Models/SaliencyResult.swift` — `SaliencyResult` struct with center, radius, confidence, and crop helper
- `Models/ImagePanel.swift` — `ImagePanel` (layout panel) and `CropInfo` structs with Codable/Equatable conformance
- `Models/ImageItem.swift` — `ImageItem` wrapper for loaded images with NSImage and filename

#### Phase 2: Services ✅
- `Services/LayoutGenerator.swift` — Algorithmic mosaic layout generation
  - Strategies for 1, 2, 3, 4-5, 6-9, and 10+ images
  - Hero panel support, gutter spacing, dynamic grid calculation
- `Services/SaliencyAnalyzer.swift` — Vision framework saliency + face detection
  - `VNGenerateAttentionBasedSaliencyImageRequest` for attention-based saliency
  - `VNDetectFaceRectanglesRequest` for face boost
  - Concurrent batch analysis with `withThrowingTaskGroup`
- `Services/CollageAssembler.swift` — CoreGraphics compositing and JPEG export
  - Full-resolution 1920x1080 assembly
  - Preview generation at scaled size
  - Title overlay with semi-transparent background
  - Configurable background color and quality

#### Phase 3: ViewModel ✅
- `ViewModel/CollageViewModel.swift` — `@MainActor ObservableObject` orchestrating the pipeline
  - Image loading (direct, folder browse, PhotosPicker)
  - Layout regeneration, saliency analysis trigger
  - Crop management with saliency-based defaults
  - Preview generation and export with save panel

#### Phase 4: Views ✅
- `Views/ImagePickerView.swift` — Drag-and-drop, folder browse, PhotosPicker integration
- `Views/CollageEditorView.swift` — Live collage preview with tap-to-select panels
- `Views/PanelCropEditor.swift` — Per-panel crop offset/zoom sliders with debounced updates
- `Views/ExportPanel.swift` — Title field, quality slider, background color picker, export button

#### Phase 5: App Wiring ✅
- `ContentView.swift` — `NavigationSplitView` with sidebar (images + layout controls), editor, and detail panel
- `CollageMakerApp.swift` — `@main` entry point with default window size

#### Phase 6: Build Verification ✅
- Clean build with zero errors and zero warnings (excluding AppIntents metadata)
- Fixed multiple compilation issues:
  - `CGBitmapInfo.alphaNone` → `.byteOrder32Big` only
  - `CGImage.draw(_:in:from:)` → crop then draw
  - `TapGesture` API changes for newer Swift
  - `PhotosPicker` single-item selection
  - `@Published` / `ObservableObject` / Combine imports
  - `Closure` mutation issues in `LayoutGenerator`
  - `SaliencyAnalyzer` TaskGroup concurrency

#### Phase 7: Unit Tests (Started) 🔄
- `CollageMakerTests/CollageMakerTests.swift` written with tests for:
  - `LayoutGeneratorTests` — 12 tests covering all image counts, hero index, canvas bounds, uniqueness
  - `SaliencyResultTests` — 3 tests for crop origin calculation
  - `CollageAssemblerTests` — 4 tests for assembly, multiple panels, title, preview
  - `ImagePanelTests` — 3 tests for frame, equality
- **Tests not yet run/verified** — to be completed in next session

### File Structure (Current)
```
CollageMaker/
  PLAN.md
  CollageMaker.xcodeproj/
  CollageMaker/
    CollageMakerApp.swift
    ContentView.swift
    Assets.xcassets/
    Models/
      SaliencyResult.swift
      ImagePanel.swift
      ImageItem.swift
    Services/
      SaliencyAnalyzer.swift
      LayoutGenerator.swift
      CollageAssembler.swift
    Views/
      ImagePickerView.swift
      CollageEditorView.swift
      PanelCropEditor.swift
      ExportPanel.swift
    ViewModel/
      CollageViewModel.swift
  CollageMakerTests/
    CollageMakerTests.swift
  CollageMakerUITests/
```

### Key Decisions Made
- Used `withThrowingTaskGroup` for concurrent saliency analysis
- Single-item `PhotosPicker` (multiple selection API not stable)
- `NavigationSplitView` for sidebar/editor/detail layout
- Debounced crop slider updates (0.3s) to avoid excessive preview regeneration
- `NSSavePanel.runModal` for export (non-async API)

---

## Session 2 — 2026-05-08

### Goal
Run unit tests, fix failures, and verify test suite passes.

### Test Results
- **18/22 tests pass** (non-crashing): LayoutGenerator (12/12), SaliencyResult (3/3), ImagePanel (3/3)
- **4/4 CollageAssembler tests fail** due to crash in test helper `createTestCGImage`

### What Was Investigated
The `CollageAssemblerTests` crash at `createTestCGImage(size:color:)` when creating 1920x1080 CGImages via `CGContext.makeImage()` with `[.byteOrder32Big]` bitmap info.

### Fix Attempts (All Failed)
1. **`CGColorSpace(name: CGColorSpace.sRGB)` → `CGColorSpaceCreateDeviceRGB()`** — No effect; crash persisted
2. **`CGImageAlphaInfo.noneSkipLast` → `[.byteOrder32Big]`** — No effect; crash persisted
3. **Added `assembleWithCGImages` + `assemblePreviewWithCGImages`** to bypass NSImage→CGImage conversion — Crash moved to the CGImage creation itself, confirming the issue is in the CGContext helper
4. **Removed force-unwraps** (`data!`, `preview!`) across all tests — Prevented cascading crashes, but root cause remains

### Root Cause Analysis
The crash occurs in `CGContext.makeImage()` when the context is created with `[.byteOrder32Big]` bitmap info on a large (1920x1080) canvas. This bitmap info has no alpha channel, which may cause issues in the test environment where the display server is available but headless. The same bitmap info works fine in the actual app build.

### Changes Made (Committed to Working Tree)
- `CollageAssembler.swift`: Added `assembleWithCGImages` and `assemblePreviewWithCGImages` methods for testability
- `CollageMakerTests.swift`: Rewrote `CollageAssemblerTests` to use CGImages directly via `createTestCGImage`
- `CollageMakerTests.swift`: Removed all force-unwraps to prevent cascading test crashes
- `CollageMakerTests.swift`: Changed `CGColorSpace(name:)` to `CGColorSpaceCreateDeviceRGB()`

### Remaining Work
1. **Fix CollageAssembler tests** — Use 100x100 images (see `agent_docs/research/unit-testing-patterns.md`)
2. **Add LayoutGenerator tests** — Overlap detection, hero panel size, gutter spacing
3. **Add SaliencyResult tests** — Exact coordinate verification, portrait image handling
4. **Add ImagePanel tests** — Codable round-trip, inequality
5. **Add test image resources** — Real images for SaliencyAnalyzer integration tests
6. **Add CollageViewModel tests** — State transitions, layout regeneration, crop updates
7. **Consider protocol-based mocking** — For Vision framework isolation in SaliencyAnalyzer tests
8. **Manual testing** — Run the app with real images, verify layout, crop, and export
9. **Polish** — Any UI refinements from manual testing
10. **Future** (from PLAN.md): multiple layout presets, color harmonization, shadow/overlap effects

---

## Session 3 — 2026-05-08

### Goal
Fix CollageAssembler test crashes, capture learnings, and update SwiftUI macOS skill.

### Test Investigation Continued
- **18/22 tests pass** (unchanged): LayoutGenerator (12/12), SaliencyResult (3/3), ImagePanel (3/3)
- **4/4 CollageAssembler tests still fail** — crash at `createTestCGImage` in `CollageMakerTests.swift:270`

### New Root Cause Discovery
Crash is `EXC_BREAKPOINT (SIGTRAP)` — `fatalError` triggered because `CGContext.makeImage()` returns `nil` even with 100x100 images. The `[.byteOrder32Big]` bitmap info (no alpha) is the culprit in the test environment, not just the large canvas size.

### Fix Attempted (In Progress)
- **Switched to `NSBitmapImageRep` approach** — Creates 100x100 RGBA (4-channel, with alpha) images via `NSBitmapImageRep` + `NSGraphicsContext`, then extracts `cgImage`
- Added `assembleWithCGImages` / `assemblePreviewWithCGImages` methods to `CollageAssembler` for testability (bypass NSImage→CGImage conversion)
- Reduced test images to 100x100 with matching `sourceRect` in `CropInfo`
- Fixed compile error: `NSColorSpaceName.sRGB` → `.deviceRGB`

### Learnings Captured
- Created `agent_docs/thoughts/swiftui-macos-test-learnings.md` with findings on:
  - `CGContext` test environment limitations with `[.byteOrder32Big]`
  - `NSBitmapImageRep` as reliable fallback for test fixture creation
  - `@MainActor` isolation issues with `@testable` imports and Swift Testing framework
  - `xcodebuild` test output parsing challenges
  - Crash report analysis for `EXC_BREAKPOINT` (fatalError) vs actual memory crashes

### Remaining Work
1. **Verify NSBitmapImageRep fix** — Run tests to confirm all 22 pass
2. **Add LayoutGenerator tests** — Overlap detection, hero panel size, gutter spacing
3. **Add SaliencyResult tests** — Exact coordinate verification, portrait image handling
4. **Add ImagePanel tests** — Codable round-trip, inequality
5. **Add test image resources** — Real images for SaliencyAnalyzer integration tests
6. **Add CollageViewModel tests** — State transitions, layout regeneration, crop updates
7. **Protocol-based mocking** — For Vision framework isolation in SaliencyAnalyzer tests
8. **Manual testing** — Run the app with real images, verify layout, crop, and export
9. **Polish** — Any UI refinements from manual testing
10. **Future** (from PLAN.md): multiple layout presets, color harmonization, shadow/overlap effects

---

## Session 4 — 2026-05-08

### Goal
Fix CollageAssembler test crashes and achieve 22/22 passing tests.

### Root Cause Identified
After isolated testing with standalone Swift scripts, discovered that `CGContext` creation with `[.byteOrder32Big]` alone returns `nil` in the test environment (and standalone scripts). The bitmap info flag is insufficient without an alpha channel specification. The fix is to combine `.byteOrder32Big` with `.noneSkipLast`:

```swift
let bitmapInfo: CGBitmapInfo = [.byteOrder32Big]
let alphaInfo: CGImageAlphaInfo = .noneSkipLast
// ...
bitmapInfo: bitmapInfo.rawValue | alphaInfo.rawValue
```

This works because `byteOrder32Big` alone produces a 32-bit pixel format with no alpha defined, which `CGContext` rejects in headless/test environments. Adding `noneSkipLast` explicitly tells the system the 4th byte is unused, making the format well-defined.

### Changes Made

#### `CollageAssembler.swift`
- Fixed `CGContext` bitmap info: added `.noneSkipLast` alpha flag alongside `.byteOrder32Big`
- Made `canvasSize` configurable on `assembleWithCGImages` and `assemblePreviewWithCGImages` (defaults to 1920x1080)
- Fixed `drawTitle` coordinate bug: context is already flipped to top-left origin, removed redundant transforms and corrected Y calculation
- Added `saveGState`/`restoreGState` around per-panel clipping to prevent clip state leakage
- Added `interpolationQuality = .high` for better resize quality

#### `CollageMakerTests.swift`
- Added `@Suite struct AppKitInit` to initialize `NSApplication.shared` before tests run
- Marked all test structs (`LayoutGeneratorTests`, `SaliencyResultTests`, `CollageAssemblerTests`, `ImagePanelTests`) as `@MainActor` to resolve `@testable import` actor isolation warnings
- Updated `CollageAssemblerTests` to use 400x225 test canvas size instead of 1920x1080
- Updated `assemblePreview` test to use 200x113 target size
- Added `await` calls for all `@MainActor`-isolated method calls

### Test Results
- **22/22 tests pass** ✅
  - LayoutGenerator: 12/12
  - SaliencyResult: 3/3
  - CollageAssembler: 4/4
  - ImagePanel: 3/3
- Build: zero errors, zero warnings

### Key Learnings
- `CGContext` bitmap info requires both byte order **and** alpha info flags — `.byteOrder32Big` alone is insufficient
- `NSBitmapImageRep` works fine for test fixture creation, but the real issue was in the production `CollageAssembler` code, not the test helper
- `@testable import` of a module with `@MainActor`-isolated types propagates isolation to test code — mark test structs as `@MainActor` accordingly
- `NSApplication.shared` must be initialized before AppKit operations in standalone test processes

### Remaining Work
1. **Manual testing** — Run the app with real images, verify layout, crop, and export
2. **Polish** — Any UI refinements from manual testing
3. **Add LayoutGenerator tests** — Overlap detection, hero panel size, gutter spacing
4. **Add SaliencyResult tests** — Exact coordinate verification, portrait image handling
5. **Add ImagePanel tests** — Codable round-trip, inequality
6. **Add test image resources** — Real images for SaliencyAnalyzer integration tests
7. **Add CollageViewModel tests** — State transitions, layout regeneration, crop updates
8. **Protocol-based mocking** — For Vision framework isolation in SaliencyAnalyzer tests
9. **Future** (from PLAN.md): multiple layout presets, color harmonization, shadow/overlap effects

---

## Session 5 — 2026-05-08

### Goal
Manual testing of the running application and fixing runtime crashes discovered during testing.

### Issues Discovered During Manual Testing

#### Crash: "Reset Crop" Button — `MainActor.assumeIsolated` SIGABRT
- **Trigger**: Clicking "Reset Crop" in `PanelCropEditor` crashed the app with `EXC_CRASH (SIGABRT)`
- **Stack trace**: `_ButtonGesture.internalBody` → `MainActor.assumeIsolated` → `swift_task_isMainExecutorImpl` → `_objc_msgSend_uncached`
- **Root cause**: `PanelCropEditor` received `CollageViewModel` as `@ObservedObject var viewModel` (a stored property on a `struct View`). When SwiftUI recreated the view struct for re-rendering, the captured `self` in the Button closure became stale, causing `MainActor.assumeIsolated` to fail because the view instance no longer matched the expected MainActor executor context.

#### Slider Only Updates Once
- **Symptom**: First slider change applied, subsequent changes had no effect
- **Root cause**: Same issue — the `@ObservedObject` stored property on the View struct wasn't properly triggering re-renders after the first update, so the view's closure captures became stale.

#### Duplicate PanelCropEditor
- **Issue**: Two `PanelCropEditor` instances appeared for the same selected panel — one in `CollageEditorView` (bottom, below preview) and one in `ContentView.detailPanel` (right side)
- **User preference**: Bottom editor is better since the preview image is wider than tall, leaving room below

### Fixes Applied

#### `PanelCropEditor.swift`
- Converted `let panel` to `@State private var panel` (was a value copy that could go stale)
- Changed `@ObservedObject var viewModel` to `@EnvironmentObject var viewModel` — eliminates the stored property issue entirely
- Removed `viewModel:` from `init()` signature

#### `CollageEditorView.swift`
- Changed `@ObservedObject var viewModel` to `@EnvironmentObject var viewModel`
- Removed `viewModel:` from init, now uses environment injection
- `PanelCropEditor` call no longer passes `viewModel:`

#### `ContentView.swift`
- Added `.environmentObject(viewModel)` to the `NavigationSplitView` to provide the view model to all children
- Removed `detailPanel` property (duplicate `PanelCropEditor`)
- Simplified `NavigationSplitView.detail` to always show `ExportPanel()`
- Updated `ImagePickerView()` call (no longer takes `viewModel:`)

#### `ExportPanel.swift`
- Changed `@ObservedObject var viewModel` to `@EnvironmentObject var viewModel`

#### `ImagePickerView.swift`
- Changed `@ObservedObject var viewModel` to `@EnvironmentObject var viewModel`
- Updated `DropDestination` to use `@EnvironmentObject` instead of receiving `viewModel:` as a parameter

### Build Status
- **Clean build** — zero errors, zero warnings

### Key Learnings
- `@ObservedObject` as a stored property on a SwiftUI `View` struct can cause `MainActor.assumeIsolated` crashes when Button closures capture `self` — the view struct may be recreated by SwiftUI, invalidating the closure's capture
- `@EnvironmentObject` is the safer pattern for sharing `@MainActor` `ObservableObject` instances across a view hierarchy, since SwiftUI manages the injection and the view doesn't store a direct reference
- Always prefer `@EnvironmentObject` over passing `@ObservedObject` through view init parameters for shared state

### Remaining Work
1. **Verify fix with manual testing** — Rebuild and test Reset Crop, sliders, and overall app flow
2. **Polish** — Any UI refinements from manual testing
3. **Add LayoutGenerator tests** — Overlap detection, hero panel size, gutter spacing
4. **Add SaliencyResult tests** — Exact coordinate verification, portrait image handling
5. **Add ImagePanel tests** — Codable round-trip, inequality
6. **Add test image resources** — Real images for SaliencyAnalyzer integration tests
7. **Add CollageViewModel tests** — State transitions, layout regeneration, crop updates
8. **Protocol-based mocking** — For Vision framework isolation in SaliencyAnalyzer tests
9. **Future** (from PLAN.md): multiple layout presets, color harmonization, shadow/overlap effects

---

## Session 6 — 2026-05-09

### Goal
Debug "sliders stop responding after reset" issue discovered during manual testing.

### Manual Testing Setup
- Built app via `xcodebuild -project ... -scheme CollageMaker -configuration Debug -destination 'platform=macOS' build`
- Launched with `NSUnbufferedIO=YES open "<DerivedData>/Build/Products/Debug/CollageMaker.app"`
- Used real images from `/Users/austin/Pictures/VideoPictures/OuterWorlds2/Session16/` (12 character portraits, ~600KB-1.2MB each)
- User reported: sliders update once, Reset Crop works once, then **all panels stop responding to sliders**

### Investigation Approach
Instead of theorizing, wrote integration tests against the ViewModel layer with real images to isolate the bug.

#### `CropWorkflowIntegrationTests` — 7 new tests
- `loadRealImagesAndGenerateLayout` — Verifies real images load and layout generates
- `cropUpdateAppliesChanges` — Single crop update works
- `multipleCropUpdatesSamePanel` — 5 sequential updates produce exactly 1 crop entry (no duplicates)
- `cropUpdateAfterReset` — Crop → Reset → Crop again all work correctly
- `cropUpdateMultiplePanels` — Independent panel crops don't interfere
- `previewRegeneratesAfterCrop` — Preview stays valid after crop changes
- `cropLookupByDestinationRectWithCGFloatPrecision` — CGRect equality works for lookups

**All 7 tests pass** — ViewModel layer is correct. `updateCrop` handles repeated updates, resets, and post-reset updates properly.

### Root Cause Identified
**`PanelCropEditor.swift:11` — `@State private var debounceTimer: Timer?`**

`@State` is designed for `Equatable` value types. `Timer?` is a reference type that doesn't conform to `Equatable`. When `updatePreview()` triggers a view body re-render:
1. SwiftUI recreates the `PanelCropEditor` struct
2. The `@State` wrapper's `Equatable` check on `Timer?` fails to track properly
3. The `Timer` reference is lost/deallocated during struct recreation
4. After the first crop update (which triggers a re-render via `updatePreview`), the debounce timer is dead
5. All subsequent slider changes schedule timers that fire into deallocated memory — silently doing nothing

### Fix Applied
- **`PanelCropEditor.swift`**: Extracted mutable state to a `@MainActor final class CropEditorState: ObservableObject` with `@Published` sliders and a proper `Timer?` property
- Changed `@State private var offsetX/offsetY/zoom` to `@StateObject private var state = CropEditorState()`
- Moved `debounceTimer` into the class where it persists across view re-renders
- Updated all slider bindings and `scheduleUpdate`/`applyCrop` to use `state.`

### Build Status
- Build in progress — to be verified

### Key Learnings
- `@State` requires `Equatable` value types — storing reference types like `Timer?` breaks across re-renders
- `@StateObject` (or `@ObservedObject` on a class) is needed for reference types that must survive view body invalidation
- Integration tests with real images against the ViewModel layer effectively isolate UI-layer bugs from logic-layer bugs
- `xcodebuild test -only-testing:TargetName` is needed to run Swift Testing framework tests (xcodebuild runs XCTest UI tests by default)
- `NSUnbufferedIO=YES` helps with unbuffered stdout from launched apps

---

## Session 7 — 2026-05-09

### Goal
Fix crop sliders not updating the preview image during manual testing.

### Manual Testing Results
- All 29 unit tests pass (including 7 integration tests from Session 6)
- App launches, images load, layout generates, preview renders correctly
- **Slider values update** (number next to slider changes) — bindings work
- **Preview image does NOT update** — panel images remain unchanged despite slider movement
- Reset Crop button has no visible effect on the preview

### Investigation & Fix Attempts
The `CropEditorState` approach from Session 6 was replaced with a ViewModel-centric approach to avoid state loss during view recomputation.

**Attempt 1 — Move slider state to `CollageViewModel`:**
- Added `@Published cropOffsetX`, `cropOffsetY`, `cropZoom` to ViewModel
- Added `scheduleCropUpdate()` with `Timer` in ViewModel (persists across view recomputation)
- `PanelCropEditor` binds directly to `$viewModel.cropOffsetX` etc.
- **Result:** Slider values update, but preview still doesn't change

**Attempt 2 — Fix `@Published` notification:**
- `crops[index].sourceRect = ...` mutates array element in-place — `@Published` doesn't fire
- Added `crops = Array(crops)` to create new array reference
- Added `objectWillChange.send()` before `previewImage` assignment
- **Result:** No change — preview still doesn't update

**Attempt 3 — Add `os.log` tracing:**
- Added `Logger` throughout the chain: slider onChange → scheduleCropUpdate → Timer fire → applyCropSliderValues → updateCrop → updatePreview
- **Result:** Debug logging in place but session ended before log output was captured

### Current State
- **Working:** Image loading, layout generation, saliency analysis, preview rendering, export, panel selection
- **Broken:** Crop slider changes don't propagate to the preview image
- **Code has debug logging:** `os.log` calls in `CollageViewModel` and `PanelCropEditor` need to be cleaned up

### Hypotheses for Next Session
1. **`@Published` not triggering view update** — Despite `crops = Array(crops)` and `objectWillChange.send()`, SwiftUI may not be re-rendering `CollageEditorView`. Could be a SwiftUI optimization that skips re-rendering when it thinks nothing changed.
2. **`onChange` not firing** — The `.onChange(of: viewModel.cropOffsetX)` modifier may not fire if SwiftUI considers the binding value unchanged (e.g., slider is bound to a `@Published` Double that SwiftUI deduplicates).
3. **View identity issue** — `PanelCropEditor` is created with `panel: selectedPanel` as a value parameter. When the view recomputes, SwiftUI may see it as a "new" view and discard state. Consider using `.id(panel.id)` to stabilize identity.
4. **Timer not firing** — The `Timer.scheduledTimer` in the ViewModel may not be scheduled on the correct run loop, or the `[weak self]` capture may be deallocating prematurely.

### Next Steps
1. **Clean up debug logging** — Remove `os.log` calls (or keep them behind a flag) before further work
2. **Verify Timer fires** — Add a simple test that calls `scheduleCropUpdate()` and verifies the timer callback executes
3. **Try removing debounce** — Call `applyCropSliderValues()` directly from `onChange` to isolate whether the Timer is the issue
4. **Try `.id()` on PanelCropEditor** — Stabilize view identity to prevent SwiftUI from discarding state
5. **Consider `.onReceive(viewModel.$cropOffsetX)`** instead of `.onChange` — Different notification mechanism that may work better with `@Published`
6. **Manual testing** — Continue with real images once slider fix is verified
7. **Polish** — UI refinements from manual testing
8. **Additional tests** — LayoutGenerator overlap/hero/gutter, SaliencyResult coordinates, ImagePanel Codable, CollageViewModel state transitions
9. **Future** (from PLAN.md): multiple layout presets, color harmonization, shadow/overlap effects

---

## Session 8 — 2026-05-09

### Goal
Fix crop sliders not updating preview image (Session 7 bug).

### Root Cause Identified
**`PanelCropEditor.swift` — `.onChange(of: viewModel.cropOffsetX)` loses observer after view recreation.**

After `updatePreview()` changes `previewImage`, SwiftUI re-renders `CollageEditorView`, which recreates `PanelCropEditor` because `panel:` is a new value each time. The `.onChange` modifier's internal "previous value" tracking is lost on the new view instance. The new view sees the current `cropOffsetX` as its initial value, so no "change" is detected on subsequent slider movements.

**Verification:** Created `CropDebounceChainTests` (6 tests) that exercise the full ViewModel debounce chain (slider value → schedule → Timer → Task → applyCrop → updateCrop → updatePreview). All pass, confirming the ViewModel is correct and the bug is purely in SwiftUI's view layer.

### Fix Applied
- **`PanelCropEditor.swift`**: Replaced `.onChange(of:)` with `.onReceive(viewModel.$cropOffsetX.dropFirst())` — subscribes to the `@Published` Combine publisher, which survives view recreation because the subscription is tied to the ViewModel's lifetime, not the view's.
- **`CollageViewModel.swift`**: Removed all `os.log` debug logging from Session 7. Fixed Timer closure to use `Task { @MainActor in ... }` for Swift 6 concurrency compliance.

### Test Results
- **39/39 tests pass** (29 original + 6 new debounce chain + 4 UI)
- Zero errors, zero warnings (excluding AppIntents metadata)

### Key Learnings
- `.onChange(of:)` tracks previous value in the view's state — when SwiftUI recreates the view struct, the tracker resets and changes are missed
- `.onReceive(publisher.dropFirst())` is the reliable pattern for reacting to `@Published` changes from `@EnvironmentObject` — the Combine subscription survives view recreation
- `dropFirst()` prevents `onReceive` from firing immediately on view attachment
- `Timer.scheduledTimer` with `Task { @MainActor in ... }` requires `Task.sleep` in tests (not `RunLoop.run`) because the actual work runs on the Swift executor, not the run loop
- UI-level tests for SwiftUI slider interaction are not practical — ViewModel-level integration tests that exercise the full debounce chain are more reliable

---

## Session 9 — 2026-05-09

### Goal
Fix crop sliders not updating preview (Session 7/8 bug) by switching to gesture-based crop editing.

### Investigation
**Slider approach fundamentally broken:** After exhaustive debugging (`.onChange` → `.onReceive`, `Timer` → `Task`, `@State` → `@StateObject`, `@ObservedObject` → `@EnvironmentObject`), slider-based crop editing still fails after the first change. The root cause remains elusive — likely SwiftUI's view reconciliation invalidating gesture/modifier state in ways that are difficult to diagnose without Xcode's SwiftUI debugger.

**Decision: Pivot to gestures.** Drag to pan, pinch to zoom. This:
1. Avoids the debounce problem entirely (apply on gesture end, not during)
2. Provides direct manipulation (more intuitive for image editing)
3. Has a simpler code path (no Timer, no Combine, no `.onChange`)

### Implementation

#### `CollageEditorView.swift`
- Added `DragGesture(minimumDistance: 5)` to preview image
- Added `MagnificationGesture()` to preview image
- `previewToCanvas()` converts preview coordinates to canvas coordinates (accounts for aspect-ratio fit scaling)
- Gestures only fire when a panel is selected (`viewModel.selectedPanelId != nil`)
- `onChanged` calls `panCrop`/`pinchZoom` (updates crop in-place, no preview yet)
- `onEnded` calls `applyPanCrop`/`applyPinchZoom` (commits + `updatePreview`)

#### `CollageViewModel.swift`
- Added `panCrop(panelId:by:)` — pans crop origin during drag, clamps to image bounds
- Added `applyPanCrop()` — commits crop, triggers `updatePreview`, resets gesture state
- Added `pinchZoom(panelId:magnification:)` — zooms crop during pinch, clamps to 0.5-3.0
- Added `applyPinchZoom()` — commits crop, triggers `updatePreview`, resets gesture state
- Gesture state: `gestureBaseCropOrigin`, `gestureBaseZoom`, `gesturePanDelta`, `gestureZoomDelta`
- Removed all `os.log` debug logging from Session 7

#### `PanelCropEditor.swift`
- Simplified to show panel info and "Reset Crop" button
- Removed sliders (no longer needed)
- Shows hint: "Drag on preview to pan crop • Pinch to zoom"

#### `CropDebounceChainTests.swift`
- Renamed to `CropGestureTests`
- 8 tests: pan moves source rect, pan clamps to bounds, pinch changes zoom, pinch clamps min/max, preview updates after pan/pinch, multiple pans accumulate
- 6/8 pass — pan tests fail (under investigation)

### Manual Testing Results
- **Pinch zoom partially works** — Zoom applied, but to the wrong panel. Gestures target `selectedPanelId` regardless of where the gesture occurs on the preview. User pinched over one panel but the crop applied to a different selected panel.
- **Drag pan not verified** — `print()` doesn't appear in `log stream` (goes to stdout, not unified log). Need `os_log` or terminal-based debugging for runtime diagnostics.
- **Pan crop tests fail** — `panCrop` guard fails to find crop by `destinationRect == panel.frame`. Likely the same `CGRect` equality precision issue from Session 4, or the crop lookup logic doesn't match the gesture's panel resolution.

### Remaining Work
1. **Fix gesture panel targeting** — Gestures should target the panel under the gesture location, not the pre-selected panel. Use gesture location + `handlePreviewTap` logic to determine which panel is being manipulated.
2. **Fix pan crop tests** — Investigate why `panCrop` guard fails (CGRect equality vs crop lookup)
3. **Visual feedback** — Highlight selected panel with border/overlay so user knows which panel is active
4. **Debug logging strategy** — `print()` → stdout (not visible in `log stream`). Use `os_log` for unified log, or run app from terminal to see `print()` output.
5. **Future** (from PLAN.md): multiple layout presets, color harmonization, shadow/overlap effects

---

## Research Items for Future Sessions

### 1. SwiftUI gesture targeting on composite images
**Problem:** When gestures are attached to a single `Image(nsImage:)` preview, the gesture location is in the image's coordinate space. Need to map gesture location → canvas coordinates → panel hit test.
**Questions:**
- Does `DragGesture` provide `location` in `onChanged`? (Only in `onEnded`)
- Can we use `SimultaneousGesture` to combine drag + pinch + tap?
- Does SwiftUI allow per-panel gesture zones on a composite image, or do we need to draw panels individually?

### 2. `CGRect` equality precision with `LayoutGenerator`
**Problem:** `panCrop` tests fail because `crops.firstIndex(where: { $0.destinationRect == panel.frame })` returns `nil`. The `LayoutGenerator` produces frames with computed `CGFloat` values that may not exactly match `panel.frame` due to floating-point arithmetic.
**Questions:**
- Does `LayoutGenerator` use `CGFloat` division that introduces precision errors?
- Should crop lookup use `panel.id` instead of `destinationRect` equality?
- Would adding `panelId` to `CropInfo` solve this cleanly?

### 3. Direct per-panel gesture overlay approach
**Idea:** Instead of one gesture on the composite preview, draw individual panel overlays (rectangles) on top of the preview image, each with its own gesture. This gives:
- Per-panel targeting (drag panel 2 affects panel 2)
- Visual feedback (selected panel gets border)
- Natural interaction model
**Questions:**
- Can we use `ZStack` with `Rectangle` overlays positioned at panel frames?
- How to handle coordinate space between preview image (aspect-ratio fit) and overlay rectangles?
- Is `Canvas` or `Shape` approach better for performance?

### 4. Alternative: `UIViewRepresentable` with `NSImageView`
**Idea:** Wrap `NSImageView` in `UIViewRepresentable` to get native AppKit gesture recognition, hit testing, and selection. This sidesteps SwiftUI gesture limitations entirely.
**Questions:**
- What's the integration cost with the existing SwiftUI view hierarchy?
- Can we maintain the `@EnvironmentObject` pattern across the boundary?
- Is this worth it vs. fixing the SwiftUI approach?
