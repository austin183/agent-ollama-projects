# Swift Equatable & macOS UI — Debrief 2026-05-12

**Purpose:** Batch 3 implementation — preview debounce, cached hit areas, popover image picker

## What Worked

- **`DispatchWorkItem` debounce pattern** — Clean approach for deferring expensive preview renders during gesture callbacks. Crop math runs live (for correct gesture state), but `updatePreview()` is deferred 0.15s. Stale work is cancelled via `previewDebounce?.cancel()`.

- **`[UUID: CGRect]` cache for hit areas** — Avoids calling `canvasToPreviewFrame` per panel on every hit test. Dictionary lookup is O(1). Invalidates on layout key change (size, panel IDs, crop keys).

- **Popover picker threshold at 10 images** — Keeps inline picker for small sets (familiar, low friction), switches to grid popover for larger sets (discoverable, searchable).

## What Didn't Work / Gaps

- **Swift tuple Equatable inference failure** — `.onChange(of:)` requires its key to be `Equatable`. Attempted multiple approaches:
  - `(geometry.size, viewModel.panels.map { $0.id }, viewModel.cropMap.keys)` — failed: `CGSize` and `Dictionary.Keys` can't conform to Equatable
  - `(Double(w), Double(h), [UUID], Array<UUID>)` — failed: 4-element tuple with mixed array types still fails
  - **Solution:** Dedicated `private struct LayoutKey: Equatable` with explicit `let` properties. Swift synthesizes Equatable correctly for structs but hits limits with heterogeneous tuples.

- **`.rounded` TextFieldStyle is iOS-only** — macOS SwiftUI has no `.rounded` text field style. Used plain `.padding()` instead.

- **Stale test from Session 6 direction fix** — `CropManagerTests.panCropMovesSourceRect` had an expectation (`afterPan.x > afterZoom.x`) that assumed the old (buggy) pan direction where delta was added. Session 6 flipped to subtraction (`baseOrigin - panDelta`), making the test fail. Fixed by inverting the expectation. This is a reminder: behavioral fixes to gesture math can silently invalidate test assumptions.

## What Was Confusing

- **`PBXFileSystemSynchronizedRootGroup` auto-discovers files** — The project uses synchronized root groups, so new `.swift` files are picked up automatically without editing `project.pbxproj`. This is different from traditional `PBXGroup` projects where files must be added manually.

- **Test count drift** — The timeline claimed "64 tests pass" through Session 8, but the actual count grew to 67 (3 new tests added in earlier sessions: `assemblePreviewSize`, `assembleWithGradientBackground`, `setLayoutStyleUpdatesStyle`). Running the full test suite after each session would catch this drift and pre-existing failures.

## Skill Improvements

- **SwiftUI Patterns skill** — Could document the "dedicated struct for `.onChange(of:)` multi-component keys" pattern as a best practice
- **macOS SwiftUI Patterns** — `.rounded` TextFieldStyle is iOS-only; document macOS alternatives

## Next Steps

- Batch 4 (gesture redesign with two-finger scroll pan) is the remaining planned batch
- Run full test suite after each session to catch test count drift and stale expectations

---
**Status**: Closed
**Follow-up**: Batch 4 — ScrollPanView implementation
