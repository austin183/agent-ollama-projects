# Session 123 — Round 105: Resizable Right Drawer + Flicker Fix

**Date:** 2026-06-21
**Change Request:** round-105-resize-right-drawer.md

## Summary

Implemented a visible resize handle between the editor and right detail panel with `DragGesture`, `UserDefaults` persistence, and smooth interaction. Two iterations: initial implementation caused flicker during drag; fixed by extracting resize state into a self-contained `ResizableDrawer` struct to isolate SwiftUI body re-evaluations.

## Changes

### Iteration 1 — Initial Implementation

**Persistence** (`UserDefaultsPersistence.swift`): Added `rightDrawerWidth` key, `PersistenceBundle` field, save/load with 300pt default.

**ViewModel** (`CollageViewModel.swift`): Added `rightDrawerWidth: CGFloat = 300` stored property, initialized from bundle.

**View** (`ContentView.swift`): Added `@State` for gesture tracking, `resizeHandle` computed property with `DragGesture`, wired `HStack` with handle + fixed-width detail panel.

**Build error**: `.cursor(.resizeLeftRight)` does not exist in macOS SwiftUI. Replaced with `NSCursor.resizeLeftRight.push()` / `NSCursor.pop()` in `onHover`.

### Iteration 2 — Flicker Fix

**Root cause**: Every `onChanged` tick set `viewModel.rightDrawerWidth`, firing `objectWillChange` on the `@Observable` ViewModel. This invalidated all `@Bindable` observers, including `ContentView` and its `CollageEditorView` child — triggering ~60 full body re-evaluations per drag, including `GeometryReader` closures and all panel overlays. Worse on hexagonal layout due to complex polygonal `PanelShape` views.

**Attempt 1 — Local `@State`**: Moved width to `@State` on `ContentView`. Still flickered — `@State` mutation on `ContentView` invalidated `ContentView.body`, which includes `CollageEditorView`.

**Fix — Struct isolation**: Extracted resize state and logic into a self-contained `ResizableDrawer` struct. Drag ticks now only invalidate `ResizableDrawer.body`, never `ContentView.body`. `CollageEditorView` is never re-evaluated during drag — only re-laid out by the `HStack` frame change.

## Verification

- Build: zero errors, zero warnings
- App launches successfully

## Files Changed

| File | Change |
|------|--------|
| `Services/UserDefaultsPersistence.swift` | `rightDrawerWidth` key, bundle field, save/load |
| `ViewModel/CollageViewModel.swift` | `rightDrawerWidth` property, init from bundle |
| `ContentView.swift` | `ResizableDrawer` struct with isolated `@State`, handle gesture, `NSCursor` hover |
