# CollageMaker — Full Architectural Code Review

**Date:** 2026-05-28
**Scope:** Entire codebase (Models, ViewModel, Services, Views, Tests)
**Reviewer:** Agent

---

## Executive Summary

CollageMaker is a well-structured macOS SwiftUI app with strong foundational architecture. The layering (Models → Services → ViewModel → Views) is clean, protocol-based dependencies enable testability, and the test suite is comprehensive. The primary area for improvement is **CollageViewModel**, which has grown into a ~960-line god class violating the Single Responsibility Principle. Several smaller issues around state duplication, thread safety, and missing test coverage are also noted.

**Verdict:** Request Changes (3 critical, 6 moderate, 8 minor)

---

## 1. Architecture & Design (SOLID Analysis)

### Strengths

| Area | Assessment |
|------|------------|
| **Layering** | Clear Models / Services / ViewModel / Views separation |
| **Dependency Inversion** | `SaliencyAnalysis` and `CollageAssembly` protocols enable mocking |
| **Interface Segregation** | Protocols are focused; `CollageAssembly` has 5 methods but they're cohesive |
| **Coordinate utilities** | `FitMath`, `CoordinateConverter`, `DebugHelpers` are well-extracted pure modules |
| **Config splitting** | `AssemblyConfig` → `LayoutConfig` / `TitleConfig` / `BackgroundConfig` is clean |

### Critical Issues

#### C1: CollageViewModel — God Class (SRP Violation)

**File:** `CollageMaker/ViewModel/CollageViewModel.swift` (963 lines)

The view model currently owns **7 distinct responsibilities**:

1. Image loading & browse orchestration
2. Layout regeneration coordination
3. Panel-image assignment management
4. Crop state delegation (wrapping CropManager)
5. Scroll/pan gesture delegation (wrapping ScrollPanManager)
6. Preview rendering orchestration (4 async tasks)
7. Export flow (save panel + assembly)
8. Undo management
9. Persistence coordination
10. Saliency analysis coordination

**Impact:** Every change to any of these areas risks regressions in others. The class is difficult to reason about, test in isolation, or refactor.

**Suggested Fix:** Consider extracting into focused sub-managers:
- `LayoutManager` — owns `panels`, `panelAssignments`, `customImageOrder`, `regenerateLayout()`
- `PreviewManager` — owns `updatePreview()`, `updateAllPanelPreviews()`, async task lifecycle
- `ExportManager` — owns `exportCollage()`, save panel, file writing
- Keep `CollageViewModel` as the UI-state coordinator with ~200 lines

#### C2: Dual cropMap State (Single Source of Truth Violation)

**Files:** `CollageViewModel.swift:34`, `CropManager.swift:7`

```swift
// CollageViewModel
var cropMap: [UUID: CropInfo] = [:]

// CropManager
var cropMap: [UUID: CropInfo] = [:]
```

These are manually synced at every mutation point:
```swift
cropManager.applyPan(...)
cropMap = cropManager.cropMap  // manual sync
```

**Impact:** Risk of divergence. Already visible in `applyOverlayCrop` where both are written separately (`CollageViewModel.swift:697-699`).

**Suggested Fix:** Either:
- Make `CropManager` the sole owner and expose `cropMap` as a computed property, or
- Have `CollageViewModel` own the map and pass it mutably to `CropManager` methods

#### C3: NSGraphicsContext Thread Safety

**File:** `CollageMaker/Services/CollageAssembler.swift`

`NSGraphicsContext.current` is a **global, non-thread-safe** singleton. The assembler methods use `saveGraphicsState()` / `restoreGraphicsState()` around it, but `updatePreview()` fires multiple `Task.detached` calls concurrently (`previewTask`, `backgroundTask`, `titleTask`, plus per-panel tasks). These can interleave on the global graphics context.

**Impact:** Potential visual corruption under concurrent preview updates. May be masked in practice by macOS internal locking, but it's not guaranteed.

**Suggested Fix:** Serialize rendering through an actor or operation queue:
```swift
actor RenderQueue {
    func render(_ work: () -> NSImage?) -> NSImage? { ... }
}
```

### Moderate Issues

#### M1: ScrollPanManager Tight Coupling to ViewModel

**File:** `CollageViewModel.swift:707-750`

The `scrollPanDelta` callback closure captures `cropManager`, `panels`, `images`, `panelAssignments`, and `cropMap` directly from the view model. `ScrollPanManager` should not know about crop internals.

**Suggested Fix:** Invert the dependency — `ScrollPanManager` emits raw scroll deltas, and the ViewModel interprets them. Currently the callback already does this partially, but the `commit` closure re-enters crop manager state management.

#### M2: SettingsView Bypasses Persistence Service

**File:** `CollageMaker/Views/SettingsView.swift`

SettingsView writes directly to `UserDefaults.standard` with raw string keys:
```swift
UserDefaults.standard.set(newValue, forKey: "gradientAngle")
```

This bypasses `UserDefaultsPersistence.Keys` and creates a dual persistence path. The `UserDefaultsColorView` coordinator also writes directly.

**Suggested Fix:** Either inject `UserDefaultsPersistence` or use the centralized `Keys` enum. Better yet, have SettingsView bind to the same `CollageViewModel` instance so persistence flows through one path.

#### M3: Silent Error Swallowing

**File:** `CollageViewModel.swift:222-228`

```swift
private func debouncedSave() {
    saveDebounceTask?.cancel()
    // ...
    persistence.save(self)  // errors silently swallowed by try?
}
```

Persistence failures are silently ignored. User changes could be lost with no indication.

**Suggested Fix:** Surface persistence errors to `errorMessage` or at minimum log at error level.

#### M4: SaliencyResult.cropOrigin Portrait Swap — Unclear Intent

**File:** `CollageMaker/Models/SaliencyResult.swift:22-25`

```swift
if imageSize.width < imageSize.height {
    originX = center.y - halfW
    originY = center.x - halfH
}
```

X/Y swap for portrait images is undocumented and non-obvious. This appears to compensate for Vision framework coordinate orientation, but the reasoning is lost.

**Suggested Fix:** Add a comment explaining the coordinate system mismatch, or extract to a named function like `adjustForPortraitOrientation()`.

#### M5: ImageItem Memory Retention

**File:** `CollageMaker/Models/ImageItem.swift`

Each `ImageItem` holds `nsImage`, `cgImage`, and `thumbnail` simultaneously. For a 20MP photo, the cgImage alone is ~80MB. With 10 images, that's 800MB+ of pixel data in memory.

**Suggested Fix:** Consider lazy-loading the full-resolution `cgImage` from disk on demand, or using `CGImageSource` to create downscaled versions for preview. The `nsImage` already caches the cgImage internally, so holding both may be redundant.

#### M6: Missing @MainActor on CollageCommands

**File:** `CollageMaker/Views/CollageCommands.swift`

`CollageCommands` holds a `CollageViewModel` reference and calls `viewModel.browseImages()` and `viewModel.exportCollage()`. While `Commands` structs are evaluated on the main actor, this is implicit and could be fragile.

---

## 2. Code Quality

### Strengths

- **Naming:** Consistent, descriptive names throughout (`regenerateLayout`, `computeCropsFromSaliency`, `canvasToPreviewFrame`)
- **Small functions:** Most service methods are focused and under 30 lines
- **Error types:** `SaliencyError` enum provides structured errors
- **Performance instrumentation:** `ContinuousClock` timing with `defer` is well-applied

### Issues

#### Minor: Duplicate AssemblyConfig Construction

`AssemblyConfig` is constructed identically in `updatePreview()` and `exportCollage()`. Extract to a helper method.

#### Minor: applyOverlayCrop No-op Assignment

**File:** `CollageViewModel.swift:699-700`
```swift
var tmp = cropMap
cropMap = tmp
```
This appears to be a forced reassignment to trigger `@Observable` tracking. Consider using a dedicated mutation pattern.

#### Minor: Debug Logger in onAppear

**File:** `CollageMaker/Views/CollageEditorView.swift:200`
```swift
.onAppear {
    logger.info("Highlight: panel ...")
}
```
This fires every time the selection highlight view appears. Should be `debug` level or gated behind `#debug`.

#### Minor: TitleMetrics Computed Property Recalculation

**File:** `CollageMaker/Services/TitleMetrics.swift:23-28`

`boundingBox` is a computed property that calls `boundingRect` every time. In hot paths (every frame during title drag), this recalculates layout. Consider caching with invalidation.

#### Nit: CollageAssembler Duplicate Code

`assembleWithCGImages` and `assemblePreviewWithCGImages` share ~80% identical code (context creation, panel drawing, title drawing). Extract to `renderIntoContext(config:, cgImages:, backgroundImage:)` and differ only in the final output step.

#### Nit: PanelCropEditor — 408 Lines

The crop editor view contains extensive resize math that could be extracted to a `CropResizeCalculator` utility.

#### Nit: AttributedStringEditor — 362 Lines

Bold/italic/underline toggle logic is repeated 3 times. Extract to a generic `toggleFontTrait(_ trait:, in textStorage:, at range:)` helper.

#### Nit: FontPickerPopover — Eager Font Loading

`font(for:)` creates an `NSFont` for every list item during rendering. With 300+ font families, this is expensive. Consider lazy rendering or caching.

---

## 3. Testing

### Strengths

| Metric | Status |
|--------|--------|
| Test files | 12 (excellent) |
| Services covered | LayoutGenerator, CropManager, ScrollPanManager, SaliencyAnalyzer, CollageAssembler, FontMerger, TitleMetrics, SaliencyResult |
| Mocking pattern | Clean protocol-based mocks (`MockSaliencyAnalyzer`, `MockAssembler`, `TrackingAssembler`) |
| AppKit init | Properly handled in `TestHelpers.swift` |
| Edge cases | Boundary clamping, empty inputs, coordinate transforms well-tested |

### Gaps

| Untested Component | Risk |
|--------------------|------|
| `FitMath` | Medium — core math, easy to test |
| `UserDefaultsPersistence` | Medium — persistence bugs are hard to debug |
| `CoordinateConverter` | Low — tested indirectly via CropManager |
| `CollageEditorView` gesture logic | High — complex gesture coordination |
| `PanelCropEditor` resize math | Medium — coordinate transforms |
| `ExportPanel` | Low — mostly UI wiring |
| `SettingsView` | Low — UserDefaults binding |

**Suggested additions:**
1. `FitMathTests` — test `fit()` and `sourceRect()` with known aspect ratios
2. `UserDefaultsPersistenceTests` — verify save/load round-trip for all 13 properties
3. `AssemblyConfig` construction tests — verify sub-config nesting

---

## 4. Documentation

### Strengths
- `AGENTS.md` is comprehensive with architecture diagram, conventions, and gotchas
- `_agent_docs/learnings/` contains 30+ session learnings
- Inline comments explain non-obvious decisions (e.g., NSSavePanel blocking, panelAssignments non-persistence)

### Gaps
- No doc comments on public APIs (`CollageAssembly`, `SaliencyAnalysis`, `LayoutGenerator.generate`)
- `SaliencyResult.cropOrigin` portrait swap lacks explanation (see M4)
- `ScrollPanManager` commit timer behavior (150ms debounce) is not documented

---

## 5. Style & Consistency

### Consistent
- OSLog with unified subsystem `austin183.indie.CollageMaker`
- `@MainActor` + `@Observable` pattern
- `weak self` in all async closures
- `guard`-early-return style
- Privacy annotations on log messages

### Inconsistencies
- `perfLogger` uses `Bundle.main.bundleIdentifier!` as subsystem vs the standard `austin183.indie.CollageMaker`
- Some `didSet` observers call `debouncedSave()` + `updatePreview()`, others call `regenerateLayout()` — the distinction is clear but not documented
- `CropManager.clamp` is private; `Swift.max`/`Swift.min` are used elsewhere for the same purpose

---

## Issue Summary

| # | Severity | Issue | File |
|---|----------|-------|------|
| C1 | Critical | CollageViewModel god class (SRP) | CollageViewModel.swift |
| C2 | Critical | Dual cropMap state (SST) | CollageViewModel.swift, CropManager.swift |
| C3 | Critical | NSGraphicsContext thread safety | CollageAssembler.swift |
| M1 | Moderate | ScrollPanManager-ViewModel coupling | CollageViewModel.swift:707 |
| M2 | Moderate | SettingsView bypasses persistence | SettingsView.swift |
| M3 | Moderate | Silent error swallowing | CollageViewModel.swift:224 |
| M4 | Moderate | SaliencyResult portrait swap undocumented | SaliencyResult.swift:22 |
| M5 | Moderate | ImageItem memory retention | ImageItem.swift |
| M6 | Moderate | Missing @MainActor on CollageCommands | CollageCommands.swift |
| — | Minor | Duplicate AssemblyConfig construction | CollageViewModel.swift |
| — | Minor | applyOverlayCrop no-op reassignment | CollageViewModel.swift:699 |
| — | Minor | Debug logger in onAppear | CollageEditorView.swift:200 |
| — | Minor | TitleMetrics boundingBox recomputation | TitleMetrics.swift |
| — | Nit | CollageAssembler duplicate code | CollageAssembler.swift |
| — | Nit | PanelCropEditor 408 lines | PanelCropEditor.swift |
| — | Nit | AttributedStringEditor toggle duplication | AttributedStringEditor.swift |
| — | Nit | FontPickerPopover eager font loading | FontPickerPopover.swift |

---

## Recommendations (Prioritized)

1. **Extract PreviewManager** from CollageViewModel — lowest risk, highest immediate benefit
2. **Unify cropMap ownership** — pick one owner, remove manual sync
3. **Serialize NSGraphicsContext access** — add an actor or queue
4. **Add FitMath and UserDefaultsPersistence tests** — small, high-value
5. **Document SaliencyResult coordinate swap** — one-line comment prevents future confusion
6. **Extract AssemblyConfig construction** — reduce duplication between preview/export
7. **Fix SettingsView persistence path** — use centralized keys or inject service
8. **Consider ImageItem lazy loading** — defer until memory pressure is observed
