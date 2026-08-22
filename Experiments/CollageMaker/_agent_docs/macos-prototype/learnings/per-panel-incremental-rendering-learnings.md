# Per-Panel Incremental Rendering — Learnings

**Date:** 2026-05-27
**Purpose:** Document learnings from implementing per-panel incremental rendering (Round 18) and the rendering mode switch bugs it introduced.

## What Worked

- **Protocol method addition for rendering granularity** — Adding `renderPanel` and `renderBackground` to `CollageAssembly` was clean. Both methods reuse the same `NSBitmapImageRep` + `CGContext` pattern as the existing full composite, just at smaller dimensions. The protocol extension keeps test mocks in sync.
- **`Task.detached` per-panel pattern** — Same capture-before-detach pattern as `updatePreview()` works for individual panels: capture `cgImage`, `crop`, `panelSize` as `let` values, render on background, dispatch `NSImage` back to `@MainActor`. No concurrency issues.
- **Debounce reuse** — The existing `previewDebounceTask` and `panelPreviewTask` patterns (cancel previous, sleep 150ms, render) worked without modification for the scroll pan path.

## What Didn't Work / Gaps

- **`panelRenderedImages.isEmpty` as mode-switch condition is fragile** — The view uses this to decide between full composite (with title) and layered per-panel rendering. But since both `panelRenderedImages` and `previewImage` are populated asynchronously, clearing one before the other is ready creates a blank canvas. Specifically:
  - Gesture end handlers call `panelRenderedImages.removeAll()` synchronously, then `updatePreview()` asynchronously. During the async gap, `panelRenderedImages` is empty AND `previewImage` hasn't been updated yet → blank panels.
  - `applyOverlayCrop` calls both `updatePreview()` and `updatePanelPreview(panelId:)` asynchronously. If the panel render completes first, `panelRenderedImages` becomes non-empty → view switches to layered mode → only ONE panel has an image → other panels disappear.
- **`isLiveGesturing` doesn't cover all rendering-affecting operations** — The flag is only set by scroll pan and pinch gestures. Panel editor operations (overlay crop drag, corner resize) also affect rendering but don't set the flag, causing the title overlay to flicker when the rendering mode switches between full composite (title baked in) and layered (no title).
- **Clearing rendered state before async replacement is a race** — `panelRenderedImages.removeAll()` followed by `updatePreview()` creates an unavoidable window where neither rendering path has valid content. The fix is to NOT clear — keep stale images visible during the async gap, then repopulate.

## What Was Confusing

- **Multiple async tasks racing to set rendering state** — `updatePreview()`, `updateBackground()`, and `updatePanelPreview(panelId:)` all run on separate `Task.detached` tasks with no ordering guarantee. The view's `body` evaluates synchronously and sees whatever state happens to be set at that moment. This means the rendering mode (full composite vs layered) can flip unpredictably during rapid interactions.
- **Title visibility has two sources** — The title is baked into `previewImage` (full composite via CoreGraphics) AND shown as a SwiftUI overlay (orange border handles). In layered mode, only the overlay exists. When the mode switches, the title can appear/disappear depending on which rendering path is active, not just on `isLiveGesturing`.

## Skill Improvements

### `building-macos-apps/SKILL.md` — Performance Notes
Add:
- **Never clear rendered state before async replacement** — If a view depends on `someDict.isEmpty` to choose between rendering modes, clearing that dict before the async replacement is ready creates a blank frame. Keep stale content visible during the gap, then repopulate.
- **Multiple async rendering tasks race** — When `updatePreview()`, `updateBackground()`, and `updatePanelPreview()` all run on separate `Task.detached` tasks, there's no ordering guarantee. The view sees whatever state is current at evaluation time. If rendering mode depends on which task completed first, the mode can flip unpredictably.

### `building-macos-apps/references/state/swift-concurrency.md`
Add note about async state races in `@Observable` views:
- When multiple `Task.detached` tasks update different `@Observable` properties that a view's `body` uses together (e.g., `panelRenderedImages` and `previewImage`), the view may see inconsistent intermediate states. Consider batching related state updates in a single `Task { @MainActor in ... }` block, or avoid clearing old state until new state is confirmed ready.

## Next Steps

- ~~Fix rendering mode switch bugs per Round 18.1 change request~~ — **Completed** (Session 57, see `layered-rendering-title-occlusion-learnings.md`)
- Consider consolidating async rendering state into a single property (e.g., `RenderingMode` enum) to avoid races between independent properties

---
**Status:** Closed
**Follow-up:** Round 18.1 — see `layered-rendering-title-occlusion-learnings.md`
