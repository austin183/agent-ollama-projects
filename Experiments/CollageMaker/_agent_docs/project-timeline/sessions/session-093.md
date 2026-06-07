# Session 93 — Round-99 Phase 4: Double Exposure Polish + Style-Specific Sidebar Controls

**Date:** 2026-06-07
**Status:** Complete — double exposure mask image persistence + style-specific UI controls

## What Was Done

### Phase 4: Mask Image Persistence

**Goal:** Persist `doubleExposureMaskImage` across app restarts so the mask survives close/reopen cycles.

**Changes:**
- `UserDefaultsPersistence.swift`: Added `doubleExposureMaskImagePath` key to `Keys` enum, `doubleExposureMaskImage`/`doubleExposureMaskImagePath` fields to `PersistenceBundle`, `loadDoubleExposureMaskImage()` helper (mirrors `loadBackgroundImage()`), save logic in `save()` to persist/clear mask path
- `CollageViewModel.swift`: Added `doubleExposureMaskImagePath: String?` stored property. Updated `doubleExposureMaskImage.didSet` to clear path on `nil` (matching `backgroundImage` pattern). Added `setMaskImage(_:path:)` convenience method. Wired both mask image and path from `PersistenceBundle` in `init()`.

### Style-Specific Sidebar Controls

**Discovery:** No UI existed for choosing the double exposure mask image, adjusting `diagonalSliceAngle`, or adjusting `hexagonalSpacing`. The plan called out "UI for mask selection" as remaining work.

**Changes:**
- `ContentView.swift`: Added conditional controls in the sidebar Layout section that appear only when the corresponding layout style is selected:
  - **Double Exposure:** "Choose Mask" button with thumbnail preview, remove button, "Mask Opacity" slider (0–100%)
  - **Diagonal Slices:** "Slice Angle" slider (5°–85°)
  - **Hexagonal:** "Hex Spacing" slider (0–30pt)
- Added `chooseMaskImage()` private method using `NSOpenPanel` (mirrors `ExportPanel.chooseBackgroundImage()`)

## Files Changed

| File | Changes |
|------|---------|
| `Services/UserDefaultsPersistence.swift` | Mask image path key, save/load, `loadDoubleExposureMaskImage()` helper, `PersistenceBundle` fields |
| `ViewModel/CollageViewModel.swift` | `doubleExposureMaskImagePath` property, `didSet` path cleanup, `setMaskImage()` method, init wiring |
| `Views/ContentView.swift` | Style-specific sidebar controls (3 conditional blocks), `chooseMaskImage()` file picker |

## Verification

- `bash script/build_and_run.sh --verify` — BUILD SUCCEEDED
- diff-review agent: no issues found

## Key Decisions

- **Follow existing `backgroundImage` pattern exactly** — The image+path persistence pair, `loadDoubleExposureMaskImage()` helper, `setMaskImage()` convenience method, and `didSet` cleanup all mirror the established `backgroundImage`/`backgroundImagePath` pattern. No new patterns introduced.
- **Conditional sidebar controls** — Rather than a separate detail panel, style-specific controls appear inline in the sidebar Layout section. This keeps the UI compact and avoids a new view file.
- **`chooseMaskImage()` in ContentView, not ExportPanel** — The mask picker is a layout-style control, not an export concern. Placing it in ContentView keeps it alongside the layout style picker.

## Issues Encountered

None — straightforward implementation following existing patterns.

---
**Status:** Complete
**Follow-up:** Continue Round-99 Phase 5 (CropInfo persistence verification) and Phase 6 (sidebar preview path clipping)
