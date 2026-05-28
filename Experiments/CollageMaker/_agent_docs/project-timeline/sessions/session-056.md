# Session 56 — 2026-05-27

### Round 18 — Per-Panel Incremental Rendering

**Goal:** Replace full-canvas composite during live pan/zoom gestures with per-panel incremental rendering, reducing wasted work when only one panel's `sourceRect` changes.

**Source:** `_agent_docs/plans/2026-05-27-round-18-per-panel-rendering.md`

---

## Problem

Every pan/zoom gesture triggered `updatePreview()`, which composites the entire 1920×1080 canvas (background + all panels + title) into a single `NSImage`, then scales to 960×540 for display. The scroll pan path (`scrollPanDelta`) called `updatePreview()` synchronously with no debounce — the hottest code path during interaction.

## Solution

Layered rendering architecture in `CollageEditorView`:

| Layer | Content | Re-renders when |
|---|---|---|
| Background | Solid/gradient/image | Background settings change |
| Per-panel images | Each panel's cropped image | That panel's `sourceRect` changes |
| Full composite with title | Shown at gesture end, fallback during initial load | Layout change, gesture end, initial load |

Live gestures render only the affected panel via `renderPanel()` with 150ms debounce. Gesture end clears per-panel cache and runs full `updatePreview()` to restore title.

## Changes

### CollageAssembler — New rendering methods

Added to `CollageAssembly` protocol and `CollageAssembler`:

- `renderPanel(crop:cgImage:panelSize:)` — Creates a CGContext at panel `destinationRect` size, crops source image, returns `NSImage`. Hot path for live gestures.
- `renderBackground(config:canvasSize:backgroundImage:previewSize:)` — Draws just the background layer at canvas size, returns scaled `NSImage`. Called when background settings change.

### CollageViewModel — New state and methods

**New stored properties:**
- `previewBackgroundImage: NSImage?` — rendered background layer
- `panelRenderedImages: [UUID: NSImage]` — per-panel rendered images
- `isLiveGesturing: Bool` — controls title visibility during gestures

**New methods:**
- `updatePanelPreview(panelId:)` — resolves effective image index, gets `CropInfo`, calls `assembler.renderPanel()` on detached task, dispatches result to main actor
- `updateBackground()` — renders background via `assembler.renderBackground()` on detached task
- `updateAllPanelPreviews()` — populates all panel renders after layout regeneration

**Modified methods:**
- `applyPanLive()` — calls `updatePanelPreview` with 150ms debounce instead of full `updatePreview`
- `applyPinchLive()` — calls `updatePanelPreview` with 150ms debounce instead of full `updatePreview`
- `scrollPanDelta` applyLive closure — calls `updatePanelPreview` with 150ms debounce (previously had none)
- `updatePreview()` — also calls `updateBackground()` to keep background layer current
- `regenerateLayout()` — clears `panelRenderedImages`, calls `updateAllPanelPreviews()`
- `clearAll()` — clears `previewBackgroundImage` and `panelRenderedImages`

### CollageEditorView — Layered composition

Replaced single `Image(nsImage: previewImage)` with conditional ZStack:
- When `panelRenderedImages` is empty: falls back to full `previewImage` (initial load, gesture end)
- When populated: background image + per-panel images positioned via `canvasToPreviewFrame`

Gesture begin sets `isLiveGesturing = true`, gesture end sets `false`, clears `panelRenderedImages`, and runs full `updatePreview()` to restore title.

### CropManager

Exposed `activePanelId` computed property so ViewModel can identify the gesturing panel for targeted re-render.

### Tests

- Updated `TrackingAssembler` mock with `renderPanelCalls`, `renderBackgroundCalls` counters
- Updated `MockAssembler` mock with stub implementations
- Updated `scrollPreviewUpdatesAssembler` test to assert `renderPanelCalls` instead of `previewCalls`

## Files Changed

| File | Change |
|---|---|
| `Services/CollageAssembler.swift` | Added `renderPanel`, `renderBackground` to protocol + class |
| `ViewModel/CollageViewModel.swift` | New state, `updatePanelPreview`, `updateBackground`, `updateAllPanelPreviews`, modified gesture handlers |
| `ViewModel/CropManager.swift` | Exposed `activePanelId` |
| `Views/CollageEditorView.swift` | Layered ZStack, `isLiveGesturing` wiring, gesture end full composite |
| `CollageMakerTests/ExportFlowTests.swift` | `TrackingAssembler` mock extended |
| `CollageMakerTests/CollageViewModelTests.swift` | `MockAssembler` mock extended |
| `CollageMakerTests/CollagePerformanceTests.swift` | Updated scroll test for `renderPanelCalls` |

## Build and Test Status

- **Build:** Succeeded — zero errors, 2 pre-existing warnings untouched
- **Tests:** All unit tests passing (152 total), 0 failures
