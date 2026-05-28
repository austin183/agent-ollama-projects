# Layered Rendering Title Occlusion — Learnings

**Date:** 2026-05-27
**Purpose:** Document learnings from Round 18.1 — fixing panel editing rendering bugs, specifically the title occlusion problem in layered rendering.

## What Worked

- **Don't clear rendered state before async replacement** — Keeping stale `panelRenderedImages` visible during the async gap (Fix A) is visually acceptable. The user just finished a gesture; stale images are one frame behind. This avoids the blank canvas that occurs when clearing before the async replacement arrives.

- **Separate title rendering layer** — Instead of baking the title into the full composite (`previewImage`) and trying to manage visibility through mode switches, `renderTitle` produces a transparent-background `NSImage` at canvas resolution. The editor ZStack layers it above per-panel images, so the title is always visible in both full composite and layered modes.

- **`isLiveGesturing` scope expansion** — Panel editor crop drag/resize operations also affect the rendering state, so they need to set `isLiveGesturing` just like canvas gestures do. This prevents title overlay handle flicker during panel editor interactions.

## What Didn't Work / Gaps

- **Baked-in title obscured by per-panel overlays** — The title was rendered by CoreGraphics into `previewImage` (full composite). When layered mode uses `previewImage` as the background layer, per-panel images drawn on top in the ZStack obscure the title. The user correctly identified this: "the title is rendering underneath the panels instead of above the panels." The solution is to render the title as a separate layer above panels, not baked into the composite background.

- **`panelRenderedImages.isEmpty` fallback condition** — Fix B was proposed but cancelled. The outer `if let previewImage` guard already guarantees `previewImage` is non-nil, so `previewImage == nil && panelRenderedImages.isEmpty` would never differ from `panelRenderedImages.isEmpty`. Fix A (don't clear) addresses the root cause directly.

## Key Pattern: Composite Image vs Layered Rendering

When switching from a full composite image (all elements baked in) to a layered rendering approach (individual elements as separate layers), any element that was baked into the composite but not rendered as its own layer will become invisible. The fix is to add that element as its own layer above the other layers.

This applies to:
- Titles, watermarks, or overlays baked into `previewImage`
- Shadows or effects applied during compositing
- Any non-panel content that needs to appear above panel images

## Skill Improvements

### `building-macos-apps/SKILL.md` — Performance Notes
Add:
- **Composite-to-layered rendering transition** — When splitting a full composite into individual layers, every element that was baked into the composite needs its own rendering path. Elements without a dedicated layer will be invisible in layered mode. Render each element (title, panels, effects) separately and compose in the ZStack.

### Existing learnings file update
Update `_agent_docs/learnings/per-panel-incremental-rendering-learnings.md`:
- Mark "Next Steps" item about Round 18.1 as completed
- Note that the title occlusion pattern (baked-in content obscured by overlays) was the key remaining issue

---
**Status:** Closed
**Follow-up:** None — Round 18.1 bugs resolved
