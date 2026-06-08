# Post-Round 99 Review Fixes Plan

**Date:** 2026-06-08
**Source Reviews:**
- `_agent_docs/reviews/2026-06-07-post-round-99-charlie.md`
- `_agent_docs/reviews/2026-06-07-post-round-99-harold.md`

## Overview

Both reviews identified overlapping issues. All findings were validated against source code. This plan organizes the confirmed fixes into phases by effort size.

**Excluded:** Portrait coordinate swap (COORD-01) — user confirmed no observed issue.
**Deferred:** ViewModel decomposition (SRP-01) — separate session, multiple phases.

---

## Phase A: Quick Wins (1–2 line fixes)

### A1: Actor Serialization Bottleneck (CONC-01)
- **File:** `Services/SaliencyAnalyzer.swift`
- **Problem:** `analyze(_:)` is an actor method. `withThrowingTaskGroup` launches concurrent tasks, but each must hop through the actor executor, serializing all analysis. No parallelism.
- **Fix:** Mark `analyze(_:)` as `nonisolated`. It accesses no actor-isolated state — pure function with local variables and Vision APIs only. Update `SaliencyAnalysis` protocol to match.
- **Lines:** `SaliencyAnalyzer.swift:27`, protocol at line 22

### A2: PanelShape Y-Axis Flip — Diagonal Slices Outline Misalignment (COORD-02)
- **File:** `Views/CollageEditorView.swift`
- **Problem:** `PanelShape.path(in:)` transforms CGPath from canvas coordinates (CoreGraphics, origin=bottom-left) to SwiftUI coordinates (origin=top-left) without a Y-axis flip. The parallelogram is drawn upside down — shear leans the wrong direction. Only affects selection outline; actual panel content renders correctly via CGContext.
- **Fix:** Apply Y-axis flip in the CGAffineTransform at lines 350-354:
  ```swift
  // Before:
  var t = CGAffineTransform(translationX: -boundingRect.origin.x * scaleX, y: -boundingRect.origin.y * scaleY)
  t = t.scaledBy(x: scaleX, y: scaleY)

  // After:
  var t = CGAffineTransform(translationX: -boundingRect.origin.x * scaleX, y: boundingRect.origin.y * scaleY + rect.height)
  t = t.scaledBy(x: scaleX, y: -scaleY)
  ```
- **Lines:** `CollageEditorView.swift:350-354`

### A3: Duplicate Property Declaration (ExportManager)
- **File:** `ViewModel/ExportManager.swift`
- **Problem:** Line 24 has a duplicate `private let assembler: any CollageAssembly` declaration.
- **Fix:** Delete the duplicate line.
- **Lines:** `ExportManager.swift:24`

---

## Phase B: Medium Fixes (multi-file, new behavior)

### B1: Batch Error Handling — All-or-Nothing Failure (ERR-01)
- **File:** `Services/SaliencyAnalyzer.swift`
- **Problem:** `withThrowingTaskGroup` propagates the first error and cancels all tasks. One corrupt image fails the entire collage analysis, returning zero results.
- **Fix:** Replace `withThrowingTaskGroup` with `withTaskGroup` that collects `[Int: Result<SaliencyResult, Error>]`. Log per-image failures. Return partial results so the collage still renders with best-fit crops (center-based fallback) for failed images.
- **Lines:** `SaliencyAnalyzer.swift:100-116`

### B2: Double Exposure Overlay Invisible in Layered Mode
- **Files:** `Views/CollageEditorView.swift`, `Services/PreviewManager.swift`, `ViewModel/CollageViewModel.swift`
- **Problem:** The overlay is correctly rendered into `previewImage`, but `CollageEditorView` only displays `previewImage` when `isLayeredMode == false`. In layered mode (normal state after loading images), it composites background + panels + title from separate layers — there is no overlay layer in the ZStack.
- **Root cause:** `CollageEditorView.swift:34-71` — the `isLayeredMode` branch has no overlay image.
- **Fix:**
  1. Add `overlayImage: NSImage?` property to `PreviewManager`
  2. Add `overlayImage` computed property to `CollageViewModel` that proxies to `previewManager.overlayImage`
  3. In `PreviewManager.updatePreview()`, when `config.overlay != nil`, render the overlay separately into `overlayImage`
  4. Add overlay `Image` to the layered `ZStack` in `CollageEditorView` between panels and title
- **Lines:** `CollageEditorView.swift:34-71`, `PreviewManager.swift`, `CollageViewModel.swift`

### B3: Debouncer Utility (SRP-02)
- **Files:** New `ViewModel/Debouncer.swift`, `ViewModel/CollageViewModel.swift`
- **Problem:** 8 debounce task variables (`saveDebounceTask`, `previewDebounceTask`, `previewRenderDebounceTask`, `panelPreviewTask`, `titleDebounceTask`, `fontSizeDebounceTask`, `gutterDebounceTask`, `backgroundColorDebounceTask`) with identical cancel-sleep-execute patterns. ~70 lines of boilerplate.
- **Fix:** Create generic `Debouncer` utility:
  ```swift
  actor Debouncer {
      func debounce(id: String, delay: Duration, work: @escaping @MainActor () -> Void)
  }
  ```
  Replace all 8 task variables with single `Debouncer` instance. Eliminate ~70 lines.
- **Lines:** `CollageViewModel.swift:30, 879-885`

---

## Phase C: Architectural Improvements (protocol work, refactoring)

### C1: LayoutOptions for Strategy-Specific Parameters (OCP-01)
- **Files:** `Services/LayoutGenerator.swift`, `Models/LayoutStyle.swift`
- **Problem:** `makeStrategy(sliceAngle:hexSpacing:)` leaks strategy-specific parameters. Adding a new layout with new params forces a signature change to `makeStrategy`.
- **Fix:** Introduce `struct LayoutOptions` with optional properties (`sliceAngle`, `hexSpacing`). Pass to both `makeStrategy(options:)` and `LayoutGenerator.generate(..., options:)`. New layouts read only what they need.
- **Lines:** `LayoutGenerator.swift:9, 197`

### C2: ExportManager DIP — Inject Save Panel and Folder Memory (DIP-01)
- **File:** `ViewModel/ExportManager.swift`
- **Problem:** Direct `UserDefaults.standard` access (lines 48, 59) and `NSSavePanel` instantiation (line 44) make this class hard to test and violate DIP.
- **Fix:** Create `SavePanelPresenter` protocol (`func present(defaultFolder: URL?) async -> URL?`). Inject presenter + default folder into `ExportManager`. Tests provide mock presenter.
- **Lines:** `ExportManager.swift:44, 48, 59`

### C3: UserDefaultsPersistence Behind Protocol (DIP-02)
- **Files:** `Services/UserDefaultsPersistence.swift`, `ViewModel/CollageViewModel.swift`
- **Problem:** `CollageViewModel` depends on concrete `UserDefaultsPersistence` class (line 23), unlike `SaliencyAnalysis` and `CollageAssembly` which use protocols.
- **Fix:** Create `ViewModelPersistence` protocol with `save(_:)` and `load()`. Update `CollageViewModel` to depend on the protocol.
- **Lines:** `CollageViewModel.swift:23`, `UserDefaultsPersistence.swift:31`

### C4: AssemblyConfig Factory Init Promotion (ISP-01)
- **File:** `Models/AssemblyConfig.swift`
- **Problem:** 14-parameter primary initializer (line 78). Callers must construct full config even when only a subset changed. Factory init using sub-structs (line 120) is cleaner but not the primary API.
- **Fix:** Promote the factory init to primary API. Mark 14-param init as `@available(*, deprecated, renamed: "init(layout:title:background:canvasSize:overlay:)")`. Update callers in `CollageViewModel` to use factory init.
- **Lines:** `AssemblyConfig.swift:78, 120`

---

## Phase D: Tests

### D1: CropInfo Codable Round-Trip
- **File:** New `CollageMakerTests/CropInfoCodableTests.swift`
- **Gap:** `CropInfo` conforms to `Codable` with custom encode/decode, but zero tests verify round-trip correctness. Decoder reconstructs `CGPath(rect:transform:)` from bounding rect, losing original path shape.
- **Test:** Encode a `CropInfo` with `.rect` and `.path` geometry, decode, verify bounding rect is preserved. Document that `.path` shape is lost (expected behavior).

### D2: PanelShape Y-Flip Verification
- **File:** New test or addition to existing test suite
- **Gap:** No test for `PanelShape` rendering with rotated/sheared geometry.
- **Test:** Verify that `PanelShape.path(in:)` produces a path with correct corner ordering for a sheared parallelogram (top edge shifted right, not left).

---

## Execution Order

1. **Phase A** — Quick wins, low risk, immediate impact
2. **Phase B** — Medium fixes, require testing
3. **Phase C** — Architectural improvements, can be done incrementally
4. **Phase D** — Tests, validate Phase A/B fixes

## Deferred (Not in This Plan)

- **COORD-01:** Portrait coordinate swap in `SaliencyResult.cropOrigin` — user confirmed no observed issue
- **SRP-01:** `CollageViewModel` god class decomposition — separate session, extract `TitleManager` and `LayoutManager`
