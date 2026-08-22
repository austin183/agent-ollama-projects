# Architectural Review Fixes — Implementation Plan

**Review doc:** `_agent_docs/reviews/2026-05-28-full-architectural-review.md`
**Date:** 2026-05-28
**Status:** Session 1 complete, Session 2 complete

---

## Session 1: Quick Fixes + Moderate Refactoring ✅ COMPLETE

All items implemented and verified:
- **1.1 M4**: Documented SaliencyResult portrait coordinate swap with explanatory comment
- **1.2**: Fixed `applyOverlayCrop` no-op reassignment — now writes through `cropManager.cropMap` then reassigns
- **1.3**: Changed `logger.info` to `logger.debug` in CollageEditorView onAppear
- **1.4**: Extracted `buildAssemblyConfig()` helper, used in both `updatePreview()` and `exportCollage()`
- **1.5**: Fixed `perfLogger` subsystem to `"austin183.indie.CollageMaker"`
- **1.6 C2 (Critical)**: Unified cropMap — removed from CollageViewModel, replaced with computed property delegating to `CropManager`. Removed all ~15 manual sync lines.
- **1.7 M3**: `debouncedSave()` now catches and logs persistence errors, surfaces to `errorMessage`
- **1.8 M2**: SettingsView uses `UserDefaultsPersistence.Keys` for all UserDefaults access
- **1.9 M6**: Added `@MainActor` to `CollageCommands`
- **1.10**: Added `FitMathTests` (11 tests: fit and sourceRect with various aspect ratios)
- **1.11**: Added `UserDefaultsPersistenceTests` (12 tests: save/load round-trips for all properties)

**Note:** `CollagePerformanceTests/scrollPreviewUpdatesAssembler` exhibited occasional flakiness (timing-dependent 300ms sleep). Pre-existing issue, not introduced by these changes.

---

## Session 1: Quick Fixes + Moderate Refactoring

### 1.1 — M4: Document SaliencyResult portrait coordinate swap

**File:** `CollageMaker/Models/SaliencyResult.swift:22-25`

Add a comment explaining that Vision's saliency center is in normalized coordinates where portrait images have x/y swapped relative to the source CGImage. The swap compensates for this coordinate system mismatch.

```swift
// Vision's saliency center is in normalized image coordinates.
// For portrait images, the VNImageRequestHandler rotates the buffer
// 90°, causing x/y to be swapped relative to the source CGImage.
// We swap back so the crop origin is correct in CGImage space.
if imageSize.width < imageSize.height {
    originX = center.y - halfW
    originY = center.x - halfH
}
```

### 1.2 — Minor: Fix applyOverlayCrop no-op reassignment

**File:** `CollageMaker/ViewModel/CollageViewModel.swift:699-700`

Replace the `var tmp = cropMap; cropMap = tmp` pattern with a cleaner approach. Since `@Observable` only sees value changes, and the dictionary was already mutated in-place, we need to force reobservation. Best approach: reassign the entire dictionary as a new value.

### 1.3 — Minor: Debug logger in onAppear

**File:** `CollageMaker/Views/CollageEditorView.swift:200`

Change `logger.info("Highlight: panel ...")` to `logger.debug(...)`.

### 1.4 — Minor: Extract buildAssemblyConfig() helper

**File:** `CollageMaker/ViewModel/CollageViewModel.swift`

`AssemblyConfig` is constructed identically in `updatePreview()` (line ~822) and `exportCollage()` (line ~912). Extract to:

```swift
private func buildAssemblyConfig() -> AssemblyConfig {
    AssemblyConfig(
        panels: panels,
        crops: cropMap,
        panelAssignments: panelAssignments,
        titleAttrString: titleAttrString,
        titleStyle: titleStyle,
        backgroundColor: backgroundColor,
        backgroundStyle: backgroundStyle,
        gradientStartColor: gradientStartColor,
        gradientEndColor: gradientEndColor,
        gradientAngle: gradientAngle,
        backgroundOpacity: backgroundOpacity,
        canvasSize: CanvasConfig.defaultCanvasSize
    )
}
```

### 1.5 — Style: Fix perfLogger subsystem

**File:** `CollageMaker/ViewModel/CollageViewModel.swift:13`

Change `Bundle.main.bundleIdentifier!` to `"austin183.indie.CollageMaker"` for consistency with the standard logger.

### 1.6 — C2: Unify cropMap ownership (Critical)

**Files:** `CollageViewModel.swift`, `CropManager.swift`

**Goal:** `CropManager` becomes the sole owner of `cropMap`. `CollageViewModel` no longer holds its own copy.

**Changes:**

1. Remove `var cropMap: [UUID: CropInfo] = [:]` from `CollageViewModel` (line 34).
2. Add a computed property on `CollageViewModel` that delegates to `cropManager.cropMap`:
   ```swift
   var cropMap: [UUID: CropInfo] {
       get { cropManager.cropMap }
       set { cropManager.cropMap = newValue }
   }
   ```
3. Remove all manual sync lines like `cropMap = cropManager.cropMap` (~15 sites):
   - `regenerateLayout()` (line 503)
   - `applyPan()` (line 610)
   - `applyPanLive()` (line 619)
   - `applyPinch()` (line 640)
   - `applyPinchLive()` (line 646)
   - `resetCrop()` (line 668)
   - `applyOverlayCrop()` (line 698)
   - `scrollPanDelta` applyLive closure (line 727)
   - `scrollPanDelta` commit closure (line 747)
   - `analyzeSaliency()` (line 589)
   - `swapPanelImages()` (line 558)
   - `clearAll()` (line 448)
   - Any undo callbacks that reference `cropMap`
4. Update `clearAll()` to call `cropManager.cropMap.removeAll()` instead of `cropMap.removeAll()`.
5. Update undo callbacks that restore `cropMap` — they should write through `cropManager.cropMap`.
6. Update `applyOverlayCrop` to write directly to `cropManager.cropMap` and reassign the full map to trigger `@Observable`.

**Test impact:** `CollageViewModelTests` may need updates where `cropMap` is read/written directly.

### 1.7 — M3: Surface persistence errors

**File:** `CollageMaker/ViewModel/CollageViewModel.swift:220-228`

Replace silent `try?` with proper error handling:

```swift
private func debouncedSave() {
    saveDebounceTask?.cancel()
    let persistence = self.persistence
    saveDebounceTask = Task { [weak self, persistence] in
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard let self else { return }
        do {
            try persistence.save(self)
        } catch {
            logger.error("Persistence save failed: \(error.localizedDescription, privacy: .public)")
            if !Task.isCancelled {
                self.errorMessage = "Failed to save: \(error.localizedDescription)"
            }
        }
    }
}
```

### 1.8 — M2: SettingsView uses centralized UserDefaults keys

**File:** `CollageMaker/Views/SettingsView.swift`

**Current state:** Raw string keys like `"gradientAngle"`, `"backgroundColor"`, `"layoutStyle"`, etc.

**Approach:** Read `UserDefaultsPersistence.Keys` enum to get the canonical key strings, then use those in `@AppStorage` and direct `UserDefaults.standard` calls.

First, check what keys `UserDefaultsPersistence.Keys` defines, then update SettingsView to use those. If `Keys` is not `@Observable`-friendly, add a static helper or make the keys accessible.

Specific changes:
- `@AppStorage("layoutStyle")` → `@AppStorage(UserDefaultsPersistence.Keys.layoutStyle)`
- `@AppStorage("gutter")` → `@AppStorage(UserDefaultsPersistence.Keys.gutter)`
- `@AppStorage("exportQuality")` → `@AppStorage(UserDefaultsPersistence.Keys.exportQuality)`
- `@AppStorage("defaultTitle")` → `@AppStorage(UserDefaultsPersistence.Keys.defaultTitle)`
- `@AppStorage("defaultFontFamily")` → `@AppStorage(UserDefaultsPersistence.Keys.defaultFontFamily)`
- `@AppStorage("defaultFontSize")` → `@AppStorage(UserDefaultsPersistence.Keys.defaultFontSize)`
- `@AppStorage("defaultExportFolder")` → `@AppStorage(UserDefaultsPersistence.Keys.defaultExportFolder)`
- `@AppStorage("backgroundStyle")` → `@AppStorage(UserDefaultsPersistence.Keys.backgroundStyle)`
- `UserDefaultsColorView` keys: `"backgroundColor"` → `UserDefaultsPersistence.Keys.backgroundColor`, etc.
- `UserDefaults.standard.set(newValue, forKey: "gradientAngle")` → use the centralized key
- `UserDefaults.standard.double(forKey: "gradientAngle")` → use the centralized key

### 1.9 — M6: Add @MainActor to CollageCommands

**File:** `CollageMaker/Views/CollageCommands.swift`

Add `@MainActor` to the `CollageCommands` struct declaration for explicit main-actor isolation.

### 1.10 — Tests: FitMathTests

**New file:** `CollageMaker/CollageMakerTests/FitMathTests.swift`

Test `FitMath.fit()` and `FitMath.sourceRect()` with known aspect ratios:
- Square image into square panel (no change)
- Wide image into tall panel (letterbox)
- Tall image into wide panel (pillarbox)
- Exact match
- Verify `sourceRect` returns center-cropped rect for fit-to-fill

### 1.11 — Tests: UserDefaultsPersistenceTests

**New file:** `CollageMaker/CollageMakerTests/UserDefaultsPersistenceTests.swift`

Test save/load round-trip for all persisted properties. Use a fresh `UserDefaults` suite (e.g., `UserDefaults(suiteName: "test-suite")`) to avoid polluting real preferences. Verify each of the 13+ properties survives a round-trip.

---

## Session 2: Major Refactoring

### 2.1 — C1: Extract PreviewManager (Critical)

**Goal:** Extract all preview rendering logic from `CollageViewModel` into a dedicated `PreviewManager` class.

**What moves to PreviewManager:**
- `previewTask`, `previewDebounceTask`, `panelPreviewTask`, `backgroundTask`, `titleTask` (all 5 task vars)
- `updatePreview()` → `renderPreview(config:, cgImages:, backgroundImage:)`
- `updateBackground()` → `renderBackground(...)`
- `updateTitleImage()` → `renderTitle(...)`
- `updatePanelPreview(panelId:)` → `renderPanelPreview(...)`
- `updateAllPanelPreviews()` → `renderAllPanelPreviews(...)`
- State: `previewImage`, `previewBackgroundImage`, `panelRenderedImages`, `titleImage`

**Architecture:**
- `PreviewManager` is `@Observable` + `@MainActor`
- It holds the rendered image state (`previewImage`, etc.)
- `CollageViewModel` delegates rendering calls to it
- `CollageViewModel` still owns the trigger logic (when to call update) but the rendering lifecycle lives in `PreviewManager`
- Protocol-based dependency on `CollageAssembly` for testability

**CollageViewModel changes:**
- Add `let previewManager = PreviewManager(assembler: ...)` in init
- Replace `self.previewImage` with `previewManager.previewImage` (or keep a computed property)
- Replace `updatePreview()` body with a call to `previewManager.updatePreview(...)`
- Pass the config/images/background as parameters rather than capturing from self

**Test impact:** `CollageViewModelTests` mocking of preview output may need adjustment. New `PreviewManagerTests` can verify task lifecycle, cancellation, and race conditions.

### 2.2 — C3: RenderQueue actor for NSGraphicsContext thread safety (Critical)

**New file:** `CollageMaker/Services/RenderQueue.swift`

**Goal:** Serialize all rendering operations that use `NSGraphicsContext.current` through an actor.

```swift
actor RenderQueue {
    func render(_ work: @Sendable () -> NSImage?) -> NSImage? {
        work()
    }
}
```

**Changes to CollageAssembler:**
- Add a static or shared `RenderQueue` instance
- Wrap all rendering methods (`assembleWithCGImages`, `assemblePreviewWithCGImages`, `renderPanel`, `renderBackground`, `renderTitle`) to execute through the queue
- Since `CollageAssembly` is a protocol, the queue can live in the concrete `CollageAssembler` class

**Changes to CollageViewModel / PreviewManager:**
- The `Task.detached` calls in preview updates already run off-main-actor, but now they'll serialize through the actor before touching `NSGraphicsContext.current`

**Alternative (simpler):** Since each `Task.detached` creates its own `NSBitmapImageRep` and sets `NSGraphicsContext.current` to a new context for that bitmap, the actual risk is lower than it appears — each task has its own isolated context. The `saveGraphicsState()` / `restoreGraphicsState()` calls are per-task. If we confirm this analysis, we can add a `SerialQueue` wrapper as a belt-and-suspenders measure rather than a full actor refactor.

**Decision needed:** After reviewing the rendering code more carefully, the `NSGraphicsContext.current` is set to a *new* context per render call (line 187: `NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)`). The `saveGraphicsState()` / `restoreGraphicsState()` bracket each call. The real risk is if two tasks interleave *between* the save and the assignment of `current`, causing one task's `current` to be clobbered. A serial dispatch queue is sufficient:

```swift
private let renderQueue = DispatchQueue(label: "austin183.indie.CollageMaker.render")
```

Wrap each rendering method's body in `renderQueue.sync { ... }`.

### 2.3 — M1: Decouple ScrollPanManager from crop internals

**File:** `CollageMaker/ViewModel/CollageViewModel.swift:707-750`

**Current state:** The `scrollPanDelta` callback captures `cropManager`, `panels`, `images`, `panelAssignments`, and `cropMap` directly. The `applyLive` and `commit` closures perform crop computation inside the scroll pan callback.

**Refactor:**
- `ScrollPanManager` already emits raw deltas via `accumulator` — that's good
- The ViewModel's `scrollPanDelta` method should keep the crop computation but not pass it *into* `ScrollPanManager`
- Currently the closures are passed *to* `scrollPanManager.scrollPanDelta()` — that's the coupling
- Invert: Have `ScrollPanManager` just accumulate and report. The ViewModel calls `applyLive` and `commit` itself based on the manager's state.

**New flow:**
```swift
func scrollPanDelta(_ delta: CGSize) {
    scrollPanManager.scrollPanDelta(delta, sensitivity: scrollSensitivity)
    
    // Apply live crop from accumulator
    cropManager.pan(by: scrollPanManager.accumulator)
    cropManager.applyPan(panelId: nil, panels: panels, images: images, panelAssignments: panelAssignments, finish: false)
    
    // Debounced preview update
    previewDebounceTask?.cancel()
    previewDebounceTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: 150_000_000)
        if let panelId = self?.scrollPanManager.activePanelId {
            self?.updatePanelPreview(panelId: panelId)
        }
    }
    
    // Schedule commit via timer
    scheduleScrollPanCommit()
}

private func scheduleScrollPanCommit() {
    // ... timer-based commit that finalizes the crop
}
```

This moves the commit timer logic into the ViewModel (or keeps it in ScrollPanManager but with a simpler callback that doesn't take crop-capturing closures).

### 2.4 — Tests: PreviewManagerTests

**New file:** `CollageMaker/CollageMakerTests/PreviewManagerTests.swift`

Verify:
- Preview task cancellation on rapid calls
- Rendered images are set on main actor
- `MockAssembler` integration works correctly
- Background, title, and panel previews render independently

### 2.5 — Tests: RenderQueue / CollageAssembler thread safety

**File:** `CollageMaker/CollageMakerTests/CollageAssemblerTests.swift` (add tests)

Add concurrent rendering tests:
- Fire 10 concurrent `assemblePreviewWithCGImages` calls
- Verify all complete without corruption (non-nil results)
- Verify `renderQueue.sync` serializes correctly

---

## Deferred (explicitly out of scope for now)

- M5: ImageItem memory retention — defer until memory pressure is observed
- Nit: PanelCropEditor 408 lines — extract `CropResizeCalculator`
- Nit: AttributedStringEditor toggle duplication — extract `toggleFontTrait`
- Nit: FontPickerPopover eager font loading — lazy rendering
- Nit: TitleMetrics `boundingBox` recomputation — caching with invalidation
- Nit: CollageAssembler duplicate code (`assembleWithCGImages` vs `assemblePreviewWithCGImages`) — extract shared rendering
- C1 follow-up: `LayoutManager` and `ExportManager` extraction after `PreviewManager` proves the pattern

---

## Verification Checklist

After each session:

```bash
# Build
bash script/build_and_run.sh --verify

# Unit tests
xcodebuild test -project CollageMaker/CollageMaker.xcodeproj -scheme CollageMaker -destination 'platform=macOS,arch=arm64' -only-testing:CollageMakerTests

# Smoke test: launch and verify no crashes
bash script/build_and_run.sh run
```
