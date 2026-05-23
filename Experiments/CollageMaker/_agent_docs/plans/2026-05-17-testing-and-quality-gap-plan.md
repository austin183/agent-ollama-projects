# CollageMaker Testing & Quality Gap Plan

**Date:** 2026-05-17
**Source:** `_agent_docs/reviews/collagemaker-solid-review.md`
**Scope:** Improving test coverage and addressing code quality nits identified in the SOLID review.

---

## Overview
This plan addresses the "Gaps" and "Nits" identified in the architecture review that were not covered in the primary SOLID implementation round. The focus is on making complex view logic testable by consolidating gesture handling into the existing `CropManager` and cleaning up redundant code/logging.

## Gap Matrix

| Area | Finding | Severity | Strategy |
|------|---------|----------|-----------|
| **Testing** | No tests for `CollageEditorView` gestures | High | Consolidate into `CropManager` → Unit Test |
| **Testing** | No tests for `PanelCropEditor` | Medium | Fix `displayImage` perf; extract coordinate math |
| **Testing** | No tests for `ContentView`, `ExportPanel` | Low | ViewModel integration tests |
| **Testing** | No test infrastructure safeguards | Medium | Add `@MainActor`, `NSBitmapImageRep` fixtures, `AppKitInit` |
| **Quality** | Complex 270-line `CollageEditorView.body` | Medium | Extract gesture handlers to `CropManager` |
| **Quality** | Redundant logging interpolation / missing logs | Low | Cleanup in `CollageAssembler` |
| **Quality** | Private logging helpers in View files | Low | Move to shared `LoggingExtensions` |
| **Quality** | `PanelCropEditor.displayImage` reallocates every render | Medium | Cache or move to ViewModel |

---

## Phase 0 — Test Infrastructure
**Addresses:** Testing Gap (Infrastructure safeguards)

### 0.1 Ensure `@MainActor` on Test Structs
- All test structs exercising `@testable import CollageMaker` types must be annotated `@MainActor` to avoid Swift 6 concurrency warnings.

### 0.2 CGImage Test Fixtures
- Any new test creating `CGImage` fixtures must use `NSBitmapImageRep` with RGBA (`samplesPerPixel: 4`, `hasAlpha: true`) instead of `CGContext.makeImage()`, which returns `nil` in headless test environments.
- Always `saveGraphicsState()` / `restoreGraphicsState()` around test context creation.

### 0.3 AppKit Initialization
- Ensure `AppKitInit` suite (`_ = NSApplication.shared`) is declared and new tests depending on AppKit types use `@Test(.dependencies(AppKitInit.self))`.

### 0.4 xcodebuild Test Targeting
- New tests must be runnable via `xcodebuild test ... -only-testing:CollageMakerTests` (Swift Testing is skipped without this flag).

---

## Phase 1 — Testability Refactor (Gesture Consolidation)
**Addresses:** Testing Gap (EditorView), Quality Issue (Complex body)

### 1.1 Extend `CropManager` with Gesture Handling
- **Modified file:** `ViewModel/CropManager.swift`
- Consolidate gesture state and coordinate math from `CollageEditorView.body` into `CropManager` rather than creating a new coordinator. `CropManager` already owns `cropMap`, `beginPan`/`pan`/`applyPan`, and pinch state — gesture hit-testing and coordinate translation are a natural extension.
- Logic to add:
    - `hitTestPanel(at: CGPoint, in previewSize: CGSize, panels: [Panel]) -> UUID?` — screen-to-canvas coordinate mapping and panel hit testing.
    - `translateZoom(magnification: CGFloat, for panelId: UUID)` — zoom scaling with division semantics (`baseZoom / magnification`).
    - Any remaining clamping and boundary-check helpers currently duplicated in the view.

### 1.2 Simplify `CollageEditorView`
- **Modified file:** `Views/CollageEditorView.swift`
- Replace inline closure logic in `.simultaneousGesture` and `.onTapGesture` with calls to `CropManager` methods.
- Retain view-local `@State` flags (`dragPanelId`, `pinchPanelId`) for gesture locking, as these are SwiftUI lifecycle concerns, not business logic.
- Result: Reduce `body` property length significantly (from 270 lines).

---

## Phase 2 — Logic Testing
**Addresses:** Testing Gaps (EditorView, PanelCropEditor, ContentView/ExportPanel)

### 2.1 Test Gesture and Coordinate Logic
- **New file:** `CollageMakerTests/CropManagerTests.swift` (extend existing file)
- Write unit tests for:
    - Panel hit testing with `hitTestPanel(at:in:panels:)`.
    - Coordinate translation (Screen → Canvas).
    - Zoom scaling calculations (division, not multiplication).
    - Panning delta accumulation and clamping.
- Follow the skill pattern: test the `CropManager` methods directly, not UI-level gestures.

### 2.2 Fix and Test `PanelCropEditor`
- **Modified file:** `Views/PanelCropEditor.swift`
- Fix `CropPreviewView.displayImage` computed property — currently allocates a new `NSImage` on every render. Cache the result or move computation to the ViewModel.
- Extract `sourceRectInContainer` coordinate math into `CropManager` to eliminate duplication with `CollageEditorView.canvasToPreviewFrame`.
- **New file:** `CollageMakerTests/PanelCropEditorTests.swift` — tests for extracted coordinate math.

### 2.3 ViewModel Integration Tests
- **New file:** `CollageMakerTests/ExportFlowTests.swift`
- Implement ViewModel-level interaction tests for export flow (e.g., verifying that calling `CollageViewModel.export()` triggers the assembler with correct parameters). Do NOT use SwiftUI snapshot tests — test ViewModel behavior directly with real or mocked data.

---

## Phase 3 — Quality & Logging Polish
**Addresses:** All identified Nits

### 3.1 Create `LoggingExtensions`
- **New file:** `Services/LoggingExtensions.swift`
- Move `rectStr`, `pointStr`, and `sizeStr` from `CollageEditorView.swift` into this utility file as `internal` helpers. Do NOT mark `public` — these are debug-only utilities with no external consumer.

### 3.2 Clean up `CollageAssembler`
- **Modified file:** `Services/CollageAssembler.swift`
- Fix redundant interpolation at line 179: `"\("\(Int(canvasSize.width))x\(Int(canvasSize.height))", privacy: .public)"` → `"\(Int(canvasSize.width))x\(Int(canvasSize.height))"`. The nested `privacy: .public` has no effect embedded inside a format string.
- Add `logger.error` in `assembleWithCGImages` when `createBitmapContext` returns `nil` (currently silent). Same for `assemblePreviewWithCGImages` and the `bitmapRep.cgImage` guard.

---

## Verification
1. **Coverage Increase:** Verify that the new `CropManager` and export flow tests increase the test count from the current 62.
2. **Code Reduction:** Confirm `CollageEditorView.body` is under 150 lines and no longer contains coordinate math.
3. **Log Accuracy:** Verify via Console.app that `CollageAssembler` now logs failures during context creation.
4. **Regression:** All existing 62 tests pass.
5. **Build:** Zero errors, zero warnings. Run `xcodebuild test -only-testing:CollageMakerTests` to confirm Swift Testing integration.

---

## Files Summary

### New files
- `Services/LoggingExtensions.swift` — Shared internal debug logging utilities.
- `CollageMakerTests/PanelCropEditorTests.swift` — Tests for extracted coordinate math.
- `CollageMakerTests/ExportFlowTests.swift` — ViewModel integration tests for export flow.

### Modified files
- `ViewModel/CropManager.swift` — Extended with hit-testing, coordinate translation, and zoom scaling methods.
- `Views/CollageEditorView.swift` — Reduced body size, delegates gesture math to `CropManager`, uses `LoggingExtensions`.
- `Views/PanelCropEditor.swift` — Fixed `displayImage` performance, extracted `sourceRectInContainer` to `CropManager`.
- `Services/CollageAssembler.swift` — Fixed logging nits, added error logging on context creation failure.
- `CollageMakerTests/CropManagerTests.swift` — Extended with gesture and coordinate tests.
