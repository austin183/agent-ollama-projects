# CollageMaker — Architectural Review Fixes Plan

**Date:** 2026-05-25
**Source:** `_agent_docs/reviews/2026-05-25-architectural-review.md`
**Scope:** High + Medium priority items (7 of 10 recommendations)
**Defered:** Items 8-10 (ExportCoordinator, Task.sleep replacement, full VM splitting)

---

## Overview

| # | Item | Priority | Files Changed | Est. Lines Added | Est. Lines Removed |
|---|------|----------|--------------|-----------------|-------------------|
| 1 | Extract UserDefaults persistence | High | 2 new + 1 modified | ~160 | ~120 |
| 2 | Fix ExportPanel.chooseBackgroundImage | High | 1 modified | ~2 | ~5 |
| 3 | Fix test extension duplication | High | 2 modified | ~3 | ~35 |
| 4 | Extract FitMath utility | Medium | 1 new + 4 modified | ~40 | ~60 |
| 5 | Split AssemblyConfig | Medium | 3+ modified | ~30 | ~20 |
| 6 | Reduce CollageAssembly protocol | Medium | 3 modified | ~5 | ~15 |
| 7 | Add missing tests | Medium | 3 new | ~120 | 0 |

---

## Item 1: Extract UserDefaults Persistence

**Problem:** CollageViewModel has 13 `didSet` observers each mixing undo registration, `UserDefaults.standard.set(...)` persistence, and business logic side effects. Two inline key strings (`"titleAttrString"`, `"defaultFontSize"`) bypass the centralized `ViewModelUserDefaultsKeys` enum.

**Solution:** Create a dedicated `UserDefaultsPersistence` service.

### New file: `Services/UserDefaultsPersistence.swift`

```
UserDefaultsPersistence class:
  - save(_ viewModel: CollageViewModel) — saves all 13 persisted properties
  - load() -> PersistenceBundle — returns defaults for initialization
  - Consolidates ALL UserDefaults keys (including current inline strings)
  - Handles type-specific archiving (NSKeyedArchiver for colors/attr strings, JSON for [Int])
```

### Modified: `CollageViewModel.swift`

- Inject `UserDefaultsPersistence` dependency
- Each `didSet` becomes: undo registration + `persistence.save(self)` + side effect
- Initializer calls `persistence.load()` to populate defaults
- `backgroundImage`'s `didSet` gains URL path persistence (currently only removes on nil)

**13 Persisted properties to cover:**
1. `layoutStyle` — raw value
2. `titleAttrString` — NSKeyedArchiver (currently inline key `"titleAttrString"`)
3. `titleStyle` — delegates to `TitleStyle.saveToUserDefaults()`
4. `gutter` — Double
5. `backgroundColor` — NSKeyedArchiver
6. `exportQuality` — Double
7. `backgroundStyle` — raw value
8. `gradientStartColor` — NSKeyedArchiver
9. `gradientEndColor` — NSKeyedArchiver
10. `gradientAngle` — Double
11. `backgroundImage` — URL path (currently only persisted in ExportPanel)
12. `backgroundOpacity` — Double
13. `customImageOrder` — JSON-encoded [Int]

---

## Item 2: Fix ExportPanel.chooseBackgroundImage()

**Problem:** `ExportPanel.chooseBackgroundImage()` (lines 227-244) directly writes to `UserDefaults` and calls `viewModel?.updatePreview()` redundantly.

**Current code:**
```swift
viewModel?.backgroundImage = image
UserDefaults.standard.set(url.path, forKey: ViewModelUserDefaultsKeys.backgroundImagePath)  // duplicate
viewModel?.updatePreview()  // redundant — backgroundImage's didSet already calls this
```

**Fix:** Remove the two lines after `viewModel?.backgroundImage = image`. The `didSet` handles persistence (via Item 1) and preview update.

---

## Item 3: Fix Test Extension Duplication

**Problem:** `CollageViewModelTests.swift:214-249` defines a `cropManager_computeInitialCrops()` extension that reimplements `CropManager.computeInitialCrops()` + `CropManager.computeBestFitSource()`. The `computeBestFitSource` implementation is character-for-character identical.

**Fix:**
- Make `CropManager.computeInitialCrops()` internal (not private)
- Remove the entire extension (lines 214-249)
- Update the one calling test (`saliencyErrorSetsErrorMessage`) to delegate to `cropManager`

---

## Item 4: Extract FitMath Utility

**Problem:** Aspect-ratio-aware fit calculation (determine fitted size within container, compute centering offset) appears in 5+ locations:

| Location | Method |
|----------|--------|
| `CropManager.swift:213-232` | `screenToCanvasPoint` |
| `CropManager.swift:241-260` | `computeBestFitSource` |
| `CoordinateConverter.canvasToPreviewFrame` | preview frame transform |
| `CoordinateConverter.sourceRectInContainer` | crop rect in container |
| `PanelCropEditor.adjustCropDuringDrag` | drag coordinate scaling |

### New file: `Services/FitMath.swift`

```
struct FitMath:
  static func fit(_ sourceSize: CGSize, into containerSize: CGSize)
      -> (fittedSize: CGSize, offset: CGPoint)
    — core algorithm: compare aspect ratios, constrain, center

  static func sourceRect(imageSize: CGSize, panelSize: CGSize) -> CGRect
    — convenience wrapper for crop computation
```

All 5 call sites delegate to `FitMath.fit` or `FitMath.sourceRect`.

---

## Item 5: Split AssemblyConfig

**Problem:** `AssemblyConfig` has 12 fields. Adding new configuration (shadows, borders, filters) requires modifying the struct and every call site.

### Modified: `Models/AssemblyConfig.swift`

Introduce sub-configs:

```
AssemblyConfig:
  layout: LayoutConfig      — panels, crops, panelAssignments
  title: TitleConfig        — attrString, style
  background: BackgroundConfig — style, color, gradientStart/End, angle, opacity, image
  canvasSize: CGSize
```

Update all construction sites in `CollageAssembler` and `CollageViewModel.exportCollage()`.

---

## Item 6: Reduce CollageAssembly Protocol

**Problem:** The protocol has 4 methods, but `assemble` and `assemblePreview` are thin NSImage wrappers around the CGImage variants. Clients only ever call the CGImage methods.

### Modified: `Services/CollageAssembler.swift`

- Protocol reduces to 2 methods: `assembleWithCGImages` and `assemblePreviewWithCGImages`
- NSImage wrappers move to default extension or remain as public convenience methods on the class (outside the protocol)
- Update `MockAssembler` and `TrackingAssembler` to only implement the 2 protocol methods

---

## Item 7: Add Missing Tests

**Problem:** `ScrollPanManager`, `TitleMetrics`, and `FontMerger` have zero test coverage.

### New file: `CollageMakerTests/ScrollPanManagerTests.swift`
- Test delta accumulation
- Test gesture begin/end lifecycle
- Test coordinate transformation

### New file: `CollageMakerTests/TitleMetricsTests.swift`
- Test `prepare()` with various font sizes
- Test with various text lengths
- Test with various canvas widths

### New file: `CollageMakerTests/FontMergerTests.swift`
- Test font trait merging scenarios
- Test edge cases (missing traits, partial traits)

---

## Execution Order

1. **Item 1** — Persistence service (foundation, other items depend on clean VM state)
2. **Item 2** — ExportPanel fix (depends on Item 1)
3. **Item 3** — Test duplication fix (independent, quick win)
4. **Item 4** — FitMath extraction (independent)
5. **Item 5** — AssemblyConfig split (independent)
6. **Item 6** — Protocol reduction (independent)
7. **Item 7** — New tests (independent)

Run full test suite after each item to catch regressions.

## Deferred (Low Priority)

- **Item 8:** Extract ExportCoordinator — move save panel + file write from CollageViewModel
- **Item 9:** Replace Task.sleep in tests — use actor-based completion signaling
- **Item 10:** Consider view model splitting — long-term: extract image loading and export into dedicated services
