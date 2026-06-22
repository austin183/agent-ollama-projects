# Session 124 — FPS Consistency + Centralized Timing + Save-on-Quit

**Date:** 2026-06-21
**Plan:** `2026-06-21-animation-fps-consistency.md` Phase 1

## Summary

Implemented Phase 1 of the FPS consistency plan: aligned all gesture-driven rendering to ~60fps (16ms interval). Extracted all timing constants into a centralized `FrameTempo` enum. Removed continuous auto-save to UserDefaults, replacing with single save on app quit via `NSApplication.willTerminateNotification`.

## Changes

### Phase 1 — FPS Consistency

Aligned three render intervals in `CollageViewModel.swift` from disparate values to 16ms:

| Gesture | Before | After |
|---------|--------|-------|
| Scroll pan render | 60ms (~16fps) | 16ms (~60fps) |
| Pan preview debounce | 150ms (~6fps) | 16ms (~60fps) |
| Overlay crop render | 50ms (~20fps) | 16ms (~60fps) |

### Centralized Timing — FrameTempo

Created `ViewModel/FrameTempo.swift` with 11 timing constants organized into three groups: gesture render throttles, gesture preview debounces, and post-interaction debounces. Replaced all 11 `.milliseconds(N)` call sites in `CollageViewModel.swift` with `FrameTempo.*` references. Removed two inline `private let` interval properties.

**Design decision:** Header doc comment contains an ms-to-fps reference table decoupled from actual values, so comments stay correct when values change.

### Save-on-Quit

Removed 13 `debouncedSave()` calls from `CollageViewModel.swift`, 1 from `ContentView.swift`, 1 from `TitleManager.finishDrag()`. Removed `debouncedSave()` from `PreviewUpdatable` protocol. Replaced with `saveSettings()` on `CollageViewModel` and a single `NSApplication.willTerminateNotification` observer in `ContentView.swift`.

**Build error:** `.onExit` modifier does not exist on macOS SwiftUI views. `NSApplicationDelegateAdapter` also not available in this SDK. Resolved with a `.task` that adds a `NotificationCenter` observer for `NSApplication.willTerminateNotification`, sleeps forever, and removes the observer on cancellation.

### User-Tuned Values

User adjusted `FrameTempo` values for feel: most intervals to 20ms (~50fps, reduced CPU), pinch to 10ms, font size to 6ms (~167fps).

## Verification

- Build: zero errors, zero warnings
- diff-review-g31: clean

## Files Changed

| File | Change |
|------|--------|
| `ViewModel/FrameTempo.swift` | New — centralized timing constants enum |
| `ViewModel/CollageViewModel.swift` | All `.milliseconds(N)` → `FrameTempo.*`, removed `debouncedSave()`, added `saveSettings()` |
| `ViewModel/PreviewUpdatable.swift` | Removed `debouncedSave()` from protocol |
| `ViewModel/TitleManager.swift` | Removed `updater.debouncedSave()` from `finishDrag()` |
| `ContentView.swift` | Removed `debouncedSave()`, added `willTerminateNotification` observer |
