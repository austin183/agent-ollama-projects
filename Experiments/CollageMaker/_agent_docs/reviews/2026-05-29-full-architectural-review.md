# CollageMaker — Architectural Code Review (Follow-up)

**Date:** 2026-05-29
**Scope:** Entire codebase (Models, ViewModel, Services, Views, Tests)
**Supersedes:** 2026-05-28-full-architectural-review.md

---

## Executive Summary

Significant improvements since the May 28 review. Three critical issues have been resolved: `cropMap` ownership is unified, `NSGraphicsContext` rendering is serialized, and `SaliencyResult` coordinate swap is documented. `PreviewManager` has been extracted, and three new test suites were added. The primary remaining concern is `CollageViewModel` at 1008 lines — still a god class despite the PreviewManager extraction.

**Verdict:** Request Changes (1 critical, 6 moderate, 9 minor)

---

## Issues Resolved Since May 28

| Issue | Status | Resolution |
|-------|--------|------------|
| C2: Dual cropMap state | **Fixed** | `CollageViewModel.cropMap` is now a computed property backed by `CropManager` with a version counter for `@Observable` tracking |
| C3: NSGraphicsContext thread safety | **Fixed** | `CollageAssembler` serializes all rendering through a dedicated `DispatchQueue` (`renderQueue`) |
| M3: Silent error swallowing | **Fixed** | `debouncedSave()` now logs errors and surfaces to `errorMessage` |
| M4: SaliencyResult portrait swap | **Fixed** | Clear comment explains Vision coordinate rotation for portrait images |
| PreviewManager extraction | **Done** | Preview rendering is now in `PreviewManager.swift` (168 lines, `@Observable`) |
| AssemblyConfig duplication | **Done** | Extracted to `buildAssemblyConfig()` method |
| FitMathTests | **Done** | New test suite added |
| UserDefaultsPersistenceTests | **Done** | New test suite added |
| PreviewManagerTests | **Done** | New test suite added |

---

## 1. Architecture & Design (SOLID Analysis)

### Strengths

| Area | Assessment |
|------|------------|
| **Layering** | Clean Models / Services / ViewModel / Views separation |
| **Dependency Inversion** | `SaliencyAnalysis`, `CollageAssembly` protocols enable mocking |
| **Config nesting** | `AssemblyConfig` → `LayoutConfig` / `TitleConfig` / `BackgroundConfig` is well-structured |
| **Pure utilities** | `FitMath`, `CoordinateConverter`, `DebugHelpers`, `LayoutGenerator` are well-extracted, testable modules |
| **Persistence** | `UserDefaultsPersistence` centralizes all keys and handles NSKeyedArchiver for AppKit types |
| **Crop management** | `CropManager` as `@Observable` class with clear gesture state lifecycle |
| **Concurrency** | `SaliencyAnalyzer` as `actor` for thread-safe Vision API access |

### Critical Issues

#### C1: CollageViewModel — God Class (SRP Violation)

**File:** `CollageMaker/ViewModel/CollageViewModel.swift` (1008 lines)

Despite the `PreviewManager` extraction, the view model still owns **7+ distinct responsibilities**:

1. Image loading & browse orchestration (`browseImages`, `addImages`, `removeImage`, `moveImages`, `clearAll`)
2. Layout regeneration coordination (`regenerateLayout`, `setLayoutStyle`, `updateGutter`)
3. Panel-image assignment management (`assignImage`, `swapPanelImages`, `selectPanelForImage`)
4. Crop gesture orchestration (12+ methods wrapping `CropManager`)
5. Scroll/pan gesture delegation (`beginScrollPan`, `scrollPanDelta`, `endScrollPan`, `scheduleScrollPanCommit`)
6. Export flow (`exportCollage` — save panel + assembly + file write)
7. Undo management (manually registered in every `didSet` and mutating method)
8. Persistence coordination (`debouncedSave`)
9. Saliency analysis coordination (`analyzeSaliency`)
10. UI state flags (`isProcessing`, `isExporting`, `isLiveGesturing`, `isDraggingTitle`, `errorMessage`, `exportSuccessMessage`)

**Impact:** Every change to any of these areas risks regressions in others. The class is difficult to reason about and test in isolation.

**Suggested Fix:** Further extraction:
- `ExportManager` — owns `exportCollage()`, save panel, file writing, `isExporting` state
- `ImageLibraryManager` — owns `images`, `browseImages`, `addImages`, `removeImage`, `moveImages`
- Keep `CollageViewModel` as the UI-state coordinator wiring the managers together

### Moderate Issues

#### M1: ScrollPanManager — ViewModel Leakage

**Files:** `CollageViewModel.swift:747-798`, `ScrollPanManager.swift`

The scroll pan flow in `scrollPanDelta` directly accesses `cropManager`, `panels`, `images`, `panelAssignments` from the view model. The `scheduleScrollPanCommit` timer re-enters crop manager state management, creating a complex interleaving of gesture state, crop state, and preview rendering.

```swift
func scrollPanDelta(_ delta: CGSize) {
    scrollPanManager.accumulateDelta(delta, sensitivity: scrollSensitivity)
    cropManager.pan(by: scrollPanManager.accumulator)
    cropManager.applyPan(panelId: nil, panels: panels, images: images, panelAssignments: panelAssignments, finish: false)
    // ... preview debouncing
    scheduleScrollPanCommit()
}
```

**Impact:** `ScrollPanManager` knows nothing about crops, but the View Model's scroll pan methods are tightly coupled to crop internals. This makes it hard to reuse scroll pan logic or test it independently.

**Suggested Fix:** Collapse the scroll pan flow into `CropManager` — give it a `beginScrollPan`, `scrollPanDelta`, `endScrollPan` interface that handles the accumulator internally.

#### M2: SettingsView Dual Persistence Path

**File:** `CollageMaker/Views/SettingsView.swift`

SettingsView writes directly to `UserDefaults.standard` with raw string keys and `@AppStorage`. The `UserDefaultsColorView` coordinator also writes directly:

```swift
// SettingsView.swift:163
UserDefaults.standard.set(newValue, forKey: UserDefaultsPersistence.Keys.gradientAngle)

// UserDefaultsColorView.Coordinator:46
UserDefaults.standard.set(data, forKey: key)
```

This bypasses `UserDefaultsPersistence.save()` and creates two independent persistence paths. Settings defaults (e.g., `defaultTitle`, `defaultFontFamily`) are stored separately from the active session state, but the relationship between them is unclear — the active ViewModel never reads the Settings defaults.

**Impact:** Settings changes don't affect the active collage. The `defaultTitle`/`defaultFontFamily` keys exist only in Settings but are never consumed by the ViewModel.

**Suggested Fix:** Either:
- Have SettingsView bind to the same `CollageViewModel` so all persistence flows through one path, or
- Document that Settings stores *defaults for new sessions* and add a "Apply to Current" action

#### M3: ImageItem Memory Retention

**File:** `CollageMaker/Models/ImageItem.swift`

Each `ImageItem` holds `nsImage`, `cgImage`, and `thumbnail` simultaneously. For a 20MP photo, the `cgImage` alone is ~80MB uncompressed pixel data. With 10 images, that's 800MB+ in memory.

```swift
struct ImageItem: Identifiable, Equatable {
    let id: UUID
    let nsImage: NSImage
    let cgImage: CGImage       // Full-resolution pixel data
    let thumbnail: NSImage     // Additional copy
    let filename: String
    let size: CGSize
}
```

**Impact:** Memory pressure with large image sets. No eviction or lazy loading.

**Suggested Fix:** Consider:
- Making `cgImage` a lazy computed property that extracts from `nsImage` on demand
- Storing the file URL instead of `nsImage` and loading on demand
- Downsampling the thumbnail more aggressively

#### M4: CollageEditorView — View-Local Gesture State

**File:** `CollageMaker/Views/CollageEditorView.swift` (447 lines)

The editor view manages 8 `@State` variables for gesture tracking:

```swift
@State private var pinchPanelId: UUID?
@State private var dragTitleLocked = false
@State private var titleResizeEdge: TitleResizeEdge = .none
@State private var dragSourcePanelId: UUID?
@State private var dragTargetPanelId: UUID?
@State private var dragCursorLocation: CGPoint?
@State private var dragSourceImageIndex: Int = 0
@State private var oldTitleStyle: TitleStyle?
@State private var dragTitleOffset = CGPoint.zero
```

Three `simultaneousGesture` modifiers compete for input, with complex hit-testing logic in `.onChanged` closures. Title drag, panel swap drag, and magnification gestures are all woven into the view body.

**Impact:** The view body is dominated by gesture handling logic rather than layout. This is hard to test and refactor.

**Suggested Fix:** Extract gesture handling into a `@MainActor final class GestureCoordinator` with `@StateObject`, or into a SwiftUI `Gesture`-returning view modifier.

#### M5: LayoutGenerator — Switch on Enum (OCP Violation)

**File:** `CollageMaker/Services/LayoutGenerator.swift:15-22`

Adding a new layout style requires modifying the `generate` method's switch statement, violating the Open/Closed Principle.

```swift
switch style {
case .uniform: return generateUniform(...)
case .hero:    return generateHero(...)
case .mosaic:  return generateMosaic(...)
}
```

**Suggested Fix:** Strategy pattern — define a `LayoutStrategy` protocol and map `LayoutStyle` cases to strategy instances, enabling new layouts without modifying `LayoutGenerator`.

#### M6: FitMath — Division by Zero Risk

**File:** `CollageMaker/Services/FitMath.swift:10-11`

```swift
let sourceAspect = sourceSize.width / sourceSize.height
let containerAspect = containerSize.width / containerSize.height
```

If either height is zero, this produces infinity/NaN, propagating through all subsequent calculations.

**Suggested Fix:** Add guard clauses for zero dimensions and return a safe fallback (e.g., zero-sized fit or the container size).

### Minor Issues

#### mi1: NSColorPickerView — Color Comparison Guard

**File:** `CollageMaker/Views/ExportPanel.swift:26-28`

```swift
func updateNSView(_ well: NSColorWell, context: Context) {
    if well.color != color {
        well.color = color
    }
}
```

`NSColor ==` compares `CGColor` values, which differ across color spaces. This guard can prevent the color well from updating when the color is semantically the same but in a different color space.

**Suggested Fix:** Remove the guard — always assign `well.color = color` unconditionally. (The skill reference `nscolorwell.md` documents this.)

#### mi2: perfLogger Subsystem Inconsistency

**File:** `CollageMaker/Services/SaliencyAnalyzer.swift:12-14`

```swift
private let perfLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "performance"
)
```

Uses `Bundle.main.bundleIdentifier!` as subsystem instead of the standard `austin183.indie.CollageMaker`. This splits performance logs across two subsystems in `log stream`.

**Suggested Fix:** Use the standard subsystem string for consistency.

#### mi3: TitleMetrics — Computed Property Recalculation

**File:** `CollageMaker/Services/TitleMetrics.swift:23-28`

`boundingBox` and `minNaturalWidth` are computed properties that call `boundingRect` every time. During title drag (60Hz), `CollageEditorView.titleCanvasFrame` recomputes `TitleMetrics` each render cycle.

**Impact:** Redundant text layout computation during interactive title drag.

**Suggested Fix:** Cache the `TitleMetrics` instance in the view model and invalidate only when `titleAttrString` or `titleStyle` changes.

#### mi4: CollageAssembler — Duplicate Assembly Logic

**File:** `CollageMaker/Services/CollageAssembler.swift:67-156`

`assembleWithCGImages` and `assemblePreviewWithCGImages` share ~80% identical code: context creation, panel drawing, title drawing. They differ only in the final output step (JPEG `Data` vs `NSImage`).

**Suggested Fix:** Extract to `renderIntoContext(config:, cgImages:, backgroundImage:) -> NSBitmapImageRep` and have each method handle only the final encoding step.

#### mi5: LayoutGenerator — Force Unwrap ImageOrder

**File:** `CollageMaker/Services/LayoutGenerator.swift`

```swift
let imgIdx = imageOrder != nil ? imageOrder![i] : i % numImages
```

This nil-check-then-force-unwrap pattern appears 8 times. It works correctly but is fragile.

**Suggested Fix:** Use `imageOrder?[i] ?? i` or provide a default `[Int]` parameter.

#### mi6: CollageAssembly Protocol — Too Broad (ISP Violation)

**File:** `CollageMaker/Services/CollageAssembler.swift:11-44`

The protocol declares 5 methods (`assembleWithCGImages`, `assemblePreviewWithCGImages`, `renderPanel`, `renderBackground`, `renderTitle`), forcing every mock to implement all of them even when only one is under test.

**Suggested Fix:** Split into focused protocols: `CollageRenderer`, `PanelRenderer`, `BackgroundRenderer`, `TitleRenderer`. `CollageAssembler` can conform to all four.

#### mi7: CropManager — Unnecessary `@Observable`

**File:** `CollageMaker/ViewModel/CropManager.swift:6-8`

`CropManager` is marked `@Observable` but the `CollageViewModel` uses a version counter (`cropMapVersion`) to trigger observation. The `@Observable` macro on `CropManager` is dead weight.

**Suggested Fix:** Remove `@Observable` from `CropManager`.

#### mi8: CollageViewModel — Dead Code

**File:** `CollageMaker/ViewModel/CollageViewModel.swift:429`

```swift
_ = images.map { $0.id }
```

This no-op expression does nothing and was likely left over from debugging.

**Suggested Fix:** Remove.

#### mi9: NSKeyedArchiver — No Secure Coding

**File:** `CollageMaker/Models/TitleStyle.swift:44` (also in `UserDefaultsPersistence.swift`, `SettingsView.swift`)

```swift
if let data = try? NSKeyedArchiver.archivedData(withRootObject: fontColor, requiringSecureCoding: false)
```

While data is only persisted locally, `requiringSecureCoding: false` is a security anti-pattern.

**Suggested Fix:** Use `requiringSecureCoding: true` where possible, or encode colors manually (e.g., as RGBA hex strings).

---

## 2. Code Quality

### Strengths

- **Naming:** Consistent, descriptive names throughout
- **Small functions:** Most service methods are focused and under 30 lines
- **Error types:** `SaliencyError` enum provides structured errors
- **Performance instrumentation:** `ContinuousClock` timing with `defer` is well-applied
- **Coordinate utilities:** `FitMath`, `CoordinateConverter` are clean, pure, well-tested
- **`@Observable` patterns:** Version counter pattern for `cropMap` is a creative solution for tracking external mutations

### Areas for Improvement

| Area | Note |
|------|------|
| **didSet boilerplate** | Every property in `CollageViewModel` has a 6-line `didSet` (guard, undo, action name, save, update). A property wrapper or macro could reduce this. |
| **DispatchWorkItem in ViewModel** | `scrollCommitTimer` uses `DispatchWorkItem` while the rest of the codebase uses `Task`. Consider unifying. |
| **PanelCropEditor** | 409 lines of resize math could benefit from a `CropResizeCalculator` utility |
| **AttributedStringEditor** | 362 lines with 3x repeated toggle logic for bold/italic/underline |

---

## 3. Testing

### Current Coverage

| Component | Tests | Status |
|-----------|-------|--------|
| `LayoutGenerator` | `LayoutGeneratorTests` | Covered |
| `CropManager` | `CropManagerTests` | Covered |
| `ScrollPanManager` | `ScrollPanManagerTests` | Covered |
| `SaliencyAnalyzer` | `SaliencyAnalyzerTests` | Covered |
| `CollageAssembler` | `CollageAssemblerTests` | Covered |
| `FontMerger` | `FontMergerTests` | Covered |
| `TitleMetrics` | `TitleMetricsTests` | Covered |
| `SaliencyResult` | `SaliencyResultTests` | Covered |
| `FitMath` | `FitMathTests` | **Added since last review** |
| `UserDefaultsPersistence` | `UserDefaultsPersistenceTests` | **Added since last review** |
| `PreviewManager` | `PreviewManagerTests` | **Added since last review** |
| `CollageViewModel` | `CollageViewModelTests` | Covered (mocking pattern) |
| `PanelCropEditor` | `PanelCropEditorTests` | Covered |
| Export flow | `ExportFlowTests` | Covered |
| Performance | `CollagePerformanceTests` | Covered |

### Remaining Gaps

| Untested Component | Risk |
|--------------------|------|
| `CollageEditorView` gesture coordination | High — complex gesture logic |
| `CoordinateConverter` | Low — tested indirectly via CropManager |
| `ExportPanel` | Low — mostly UI wiring |
| `SettingsView` | Low — UserDefaults binding |

---

## 4. Documentation

### Strengths
- `AGENTS.md` is comprehensive with architecture, conventions, and gotchas
- `_agent_docs/learnings/` contains 43 session learnings
- Inline comments explain non-obvious decisions (NSSavePanel blocking, panelAssignments non-persistence, Vision coordinate swap)
- `FitMath` has doc comments

### Gaps
- No doc comments on public APIs (`CollageAssembly`, `SaliencyAnalysis`, `LayoutGenerator.generate`)
- `ScrollPanManager` commit timer behavior is undocumented
- `PreviewManager` task cancellation semantics are undocumented

---

## 5. Style & Consistency

### Consistent
- OSLog with unified subsystem `austin183.indie.CollageMaker`
- `@MainActor` + `@Observable` pattern
- `weak self` in all async closures
- `guard`-early-return style
- Privacy annotations on log messages

### Inconsistencies
- `perfLogger` in `SaliencyAnalyzer` uses `Bundle.main.bundleIdentifier!` vs standard subsystem
- `DispatchWorkItem` for scroll commit timer vs `Task` for everything else
- `CropManager.clamp` is private; `Swift.max`/`Swift.min` used elsewhere for the same purpose

---

## Issue Summary

| # | Severity | Issue | File | Status |
|---|----------|-------|------|--------|
| C1 | Critical | CollageViewModel god class (SRP) | CollageViewModel.swift (1008 lines) | **Open** |
| M1 | Moderate | ScrollPan-ViewModel coupling | CollageViewModel.swift:747 | **Open** |
| M2 | Moderate | SettingsView dual persistence | SettingsView.swift | **Open** |
| M3 | Moderate | ImageItem memory retention | ImageItem.swift | **Open** |
| M4 | Moderate | View-local gesture state (8 @State vars) | CollageEditorView.swift | **Open** |
| M5 | Moderate | LayoutGenerator switch on enum (OCP) | LayoutGenerator.swift:15 | **New** |
| M6 | Moderate | FitMath division by zero | FitMath.swift:10 | **New** |
| mi1 | Minor | NSColorPickerView color comparison guard | ExportPanel.swift:26 | **New** |
| mi2 | Minor | perfLogger subsystem inconsistency | SaliencyAnalyzer.swift:12 | **New** |
| mi3 | Minor | TitleMetrics recomputation during drag | TitleMetrics.swift:23 | **Open** |
| mi4 | Minor | CollageAssembler duplicate code | CollageAssembler.swift:67-156 | **Open** |
| mi5 | Minor | Force unwrap imageOrder | LayoutGenerator.swift | **New** |
| mi6 | Minor | CollageAssembly protocol too broad (ISP) | CollageAssembler.swift:11 | **New** |
| mi7 | Minor | Unnecessary @Observable on CropManager | CropManager.swift:6 | **New** |
| mi8 | Minor | Dead code no-op | CollageViewModel.swift:429 | **New** |
| mi9 | Minor | NSKeyedArchiver without secure coding | TitleStyle.swift:44 | **New** |

---

## Recommendations (Prioritized)

1. **Extract ExportManager** from CollageViewModel — owns `exportCollage()`, save panel, file I/O, `isExporting` state
2. **Extract ImageLibraryManager** — owns `images`, `browseImages`, `addImages`, `removeImage`, `moveImages`, `clearAll`
3. **Fix FitMath division by zero** — add guard clauses for zero dimensions (1-line fix)
4. **Fix NSColorPickerView guard** — remove `!=` comparison, always assign (1-line fix)
5. **Unify perfLogger subsystem** — use standard subsystem string (1-line fix)
6. **Remove dead code** — delete no-op expression at CollageViewModel.swift:429 (1-line fix)
7. **Remove @Observable from CropManager** — unnecessary macro (1-line fix)
8. **Simplify LayoutGenerator imageOrder** — replace nil-check-then-force-unwrap with optional chaining
9. **Split CollageAssembly protocol** — into focused `CollageRenderer`, `PanelRenderer`, etc.
10. **LayoutGenerator strategy pattern** — make layout styles extensible without modification
11. **Collapse scroll pan into CropManager** — give it a self-contained scroll pan interface
12. **Document Settings defaults semantics** — clarify relationship between Settings and active session
13. **Use NSKeyedArchiver secure coding** — enable `requiringSecureCoding: true` or encode manually
14. **Consider ImageItem lazy loading** — defer until memory pressure is observed
