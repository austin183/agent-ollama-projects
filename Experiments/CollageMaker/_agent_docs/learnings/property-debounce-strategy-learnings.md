# Property Debounce Strategy — Learnings

**Date:** 2026-05-31
**Purpose:** Document learnings from debouncing background/title property changes to reduce render submissions during rapid user input.

## What Worked

### Continuous vs discrete control classification

Not all `didSet` observers need the same treatment. The decision is based on event frequency during normal use:

| Control type | Event rate | Debounce? | Rationale |
|---|---|---|---|
| Slider drag | 30-60/sec | Yes (150ms) | Continuous, user sees final value |
| Color picker drag | 30-60/sec | Yes (150ms) | Continuous, user sees final color |
| Typing | ~5/sec | No | Each keystroke should appear |
| Enum picker | ~5-10/sec | No | Discrete, 150ms delay feels sluggish |
| Image selection | ~1/sec | No | Discrete, expensive load warrants immediate feedback |

**Rule of thumb:** If the control produces more than ~10 events per second during normal interaction, debounce it. If the user expects to see each individual change (typing, selection), render immediately.

### Separate debounce tasks per scope

`previewDebounceTask` (panel crop preview during gestures) and `previewRenderDebounceTask` (full-canvas background/title property changes) are separate because they serve different scopes. A slider drag should not cancel a pending panel crop preview, and vice versa.

### Cross-boundary cancellation

When a higher-priority operation (layout regeneration, saliency completion) calls `updatePreview()` directly, it must cancel any pending debounced task first. Otherwise the debounced task wakes 150ms later and re-renders over the fresh state — a wasted render that reads current config but still costs CPU.

## What Didn't Work / Gaps

### `backgroundStyle` debounced by mistake

Initial implementation debounced `backgroundStyle` along with the color/slider properties. But `backgroundStyle` is a discrete enum picker — the user clicks a style option and should see the change immediately. A 150ms delay on a discrete selection feels like a bug. **Fix:** Reverted to immediate `updatePreview()`. This was caught by the diff-review agent, not by manual testing.

## Key Patterns

### Debounce cancellation at entry points

Any method that calls `updatePreview()` directly should also cancel the debounce task to prevent stale renders:

```swift
func regenerateLayout() {
    previewRenderDebounceTask?.cancel()  // cancel pending debounced render
    // ... layout computation ...
    updatePreview()  // render immediately with fresh state
}
```

This is a one-line addition but prevents a category of wasted renders that only manifests during rapid interaction (slider drag followed immediately by layout change).

## Skill Improvements

### `building-macos-apps/SKILL.md` — Gesture Patterns / Live Preview

Add to the live preview section:
- **Continuous vs discrete property debounce** — Slider and color picker `didSet` observers fire 30-60x/sec during drag and should use a 150ms debounced render method. Discrete controls (typing, enum picker, image selection) should render immediately. Rule of thumb: >10 events/sec = debounce.

### `building-macos-apps/references/state/swift-concurrency.md`

Add cross-boundary cancellation pattern:
- When a method bypasses a debounced path to render immediately (e.g., `regenerateLayout()` calling `updatePreview()` directly), cancel the pending debounce task first. A sleeping debounced task will otherwise wake and re-render over the fresh state.

## Next Steps

- Continue with Phase 2 (render preview at preview size) for 4x per-render speedup

---
**Status:** Closed
**Follow-up:** Phase 2 — preview size rendering
