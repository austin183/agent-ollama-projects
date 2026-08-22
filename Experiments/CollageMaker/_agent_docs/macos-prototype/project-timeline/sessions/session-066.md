# Arch Review Phase 3 — Major Restructuring — Session 66

**Date:** 2026-05-30
**Plan:** `_agent_docs/plans/2026-05-29-architectural-review-fixes.md` (Phase 3)

## Changes

### 3.1 — C1: Extract ExportManager from CollageViewModel
New `ViewModel/ExportManager.swift` — `@MainActor @Observable` class owning `isExporting`, `successMessage`, `exportTask`, and the full export flow (save panel, assembly orchestration, file I/O). CollageViewModel delegates via `exportManager` property with backward-compatible computed properties (`isExporting`, `exportSuccessMessage`) for existing views. `buildAssemblyConfig()` promoted from `private` to `func` for ExportManager access.

### 3.2 — C1: Extract ImageLibraryManager from CollageViewModel
New `ViewModel/ImageLibraryManager.swift` — `@MainActor @Observable` class owning `images`, `customImageOrder`, and all image operations (`browseImages`, `addImages`, `removeImage`, `moveImages`, `clearAll`). Includes `onImagesChanged` callback to trigger `regenerateLayout()`. CollageViewModel exposes `images` and `customImageOrder` as computed properties. Thin wrapper methods in VM handle undo registration and saliency re-analysis.

### 3.3 — M4: Extract GestureCoordinator from CollageEditorView
New `Views/GestureCoordinator.swift` — `ObservableObject` with `@Published` properties for 8 gesture-tracking state variables (`pinchPanelId`, `dragTitleLocked`, `titleResizeEdge`, `dragSourcePanelId`, `dragTargetPanelId`, `dragCursorLocation`, `dragSourceImageIndex`, `oldTitleStyle`, `dragTitleOffset`). `TitleResizeEdge` promoted from `private` to file-level `enum`. CollageEditorView replaces 8 `@State` vars with single `@StateObject`.

### 3.4 — M2: Document Settings defaults semantics
Added doc comment to `SettingsView` clarifying that settings store defaults for new sessions only and do not affect the active CollageViewModel.

## View & Test Updates
- **ContentView**: `viewModel.images` → `viewModel.imageLibrary.images` (7 sites)
- **ExportPanel**: `isExporting`/`exportSuccessMessage` → `exportManager` property access (4 sites)
- **CollageEditorView**: `viewModel.images` → `viewModel.imageLibrary.images` (2 sites)
- **PanelCropEditor**: `viewModel.images` → `viewModel.imageLibrary.images` (2 sites)
- **Test files**: `vm.images` → `vm.imageLibrary.images` across CollageViewModelTests, ExportFlowTests, CollagePerformanceTests

## Build & Test
- Build: succeeded (zero errors, zero warnings)
- All 167+ unit tests passing
