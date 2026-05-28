# Session 58 — 2026-05-28

### Full Architectural Review Fixes — Session 1 (Phases 1-2)

**Goal:** Address all quick fixes, moderate issues, and one critical issue from the full architectural code review. Add new test coverage for previously untested components.

**Source:** `_agent_docs/reviews/2026-05-28-full-architectural-review.md`, `_agent_docs/plans/2026-05-28-architectural-review-fixes.md`

---

## Changes

### C2 (Critical) — Unify cropMap ownership

Eliminated dual `cropMap` state between `CollageViewModel` and `CropManager`. `CropManager` is now the sole owner. `CollageViewModel` exposes `cropMap` as a computed property that delegates to `cropManager.cropMap`. Removed all ~15 manual sync lines (`cropMap = cropManager.cropMap`) scattered across `regenerateLayout`, `applyPan`, `applyPanLive`, `applyPinch`, `applyPinchLive`, `resetCrop`, `applyOverlayCrop`, `scrollPanDelta`, `analyzeSaliency`, `swapPanelImages`, and `clearAll`.

### M3 (Moderate) — Surface persistence errors

`debouncedSave()` now catches persistence errors with `try/catch` instead of silently swallowing them with `try?`. Errors are logged at error level and surfaced to `errorMessage` for user visibility.

### M2 (Moderate) — SettingsView uses centralized UserDefaults keys

All raw string keys in `SettingsView` replaced with `UserDefaultsPersistence.Keys` enum values: `layoutStyle`, `gutter`, `exportQuality`, `defaultTitle`, `defaultFontFamily`, `defaultFontSize`, `defaultExportFolder`, `backgroundStyle`, `backgroundColor`, `gradientStartColor`, `gradientEndColor`, `gradientAngle`.

### M4 (Moderate) — Document SaliencyResult portrait coordinate swap

Added explanatory comment in `SaliencyResult.cropOrigin` documenting that Vision's `VNImageRequestHandler` rotates portrait buffers 90°, causing x/y swap relative to the source CGImage.

### M6 (Moderate) — Add @MainActor to CollageCommands

Added `@MainActor` annotation to `CollageCommands` struct for explicit main-actor isolation.

### Minor fixes

- **perfLogger subsystem:** Changed from `Bundle.main.bundleIdentifier!` to `"austin183.indie.CollageMaker"` for consistency
- **applyOverlayCrop no-op reassignment:** Removed `var tmp = cropMap; cropMap = tmp` pattern — writes through `cropManager.cropMap` directly
- **buildAssemblyConfig helper:** Extracted to deduplicate identical `AssemblyConfig` construction in `updatePreview()` and `exportCollage()`
- **Debug logger in onAppear:** Changed `logger.info` to `logger.debug` in `CollageEditorView` highlight view

### Tests added

- **FitMathTests** (11 tests): `fit()` — square-to-square, wide-into-square, tall-into-square, square-into-wide, square-into-tall, aspect ratio preservation, never exceeds container; `sourceRect()` — square/square, wide/tall, tall/wide, aspect preservation, centering
- **UserDefaultsPersistenceTests** (12 tests): Individual save/load round-trips for layoutStyle, gutter, exportQuality, backgroundStyle, gradientAngle, backgroundOpacity, title, customImageOrder, backgroundColor, gradientColors; defaults when nothing saved; full round-trip with all properties

### Post-session fix — Panel Editor overlay not updating

Discovered that the cropMap unification broke live overlay updates in `PanelCropEditor`. Root cause: `cropMap` is a computed property delegating to `cropManager.cropMap`, but `CropManager` wasn't `@Observable`, so SwiftUI couldn't track mutations during drag. Fix: added `@Observable` to `CropManager`, updated `PanelCropEditor` to read `viewModel.cropManager.cropMap` directly to establish the observation dependency.

## Files Changed

| File | Change |
|---|---|
| `Models/SaliencyResult.swift` | Added comment for portrait coordinate swap |
| `ViewModel/CollageViewModel.swift` | Removed stored `cropMap`, added computed property, removed ~15 sync lines, extracted `buildAssemblyConfig()`, fixed `applyOverlayCrop`, surface persistence errors, fixed perfLogger |
| `ViewModel/CropManager.swift` | Added `@Observable` macro |
| `Views/CollageEditorView.swift` | `logger.info` → `logger.debug` in onAppear |
| `Views/CollageCommands.swift` | Added `@MainActor` |
| `Views/SettingsView.swift` | All raw keys → `UserDefaultsPersistence.Keys` |
| `Views/PanelCropEditor.swift` | Read `cropManager.cropMap` directly for observation |
| `CollageMakerTests/FitMathTests.swift` | New — 11 tests |
| `CollageMakerTests/UserDefaultsPersistenceTests.swift` | New — 12 tests |

## Build and Test Status

- **Build:** Succeeded — zero errors
- **Tests:** All unit tests passing (172+ total), 0 failures
