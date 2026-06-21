# Session 122 — Round 104: View Menu Toggle for Saliency Overlay

**Date:** 2026-06-21
**Change Request:** round-104.md

## Summary

Promoted the saliency debug overlay from `#if DEBUG`-only to a user-controllable View menu toggle. The overlay is now off by default and can be shown/hidden via **View > Show Saliency Overlay** (Cmd+Shift+H).

## Changes

### ViewModel Property — `ViewModel/CollageViewModel.swift`

Added `showSaliencyOverlay: Bool = false` stored property. No persistence needed — this is a transient UI preference.

### View Menu Toggle — `Views/CollageCommands.swift`

Added `CommandMenu("View")` with a `Toggle` bound to `viewModel.showSaliencyOverlay` via `Binding(get:set:)`. Keyboard shortcut: Cmd+Shift+H.

**Build error:** Initial attempt used `Button` with `.toggle(isOn:)` modifier, which has no member `toggle` on `some View` in command context. Fixed by switching to `Toggle` which provides the checkmark state natively.

### Removed Debug Gates — `Views/PanelCropEditor.swift`

- Removed `#if DEBUG` / `#endif` around the saliency overlay rendering in `CropPreviewView.body` (line 282), replaced with `if showSaliencyOverlay, let saliency`
- Removed `#if DEBUG` / `#endif` around the `saliencyDebugOverlay()` method (line 370)
- Added `showSaliencyOverlay: Bool` parameter to `CropPreviewView` struct
- Passed `viewModel.showSaliencyOverlay` through when instantiating `CropPreviewView`

## Verification

- Build: zero errors, zero warnings
- App launches successfully

## Files Changed

| File | Change |
|------|--------|
| `ViewModel/CollageViewModel.swift` | Added `showSaliencyOverlay: Bool = false` |
| `Views/CollageCommands.swift` | Added `CommandMenu("View")` with `Toggle` |
| `Views/PanelCropEditor.swift` | Removed `#if DEBUG` gates, added `showSaliencyOverlay` parameter |
