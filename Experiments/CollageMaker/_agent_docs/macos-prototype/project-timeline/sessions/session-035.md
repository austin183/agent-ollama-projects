# Session 35 — 2026-05-21

### Phase 3 Test Verification: `buildMoveMapping` Fatal Error and Test Suite Race Condition

**Goal:** Pick up from session 34 — verify the `buildMoveMapping` fix, confirm Phase 3 tests pass, and investigate test suite race condition.

**Source:** `_agent_docs/project-timeline/sessions/session-034.md` (continuation)

**Issues Fixed:**

#### `buildMoveMapping` Fatal Range Error

The `moveImagesSingleElement` test exposed a fatal runtime crash. When `to == fromFirst` (e.g., single element, moving index 0 to position 0), the `else` branch's closed range `(fromFirst + 1)...to` evaluated to `1...0` — a fatal `Range requires lowerBound <= upperBound` error.

**Fix:** Added `guard to != fromFirst else { return oldPos }` at the top of `buildMoveMapping` to short-circuit the no-op case.

**File:** `ViewModel/CollageViewModel.swift:388`

#### Test Suite Race Condition: `NSGraphicsContext.current` Contention

When running the full test suite, 25+ tests showed 0.000s cascade failures. Root cause was `createTestCGImage` in `TestHelpers.swift` modifying global `NSGraphicsContext.current`. Swift Testing's cross-process parallelization caused concurrent graphics context modifications.

**Fix:** Added `@Suite(.serialized)` to 5 test suites that use test image creation helpers:
- `CollageViewModelTests`
- `ExportFlowTests`
- `CollageAssemblerTests`
- `SaliencyAnalyzerTests`
- `CropManagerTests`

**Impact:**
- Before: ~25+ cascade failures at 0.000s across all suites
- After: ALL PASS — zero failures

**Files Modified:**
- `ViewModel/CollageViewModel.swift` — `buildMoveMapping` guard clause
- `CollageMakerTests/CollageViewModelTests.swift` — `@Suite(.serialized)`
- `CollageMakerTests/ExportFlowTests.swift` — `@Suite(.serialized)`
- `CollageMakerTests/CollageAssemblerTests.swift` — `@Suite(.serialized)`
- `CollageMakerTests/SaliencyAnalyzerTests.swift` — `@Suite(.serialized)`
- `CollageMakerTests/CropManagerTests.swift` — `@Suite(.serialized)`

**Build and Test Status:**
- **Build:** SUCCEEDED — zero errors, zero warnings
- **Full unit test suite (CollageMakerTests):** ALL PASS — zero failures
- **4 move edge case tests:** ALL PASS consistently

**Session Status:** Complete — Phase 3 test verification done. All unit tests passing.
