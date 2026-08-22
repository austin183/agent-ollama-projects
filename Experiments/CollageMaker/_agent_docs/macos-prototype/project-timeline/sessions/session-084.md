# Arch Review Phase 4 Polish — Session 84

**Date:** 2026-06-05
**Plan:** `2026-06-04-architectural-review-fixes.md` Phase 4 (13 of 16 items, 3 deferred per plan)

## Context

Implemented Phase 4 polish items from the architectural review — cross-cutting code quality improvements spanning models, views, services, and tests.

## Changes Implemented

### 4.2 S-4: Deduplicate NSColorPickerView → ColorWellView.swift

Created `Views/ColorWellView.swift` as shared `NSViewRepresentable` for `NSColorWell`. Removed 38-line `NSColorPickerView` private struct from `ExportPanel.swift`. ExportPanel now references `ColorWellView` for all 5 color wells (background color, gradient start/end, title color, title background).

### 4.3 S-5: @unchecked Sendable justification comments

Added safety comments to `LayoutConfig`, `TitleConfig`, and `AssemblyConfig` extensions documenting which non-Sendable properties they contain and why the conformance is safe.

### 4.4 S-6: Precompute panelFrames in CollageEditorView

`panelAt()` now receives `panelFrames: [UUID: CGRect]` instead of computing them internally. Frames computed once inside `GeometryReader` closure, passed to all 4 call sites (drag start, drag change, drag end, tap). Eliminated redundant `canvasToPreviewFrame` calls.

### 4.5 S-7: Move undo registration from View to ViewModel

Added three helper methods to `CollageViewModel`:
- `beginGestureUndo()` — wraps `undoManager.beginUndoGrouping()`
- `endGestureUndo(actionName:)` — wraps `setActionName` + `endUndoGrouping`
- `registerTitleStyleUndo(oldStyle:)` — wraps `registerUndo` + `setActionName`

Updated `CollageEditorView` call sites: scroll pan begin/end, pinch begin/end, title drag end.

### 4.6 S-8: Extract search filtering extension

Created `Models/ImageItem+Filtering.swift` with `func indexed(by query: String)` on `[ImageItem]`. Updated `ContentView` and `ImagePickerGrid` to use `.indexed(by: searchQuery)` instead of inline `enumerated().filter().map()`.

### 4.7 S-9: Store single image repr in ImageItem

Removed stored `nsImage: NSImage` property. Added computed `var nsImage: NSImage { NSImage(cgImage: cgImage, size: size) }`. Updated `ImageLibraryManager` init call and `TestHelpers.createTestImageItem`. Single remaining caller (`PanelCropEditor.swift:33`) uses computed property transparently.

### 4.9 S-11: NaN/infinity guards in FitMath

Added `.isFinite` checks to both `computeFitSourceRect` and `computeBestFitSource` guards alongside existing `> 0` checks.

### 4.10 S-12: Fix deprecated noneSkipFirst

Changed `CGImageAlphaInfo.noneSkipFirst` to `noneSkipLast` in `ImageLibraryManager` thumbnail rendering. Equivalent on little-endian Apple Silicon.

### 4.12 S-14: Split LoggingExtensions.swift

Deleted `LoggingExtensions.swift` (104 lines). Created:
- `Services/DebugHelpers.swift` — `rectStr`, `pointStr`, `sizeStr` helpers
- `Services/NSColor+Hex.swift` — `rgbaHex` getter and `init(rgbaHex:)`

### 4.13 S-15: Split SaliencyResult.cropOrigin

**Attempted, then reverted.** The plan's `toImageSpace` method multiplied `center.x * imageSize.width`, but `SaliencyResult.center` is already in pixel coordinates (set by `SaliencyAnalyzer` at line 56: `box.midX * CGFloat(width)`). The double-multiplication produced huge values that clamped to image edges, causing all crops to start at the bottom corner. Reverted to original code.

### 4.14 S-16: Fix TitleStyle.LayoutKey visibility

Removed `public` from `LayoutKey` struct and its `init`. Changed `var layoutKey` from `public` to internal.

### 4.15 S-17: Rename CanvasConfig → SizeConstants

Renamed `CanvasConfig` to `SizeConstants` across 12+ call sites in main code and 8 test files. Deleted `CanvasConfig.swift`, created `SizeConstants.swift`. Added computed `canvasAspect` and `canvasToPreviewScale` properties.

### 4.16 S-18: Rename SplitMix64 → SeededPRNG

Renamed `SplitMix64` to `SeededPRNG` in `LayoutGenerator.swift`. Removed `RandomNumberGenerator` conformance (PRNG is called via manual `next()`, not protocol methods).

## Deferred Per Plan

- **4.1 S-3** (TitleRendererCT Sendable audit) — defer unless profiling shows problem
- **4.8 S-10** (remove `@MainActor` from TitleDragHandler) — low priority
- **4.11 S-13** (add `file:` private parameter) — defer if time-constrained

## Build Status

**BUILD SUCCEEDED** — Zero warnings. App launches successfully.

**diff-review**: No issues found across all changes.

## Files Changed

- `Views/ColorWellView.swift` — New file, shared NSColorWell wrapper
- `Views/ExportPanel.swift` — Replaced NSColorPickerView with ColorWellView
- `Models/AssemblyConfig.swift` — Added @unchecked Sendable comments
- `Views/CollageEditorView.swift` — panelFrames precomputation, undo helper calls
- `ViewModel/CollageViewModel.swift` — Undo helper methods
- `Models/ImageItem+Filtering.swift` — New file, search extension
- `ContentView.swift` — Used .indexed(by:) extension
- `Views/ImagePickerGrid.swift` — Used .indexed(by:) extension
- `Models/ImageItem.swift` — nsImage stored → computed
- `ViewModel/ImageLibraryManager.swift` — Updated ImageItem init, noneSkipLast fix
- `Services/FitMath.swift` — NaN/infinity guards
- `Services/DebugHelpers.swift` — New file, debug string helpers
- `Services/NSColor+Hex.swift` — New file, hex encoding/decoding
- `Models/SaliencyResult.swift` — Reverted toImageSpace (pixel coord bug)
- `Models/TitleStyle.swift` — LayoutKey visibility fix
- `Models/SizeConstants.swift` — New file (replaces CanvasConfig)
- `Services/LayoutGenerator.swift` — SeededPRNG rename
- `Tests/TestHelpers.swift` — ImageItem init, SizeConstants
- `Tests/*Tests.swift` (8 files) — SizeConstants rename
