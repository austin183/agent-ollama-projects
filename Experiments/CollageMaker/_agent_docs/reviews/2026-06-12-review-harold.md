# CollageMaker — Architectural Code Review
**Date:** 2026-06-12
**Reviewer:** Harold
**Scope:** Full codebase — Models, Services, ViewModel, Views, Tests

---

## Executive Summary

CollageMaker is a well-architected macOS SwiftUI app with strong separation of concerns across its four-layer architecture (Models → Services → ViewModel → Views). The protocol abstraction strategy (`SaliencyAnalysis`, `CollageAssembly`, `LayoutStrategy`, `ViewModelPersistence`) enables thorough test mocking. Concurrency patterns — actors for Vision, `Task.detached` for rendering, `@MainActor` for state — are mostly correct.

The project has three classes of issues:

1. **Critical correctness bugs** — `CropInfo` Codable loses path data, `TitleStyle` Equatable compares NSColor by reference, and unsynchronized saliency tasks can race.
2. **God classes** — `CollageViewModel` (1,092 lines), `CollageAssembler` (497 lines), `PanelCropEditor` (674 lines), and `ContentView.sidebar` (260 lines) exceed reasonable size and mix multiple responsibilities.
3. **Observation gaps** — Computed properties on `CollageViewModel` (`images`, `customImageOrder`, `cropMap`) break `@Observable` tracking for views that don't read the delegated managers directly.

The test suite (21 files) is well-structured with good mocking patterns (`TestAssembler`), but relies on `Task.sleep` for async synchronization and has zero coverage for `Debouncer`, `DropHandler`, and `NSColor+Hex`.

**Overall Assessment:** Solid foundation with 5 critical bugs, 10 structural concerns, and 15 improvements. The architecture is sound but individual files need decomposition and a few correctness fixes.

---

## Critical Issues (Must Fix)

### C1: `CropInfo` Codable Loses Arbitrary Path Data
**File:** `Models/ImagePanel.swift:66-77`
**Severity:** High — Data corruption on load

`CropInfo.encode(to:)` only serializes `destination.boundingRect`, discarding the `PanelGeometry` enum case. On decode, `init(from:)` reconstructs `.rect(boundingRect)`, so hexagonal or diagonal-slice panels deserialize as rectangles. Any saved collage with non-rectangular layouts will lose its panel shapes.

**Fix:** Encode the `PanelGeometry` enum (e.g., serialize as `geometry.kind` + `geometry.boundingRect`, or the full `CGPath` data for path-based geometries).

---

### C2: `TitleStyle` Equatable Compares NSColor by Reference
**File:** `Models/TitleStyle.swift:4`
**Severity:** Medium — Spurious UI updates, test failures

Auto-synthesized `Equatable` compares `fontColor` and `backgroundColor` using `NSColor`'s `Equatable` conformance, which compares by pointer identity, not color value. Two `TitleStyle` instances with the same visual color but different `NSColor` instances will be unequal. This causes spurious cache invalidations and failed test assertions.

**Fix:** Implement custom `==` that compares colors via `rgbaHex` or component values.

---

### C3: Unsynchronized Saliency Tasks Can Race
**File:** `ViewModel/CollageViewModel.swift:460-495`
**Severity:** Medium — Stale results on rapid operations

`addImages()`, `removeImage()`, and `moveImages()` each fire a `Task { await self?.analyzeSaliency() }`. If the user rapidly adds, removes, and reorders images, multiple `analyzeSaliency()` calls run concurrently. Each overwrites `saliencyResults` on completion, potentially with stale data from an earlier image set.

**Fix:** Add a `saliencyGeneration: Int` counter. Increment before each call, capture in the Task, and guard `gen == self.saliencyGeneration` before applying results.

---

### C4: `CropManager` Is Not `@Observable`
**File:** `ViewModel/CropManager.swift:7`
**Severity:** Medium — Silent observation failures

`CropManager` is `@MainActor final class` but lacks `@Observable`. Mutations to `cropMap` don't emit observation events. The ViewModel works around this with `cropMapVersion`, but any code reading `cropManager.cropMap` directly will not receive updates.

**Fix:** Add `@Observable` to `CropManager`.

---

### C5: `LayoutStyle` Imports SwiftUI
**File:** `Models/LayoutStyle.swift:2`
**Severity:** Low — Unnecessary dependency

`import SwiftUI` is unused. The Models layer should not depend on SwiftUI. Increases compile time and coupling.

**Fix:** Remove the import.

---

### C6: `PreviewManager.awaitPendingTasks()` Uses Hardcoded Sleep
**File:** `Services/PreviewManager.swift:237`
**Severity:** Medium — Fragile test synchronization

`Task.sleep(nanoseconds: 300_000_000)` is a test synchronization anti-pattern. Too short on slow CI, too long locally, and hides real race conditions.

**Fix:** Replace with a `CheckedContinuation` or `AsyncStream` that signals when all tasks complete.

---

### C7: `SaliencyResult` Missing Equatable
**File:** `Models/SaliencyResult.swift:4`
**Severity:** Low — Test friction

Stored in `[Int: SaliencyResult]` dictionaries but cannot be compared in tests.

**Fix:** Add `Equatable` conformance.

---

### C8: `FontMerger` Uses NSFont Without @MainActor
**File:** `Services/FontMerger.swift`
**Severity:** Medium — Potential data race

`NSFont` is MainActor-only. The struct has no `@MainActor` annotation and could be called from a background thread.

**Fix:** Add `@MainActor` to the struct.

---

## Structural Concerns (Should Address)

### S1: `CollageViewModel` Is a God Class (1,092 lines)
**File:** `ViewModel/CollageViewModel.swift`

Orchestrates image library, crop state, layout, preview, export, title (10+ setters), background (7+ properties), double exposure, diagonal slice, hexagonal layout, saliency, undo, persistence, and debouncing. Two subsystems should be extracted:

- **`TitleManager`** — 10+ `setTitle*` methods + `applyTitleChange` + `titleViewUpdate` + `finishTitleDrag` + `updateTitleImage` + `updateTitleImageLive` (~90 lines)
- **`BackgroundManager`** — 7 background properties + `updateBackground()` + `setBackgroundImage`/`setMaskImage` setters (~70 lines)

Both follow the existing `CropManager` / `ExportManager` / `ImageLibraryManager` extraction pattern.

---

### S2: `@Observable` Computed Properties Break Tracking
**File:** `ViewModel/CollageViewModel.swift:90-111`

Three computed properties delegate to sub-managers:
- `var images: [ImageItem] { imageLibrary.images }`
- `var customImageOrder: [Int] { ... }`
- `var cropMap: [UUID: CropInfo] { ... }` (uses version counter workaround)

`@Observable` cannot track computed properties. Views reading `viewModel.images` will never receive updates — they must read `viewModel.imageLibrary.images` directly.

**Current workaround:** The `cropMap` property uses a version counter (`let _ = cropMapVersion`) to force re-evaluation. This works but is fragile.

**Recommendation:** Audit all view call sites. Either have views read managers directly (`viewModel.imageLibrary.images`) or store the values in the ViewModel and sync from manager callbacks.

---

### S3: `CollageAssembler` Combines 5 Protocols (497 lines)
**File:** `Services/CollageAssembler.swift`

`CollageAssembly` protocol inherits from `CollageRenderer`, `PanelRenderer`, `BackgroundRenderer`, `TitleRenderer`, and `OverlayRenderer`. This violates Interface Segregation — any consumer needing one capability depends on all five.

Additionally, the class does full assembly, preview assembly, per-panel rendering, background rendering, title rendering, and overlay rendering. Consider splitting into focused renderers.

---

### S4: `PanelCropEditor` Contains Geometry Algorithms (674 lines)
**File:** `Views/PanelCropEditor.swift`

The largest file in the project. Contains:
1. `PanelCropEditor` view (~169 lines)
2. `CropPreviewView` rendering (~288 lines)
3. Sutherland-Hodgman polygon clipping (~80 lines)
4. Crop adjustment domain logic (~185 lines)

The polygon clipping algorithm and crop adjustment math are computational geometry that belong in `Services/`, not `Views/`. The view should call `viewModel.adjustCrop(panelId:, dragValue:)`.

**Proposed split:**
- `CropPreviewView.swift` — rendering only
- `CropGeometry.swift` — static geometry methods (clip, quad, drag detection)
- `PanelCropEditorView.swift` — editor UI shell
- `PanelCropDragHandler.swift` — drag gesture logic

---

### S5: `ContentView.sidebar` Is a 260-Line Computed Property
**File:** `Views/ContentView.swift:77-338`

Mixes image list management, layout configuration, status display, and file operations. Should be decomposed into `ImageListSection`, `LayoutSection`, and `StatusSection` subviews.

---

### S6: `CollageEditorView.body` Is 290 Lines With 4 Gestures
**File:** `Views/CollageEditorView.swift:33-325`

Contains layered/preview rendering, title drag overlay, panel swap overlay, ScrollPanView overlay, and 4 gesture handlers (title drag, panel swap, pinch, tap). Each gesture handler should be a view modifier.

---

### S7: `DropHandler` Has No Protocol Abstraction
**File:** `Services/DropHandler.swift`

The only service without a protocol. Cannot be mocked in tests.

**Fix:** Add `protocol DropHandling { func loadImageURLs(from:) async -> [URL] }`.

---

### S8: `UserDefaultsPersistence.load()` Does Sync File I/O on Main Thread
**File:** `Services/UserDefaultsPersistence.swift:241-262`

`Data(contentsOf:)` for background images blocks the main thread during `load()`.

**Fix:** Split into `loadUserDefaults() -> PersistenceBundle` (fast, main-thread) and `loadImage(at:) async -> NSImage?` (background).

---

### S9: `UserDefaultsPersistence` Swallows Encoding Errors
**File:** `Services/UserDefaultsPersistence.swift:84,193,226`

`try?` on `JSONEncoder` and `NSKeyedArchiver` silently discards all encoding failures.

**Fix:** Log errors or return `Result`.

---

### S10: `SaliencyAnalyzer` Actor Is Unnecessary
**File:** `Services/SaliencyAnalyzer.swift`

The actor has zero stored state and `analyze` is `nonisolated`. The actor wrapper adds hop overhead with no safety benefit.

**Fix:** Convert to a `struct` with static methods.

---

## Suggestions (Improvements)

### Models
| # | File | Suggestion |
|---|------|------------|
| M1 | `AssemblyConfig.swift` | `BackgroundConfig` stores redundant `CGColor` copies of `NSColor` — convert to computed properties |
| M2 | `SaliencyResult.swift` | Move `cropOrigin` (Vision-specific logic) out of the data model into `SaliencyAnalyzer` |
| M3 | `ImageItem.swift` | Clarify distinction between `thumbnail` (stored `NSImage`) and `nsImage` (computed from `cgImage`) |
| M4 | `PanelGeometry.swift` | Move `extractPathPoints` to a `CGPath` extension; add `Equatable` conformance |
| M5 | `LayoutStyle.swift` | Move `icon` (SF Symbol names) from model to Views layer |
| M6 | `TitleStyle.swift` | Extract magic number `40` in `effectiveWidth` to a named constant |

### Services
| # | File | Suggestion |
|---|------|------------|
| SV1 | `CollageAssembler.swift:161-219` | DRY up `renderIntoContext` and `renderPreviewIntoContext` — 80% shared logic |
| SV2 | `PreviewManager.swift` | Split into `PreviewRenderer` (orchestration) + `PreviewState` (state) |
| SV3 | `PreviewManager.swift:21` | Remove unused `previewDebounceTask` property |
| SV4 | `LayoutGenerator.swift` | Split 6 strategies into separate files; consider registry pattern for OCP |
| SV5 | `TitleRendererCT.swift:22` | Add `@MainActor` or runtime assertion to `TitleTextData.extract` |
| SV6 | `CollageAssembler.swift:333-348` | Use `defer { context.restoreGState() }` for safety |

### ViewModel
| # | File | Suggestion |
|---|------|------------|
| V1 | `CollageViewModel.swift` | Register undo immediately in `didSet`, debounce only side effects |
| V2 | `CollageViewModel.swift` | `clearAll()` manually resets 12+ properties — extract to `resetState()` protocol |
| V3 | `CollageViewModel.swift` | `swapPanelImages` undo doesn't restore crop swap state |
| V4 | `CropManager.swift` | `applyPan`/`applyPinch` take 5 parameters — extract `CropContext` struct |
| V5 | `Debouncer.swift` | Dictionary grows unbounded with dynamic IDs — add TTL or max capacity |
| V6 | `ExportManager.swift` | `exportTask` type mismatch (`Void` vs `URL?`) |

### Views
| # | File | Suggestion |
|---|------|------------|
| VI1 | `CollageEditorView.swift` | Extract gesture handlers into view modifiers |
| VI2 | `CollageEditorView.swift` | Add accessibility to canvas |
| VI3 | `SettingsView.swift` | Unify UserDefaults persistence patterns (`@AppStorage` vs manual) |
| VI4 | `SettingsView.swift` | Extract tab views for `#Preview` support |
| VI5 | `AttributedStringEditor.swift` | Extract common font toggle logic (75 lines of near-identical patterns) |
| VI6 | `TitleDragHandler.swift` | Convert to static methods (instantiated fresh every gesture tick) |

### Tests
| # | File | Suggestion |
|---|------|------------|
| T1 | `ExportManagerTests.swift` | Add `MockSavePanelPresenter` and test full export flow |
| T2 | `CollageViewModelTests.swift` | Replace `Task.sleep(200ms)` with deterministic completion |
| T3 | `TestHelpers.swift` | Move `ThreadSafeArray` from `RenderSchedulerTests.swift` |
| T4 | `SaliencyAnalyzerTests.swift` | Add `@MainActor` to suite (uses `NSGraphicsContext`) |
| T5 | Missing | Create `DebouncerTests.swift`, `DropHandlerTests.swift`, `NSColor+Hex` tests |
| T6 | `CollageAssemblerTests.swift` | Add error-path testing (invalid crops, mismatched counts, nil images) |
| T7 | `TitleMetricsCTTests.swift` | Extract duplicated bitmap creation pattern to `TestHelpers.swift` |

---

## Nits (Optional)

| # | File | Note |
|---|------|------|
| N1 | `PanelGeometry.swift:32` | Doc comment states CoreGraphics origin is bottom-left; it is top-left |
| N2 | `SaliencyAnalyzer.swift:57` | Add comment explaining Vision Y-flip |
| N3 | `LayoutGenerator.swift:210` | `DoubleExposureLayoutStrategy` is a stub — add TODO or deprecation |
| N4 | `FitMath.swift` | Consider adding `fill` (cover) variant alongside `fit` (contain) |
| N5 | `DebugHelpers.swift` | Consider extensions on `CGRect`/`CGPoint`/`CGSize` instead of static methods |
| N6 | `NSColor+Hex.swift` | Consider supporting 7-char hex (RGB without alpha) |
| N7 | `ContentView.swift:16` | Extra whitespace in `@State` declaration |
| N8 | `CollageEditorView.swift:11` | `TitleResizeEdge` should be a nested type |
| N9 | `SettingsView.swift:68-71` | Dead `@State` variables (`solidLoaded`, `gradStartLoaded`, `gradEndLoaded`) |
| N10 | `ScrollPanView.swift:38` | Redundant `event.type` check |
| N11 | `CropManagerTests.swift:116` | `pinchZoomOutIncreasesCropSize` name doesn't match test behavior |
| N12 | `PanelCropEditorTests.swift` | Tests `CropManager` static methods, not `PanelCropEditor` |
| N13 | `CollagePerformanceTests.swift` | Not actual performance tests — rename |
| N14 | `LayoutGeneratorTests.swift:86` | `+10` tolerance is undocumented |

---

## Test Coverage Gaps

| Untested File | Priority | Reason |
|---------------|----------|--------|
| `Debouncer.swift` | High | Async cancellation logic is hard to get right |
| `DropHandler.swift` | High | URL parsing edge cases, UTType filtering |
| `NSColor+Hex.swift` | Medium | Color hex encoding/decoding round-trips |
| `GestureCoordinator.swift` | Medium | Pinch throttling logic |
| `ImageItem+Filtering.swift` | Low | Search filtering |
| `ScrollPanView.swift` | Low | Scroll wheel capture |
| `DebugHelpers.swift` | Low | Formatting utilities |

---

## Architecture Strengths

1. **Protocol abstractions** — `SaliencyAnalysis`, `CollageAssembly`, `LayoutStrategy`, `ViewModelPersistence` enable clean test mocking
2. **`TestAssembler` mock** — Combines call tracking, configurable returns, delay injection, and parameter recording
3. **UUID-based UserDefaults isolation** — Used consistently across test suites
4. **Version counter pattern** — `cropMapVersion` and `titleImageVersion` correctly preserve delegation abstraction for `@Observable`
5. **Multi-field cache invalidation** — `ensureTitleBounds()` clears all three cache fields atomically
6. **`@Suite(.serialized)`** — Applied to suites touching `NSGraphicsContext`
7. **Manager extraction pattern** — `CropManager`, `ExportManager`, `ImageLibraryManager` follow a consistent delegation pattern

---

## Approval Decision

**Status: Request Changes**

**Blocking issues:**
- C1: `CropInfo` Codable path data loss (data corruption)
- C2: `TitleStyle` Equatable NSColor reference comparison (silent bugs)
- C3: Unsynchronized saliency tasks (stale results)
- C6: `awaitPendingTasks` sleep anti-pattern (fragile tests)

**Recommended next steps (priority order):**
1. Fix C1, C2, C3, C7 (correctness bugs in Models)
2. Fix C4, C8 (concurrency safety)
3. Fix C5, C6 (cleanup and test reliability)
4. Address S1, S4, S5, S6 (god class decomposition)
5. Address S7, S8, S9 (service layer improvements)
6. Fill test coverage gaps (T1-T6)
