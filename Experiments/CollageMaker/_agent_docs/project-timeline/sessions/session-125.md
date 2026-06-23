# Session 125 — Review Fixes Phase 1

**Date:** 2026-06-23
**Plan:** `2026-06-23-review-fixes-plan.md` Phase 1

## Summary

Implemented Phase 1 of the review fixes plan addressing 4 low-risk issues from Marcos and Victoria architectural reviews. All changes are self-contained, single-file fixes. Build passes, all tests pass (3 pre-existing failures unrelated).

## Changes

### C2 — BackgroundRenderer renderBackground previewSize

**File:** `Services/BackgroundRenderer.swift`

Fixed `renderBackground` to create the bitmap context at `previewSize` instead of `canvasSize`, with a `context.scaleBy` transform so drawing at `canvasSize` coordinates produces correctly scaled output. Returns `NSImage` at `previewSize`. Mirrors the existing pattern in `CollageAssembler.renderPreviewIntoContext` (session 071).

### C4 — Debouncer deinit

**File:** `ViewModel/Debouncer.swift`

Added `deinit` that cancels pending tasks to prevent dangling captures when `CollageViewModel` is deallocated. Inlined `tasks.values.forEach { $0.cancel() }` instead of calling `cancelAll()` because `deinit` runs outside `@MainActor` isolation.

### R15 — @MainActor on TitleTextData.extract

**File:** `Services/TitleRendererCT.swift`

Added `@MainActor` annotation to `TitleTextData.extract(from:)` to enforce compiler-checked isolation. The method accesses `NSFont` (MainActor-only) and the doc comment already stated "Must be called on the main actor" — now enforced by the compiler.

### R17 — exportManager IUO elimination

**File:** `ViewModel/CollageViewModel.swift`

Changed `var exportManager: ExportManager!` to `private let exportManager: ExportManager`. The IUO was unnecessary since the property is initialized in `init` and never reassigned.

## Verification

- Build: succeeded
- Tests: all pass (3 pre-existing failures: `FontMergerTests/veryLargeTargetSize`, `FontMergerTests/emptyFamilyReturnsBoldSystemFont`, `TitleManagerTests/finishDragCancelsDebouncerAndSaves`)
- diff-review-g31: clean

## New Learnings

- **deinit actor isolation** — `deinit` runs outside any actor isolation, even for `@MainActor` classes. Cannot call `@MainActor`-isolated methods from `deinit`. Must inline `Sendable` operations (e.g., `Task.cancel()`) directly.

---
**Status**: Closed
**Follow-up**: Phase 2 (C0, C1) next
