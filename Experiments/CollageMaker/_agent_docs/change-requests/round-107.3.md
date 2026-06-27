# Gradient Angle Slider Lag — Full Composite Render on Background-Only Change

**Date**: 2026-06-27
**Issue**: When dragging the gradient angle slider, there is noticeable lag between the slider thumb position and the background render update. The preview appears to stutter or freeze during continuous drag gestures.

## What Happens Today

1. User drags the gradient angle slider in `ExportPanel.swift:64-72` (range 0...360°, no step size)
2. Slider fires continuous value changes bound to `viewModel.gradientAngle`
3. The computed setter at `CollageViewModel.swift:295-307` calls `updatePreviewDebounced()`
4. Debouncer delays 20ms (`FrameTempo.previewRenderDebounce`) before firing
5. `updatePreview()` rebuilds the **entire composite** — background + all panel images + title — even though only the gradient angle changed

The full composite render path at `CollageViewModel.swift:916-930` calls `previewManager.updatePreview(...)` which invokes `assembler.assemblePreviewWithCGImages(...)`, rendering every element on the main actor. This is expensive CoreGraphics work that blocks UI responsiveness during slider drags.

## Why It's Slow

**Severe over-rendering**: The system rebuilds the entire composite (background + N panels + title) for what should be a background-only change. Each panel render involves image sampling, crop clipping, and geometry-based path rendering — none of which are affected by gradient angle changes.

**Unused optimization path exists**: `PreviewManager` already has a dedicated `updateBackground()` method (`PreviewManager.swift:85-107`) that renders only the background to `previewBackgroundImage`, using its own generation counter for stale-result discard. This path is NOT wired into `gradientAngle` changes — it's only invoked via `BackgroundManager.updateBackground(updater:)`.

**Inconsistent behavior across rendering modes**:
- Non-layered mode: displays `viewModel.previewImage` (full composite) — forced to re-render everything on every angle change
- Layered mode: displays `viewModel.previewBackgroundImage` for the background layer, but this is never updated during gradient angle drags, so it may show stale state or fall back

## Technical Details

| File | Line(s) | Role |
|------|---------|------|
| `ExportPanel.swift` | 61-73 | Gradient angle slider UI (0...360°, no step size) |
| `CollageViewModel.swift` | 295-307 | Computed setter for `gradientAngle`, calls `updatePreviewDebounced()` |
| `FrameTempo.swift` | 34 | `previewRenderDebounce = .milliseconds(20)` — debounce delay |
| `CollageViewModel.swift` | 910-914 | `updatePreviewDebounced()` debounces via `debouncer.debounce(id: "previewRender", ...)` |
| `CollageViewModel.swift` | 916-930 | `updatePreview()` builds full AssemblyConfig, renders ALL panels + title |
| `BackgroundRenderer.swift` | 12-39 | `drawGradient()` — computes start/end from angle, draws CGGradient (fast, ~ms) |
| `PreviewManager.swift` | 85-107 | `updateBackground()` — background-only render path (NOT used for gradientAngle) |
| `CollageAssembler.swift` | 269-300 | `renderBackground()` — async wrapper around BackgroundRenderer (used by updateBackground path) |

## User Perception

From world-review agent analysis:
- **Noticeable delay**: 20ms debounce + full composite render time creates perceptible lag between thumb movement and visual update
- **Stuttering/jank**: Main-thread blockage from heavy CoreGraphics compositing makes the canvas appear to freeze during continuous drag
- **Unresponsive slider feel**: Slider thumb feels "sticky" or unresponsive during rapid drags due to main thread contention
- **Inconsistent feedback across modes**: Layered mode background may not update in real-time; non-layered mode shows full composite re-render

## Suggested Fix Direction

Wire `gradientAngle` (and other gradient/color/opacity property changes) to call the dedicated `updateBackground()` path instead of the full `updatePreview()` composite render. The background-only path:
- Renders only the gradient at canvas size (~1ms vs hundreds of ms for full composite)
- Has its own generation counter for stale-result discard (`backgroundGeneration`)
- Updates `previewBackgroundImage` which is already used in layered mode

This would reduce per-event CPU from O(N panels × render time) to just background rendering, eliminating the lag. The full composite can still be regenerated on gesture end or when other properties that affect panel content change.

## Verification

- Build + test pass
- Manual: drag gradient angle slider — preview should update smoothly without stuttering
- Manual: verify non-layered mode shows updated background (either via cached `previewBackgroundImage` or fallthrough to composite)
- Manual: verify layered mode background updates in real-time during slider drag
