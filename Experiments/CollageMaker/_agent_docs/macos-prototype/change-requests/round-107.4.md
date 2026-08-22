# Slice Angle Slider — Full Layout Regeneration on Every Slider Tick with Blank Canvas

**Date**: 2026-06-27
**Issue**: When dragging the diagonal slice angle slider, there is a long pause followed by a blank images canvas. The preview does not update panels responsively — during slider drags, users see an empty/blank canvas where previously there were image panels. The app feels unresponsive or broken while adjusting this parameter.

## What Happens Today

1. User drags the "Diagonal slice angle" slider in `LayoutConfigSidebar.swift:73-86` (range 0...75°, step 1°)
2. Slider fires continuous value changes bound to `viewModel.setDiagonalSliceAngle($0)`
3. The setter at `CollageViewModel.swift:189-196` calls `layoutManager.setDiagonalSliceAngle(value)` then immediately invokes `regenerateLayout(preserveCrops: false)` — **no debouncing**, unlike the gutter slider which uses `debouncer.debounce(id: "gutter", delay: FrameTempo.layoutChangeDebounce, ...)`
4. The regeneration path at `CollageViewModel.swift:625-653` calls `layoutManager.regenerateLayout(...)` followed by `updateAllPanelPreviews()`
5. `LayoutManager.regenerateLayout` (`LayoutManager.swift:34-82`) regenerates all panel geometry via `DiagonalSlicesLayoutStrategy` with new shear transforms, then discards existing crops and recomputes from scratch using Vision-based saliency analysis (because `preserveCrops: false`)
6. New panel geometry generates immediately but `updateAllPanelPreviews()` is the last operation — during this window panels exist with no rendered images = **blank canvas**
7. Main-thread CoreGraphics work and Vision saliency analysis block the UI thread, causing the long pause

Dragging from 0° to 75° fires ~75 full layout regenerations + saliency re-analyses with no throttling.

## Why It's Problematic

**Severe over-triggering**: The system performs a complete layout regeneration (geometry + crop recomputation) on every single slider tick, even though the user is dragging quickly through intermediate values. Each regeneration involves:
- New CGMutablePath parallelogram geometry for every panel via `tan(radians)` shear transform (`LayoutGenerator.swift:203-259`)
- Adjustment of `effectiveGutter = gutter * cos(radians) * cos(radians)` per panel
- Full crop re-computation from saliency analysis (Vision framework) — expensive ML work on the main actor

**Blank canvas during regeneration**: The sequence in `regenerateLayout` is:
1. New panels are generated with new geometry (panels exist but have no rendered images)
2. Crops are recomputed from scratch
3. `updateAllPanelPreviews()` renders all panel images — this only runs after steps 1-2 complete

Between step 1 and step 3, the UI has panels defined but with zero image content → blank canvas. The main-thread CoreGraphics compositing in step 3 blocks the run loop, creating a perceptible freeze.

**Inconsistent behavior across layout sliders**:
- Gutter slider: debounced + `preserveCrops: true` → survives rapid adjustment, no blank flash
- Slice Angle slider: **no debounce** + `preserveCrops: false` → ~75 full regenerations per drag, blank canvas
- Hex Spacing slider: same problematic pattern as slice angle (likely the same bug)

## Technical Details

| File | Line(s) | Role |
|------|---------|------|
| `LayoutConfigSidebar.swift` | 73-86 | Slice Angle slider UI (0...75°, step 1°) |
| `CollageViewModel.swift` | 189-196 | `setDiagonalSliceAngle` — calls `regenerateLayout(preserveCrops: false)` with NO debouncing |
| `LayoutManager.swift` | 139-143 | Stores value, returns old for undo — no side effects at this level |
| `CollageViewModel.swift` | 625-653 | `regenerateLayout(preserveCrops:)` — calls layout manager then `updateAllPanelPreviews()` |
| `LayoutManager.swift` | 34-82 | `regenerateLayout(...)` — generates new panels, discards/recomputes crops, no debouncing |
| `LayoutGenerator.swift` | 203-259 | `DiagonalSlicesLayoutStrategy` — shear transform `tan(radians)`, parallelogram CGPaths, `effectiveGutter = gutter * cos²(radians)` |
| `CollageViewModel.swift` | 176-187 | Gutter setter for comparison: uses `debouncer.debounce()` + `preserveCrops: true` |

## User Perception

From world-review agent analysis:
- **Blank canvas**: Users see an empty/blank canvas where image panels previously were — complete loss of visual context during parameter adjustment
- **Long pause / freeze**: Main-thread CoreGraphics compositing and Vision saliency analysis block the run loop, making the app feel frozen or broken
- **Jarring experience**: The combination of blank screen + pause breaks user trust and interrupts the iterative design workflow
- **Unresponsive slider feel**: Slider thumb may move but canvas does not reflect changes until regeneration completes — no live geometry feedback during drag

A good experience would show live panel geometry updating in real-time as the slider moves, while keeping existing image content visible inside panels. Only after the gesture ends (or debounce fires) should crops be recomputed if needed.

## Suggested Fix Direction

1. **Debouncing**: Wire `setDiagonalSliceAngle` to use debounced regeneration like the gutter slider (`debouncer.debounce(id: "sliceAngle", delay: FrameTempo.layoutChangeDebounce, ...)`). This prevents ~75 rapid regenerations during a single drag gesture.

2. **Crop preservation during drag**: Use `preserveCrops: true` during live slider adjustments so existing crop work is not discarded on every tick. Only recompute crops via saliency analysis after the debounce fires (gesture end / pause in dragging). This avoids expensive ML re-analysis on every frame of a drag.

3. **Geometry-only live preview**: During the drag, update only panel geometry (CGPaths) without triggering full `updateAllPanelPreviews()` compositing. The existing panel images remain visible inside the reshaped panels, eliminating the blank canvas window entirely. Full composite re-render happens after debounce fires or gesture ends.

4. **Review slider range**: Current range is 0...75°. At 90° you get vertical slices (no shear). Consider extending to 0...90° to allow true vertical slicing, unless there is a technical reason for the 75° cap.

## Verification

- Build + test pass
- Manual: drag slice angle slider from 0° to 75° — canvas should NOT go blank; panel geometry should update live during drag
- Manual: verify existing image content remains visible inside panels throughout the drag (no crop recomputation mid-drag)
- Manual: upon releasing slider (or after debounce pause), final layout renders correctly with any needed crop adjustments applied
- Manual: compare responsiveness with gutter slider — slice angle should feel similarly smooth and responsive
- Manual: test slider range boundaries (0°, 45°, 75°; consider testing 90° if range is extended)

(End of file - total lines TBD)
