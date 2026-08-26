# Undo/Redo Expansion — Change Request

**Date:** 2026-07-20
**Status:** Draft
**Priority:** P1 — User-facing functionality gap

---

## Overview

The undo/redo system wiring was repaired in Phase 1 of the pre-merge review fixes (CR-1: `base.getUndoManager()` getter pattern). The plumbing now works — commands pushed to the undo manager are correctly executed and trigger re-renders.

However, **only 3 of ~20 user actions push undo commands**. The vast majority of edits (adding images, changing layout, editing title text, etc.) are not undoable. Additionally, the title move/resize undo command contains a closure bug that prevents it from working.

This spec defines what actions should be undoable, how they should behave, and documents the title undo bug for a follow-up fix.

---

## Title Undo Bug (Existing — Follow-up Fix)

**Severity:** High — undo appears to work (icon enables) but silently fails.

**Symptom:** After moving or resizing the title box, the undo icon becomes available. Clicking it (or pressing Cmd+Z) does nothing — the title stays in its new position.

**Root cause:** In `createCollageLifecycle.js` (title interaction, lines 196-243), the undo command closure captures `titleUndoSnapshot` by reference. After the command is pushed, line 241 sets `titleUndoSnapshot = null`. The closure's reference now resolves to `null`, so `titleUndoSnapshot.titleBoxX` throws a `TypeError` when undo executes. The error crashes `_performUndo` before the render callback fires.

**Fix:** Copy snapshot values into a new local constant inside `onInteractionEnd` before building the command (same pattern used by the crop interaction at lines 158-162):

```javascript
// BEFORE (broken):
onInteractionEnd: () => {
    if (titleUndoSnapshot && this.undoManager) {
        const postState = { ... };
        if (/* changed */) {
            this.undoManager.push({
                undo: () => {
                    this.titleStyle.titleBoxX = titleUndoSnapshot.titleBoxX; // titleUndoSnapshot is null!
                    ...
                },
                ...
            });
        }
    }
    titleUndoSnapshot = null;
}

// AFTER (fixed):
onInteractionEnd: () => {
    if (titleUndoSnapshot && this.undoManager) {
        const preState = { ...titleUndoSnapshot }; // Copy values NOW
        const postState = {
            titleBoxX: this.titleStyle.titleBoxX,
            titleBoxY: this.titleStyle.titleBoxY,
            titleBoxWidth: this.titleStyle.titleBoxWidth
        };
        if (/* changed */) {
            this.undoManager.push({
                undo: () => {
                    this.titleStyle.titleBoxX = preState.titleBoxX;
                    this.titleStyle.titleBoxY = preState.titleBoxY;
                    this.titleStyle.titleBoxWidth = preState.titleBoxWidth;
                },
                redo: () => {
                    this.titleStyle.titleBoxX = postState.titleBoxX;
                    this.titleStyle.titleBoxY = postState.titleBoxY;
                    this.titleStyle.titleBoxWidth = postState.titleBoxWidth;
                },
            });
            this._updateUndoState();
        }
    }
    titleUndoSnapshot = null;
}
```

**Note:** The panel swap undo (lines 120-134) does NOT have this bug because `swapInfo` is not reassigned to `null` after the command is pushed. The crop undo (lines 156-178) is also safe because it copies values into `preState`/`postState` locals before the closure.

---

## Currently Undoable Actions

| # | Action | Command Label | Status |
|---|--------|---------------|--------|
| 1 | Panel swap (drag panel onto another) | "Swap Panels" | Working |
| 2 | Crop drag (drag crop handles) | "Adjust Crop" | Working |
| 3 | Title move/resize (drag title box) | "Move/Resize Title" | **Broken** (closure bug, see above) |

---

## Desired Undoable Actions

### P0 — Core Editing (Most User-Visible)

These are the actions users perform most frequently and expect to undo.

#### Add Images

- **Trigger:** User adds images via file picker or drag-and-drop.
- **Pre-state:** Current `images` array and `crops` array.
- **Post-state:** New `images` array (with added images) and `crops` array (with new crop entries).
- **Undo:** Remove the newly added images and their crops; restore previous `images` and `crops`.
- **Redo:** Re-add the images and crops.
- **Command label:** "Add Images"
- **Implementation notes:**
  - Snapshot `images` and `crops` before `imageLibrary.addImages()`.
  - Use `imageLibrary.disposeImage()` for cleanup in the undo function (not array splice alone — must revoke object URLs and dispose image elements).
  - If multiple files are added in one batch, group them into a single undo command.
  - Push command AFTER `addImages()` resolves and images are confirmed loaded.

#### Remove Image

- **Trigger:** User removes an image from the library (X button or Delete key on selected panel).
- **Pre-state:** The removed image object and its crop entry.
- **Post-state:** `images` array without the removed image.
- **Undo:** Re-insert the image and crop at their original index.
- **Redo:** Remove the image and crop again.
- **Command label:** "Remove Image"
- **Implementation notes:**
  - Snapshot the image object and crop BEFORE disposal.
  - The undo function must re-add the image to `imageLibrary` (not just splice into the array — the library manages state).
  - Consider: the disposed image's `HTMLImageElement` may have been nulled. If the image element is gone, the undo cannot restore it. In that case, show a toast: "Cannot undo — image data no longer available."

#### Clear All Images

- **Trigger:** User clicks "Clear All" in the image library.
- **Pre-state:** Full `images` array and `crops` array.
- **Post-state:** Empty arrays.
- **Undo:** Restore all images and crops.
- **Redo:** Clear all again.
- **Command label:** "Clear All Images"
- **Implementation notes:**
  - Same constraints as "Remove Image" — disposed image elements cannot be restored.
  - If any image elements were disposed, show a toast and skip the undo.

### P1 — Layout & Styling

#### Change Layout Style

- **Trigger:** User selects a different layout from the layout dropdown.
- **Pre-state:** Previous `layoutStyle` value.
- **Post-state:** New `layoutStyle` value.
- **Undo/Redo:** Toggle `this.layoutStyle` between the two values and call `_regenerateAndRender()`.
- **Command label:** "Change Layout"

#### Change Layout Options (Gutter, Slice Angle, Hex Spacing)

- **Trigger:** User adjusts gutter, slice angle, or hex spacing sliders.
- **Strategy:** Batch into a single "Layout Options" command per slider interaction (snapshot on slider start, push on slider release/blur). Do NOT push per-slider-tick — that creates undo fatigue.
- **Command label:** "Adjust Layout Options"
- **Implementation notes:**
  - Use the same pattern as crop interaction: snapshot on interaction start, push command on interaction end.
  - For sliders, "start" = focus/drag-start, "end" = blur/drag-end.

#### Title Text Change

- **Trigger:** User types in the title text editor and the field loses focus (or Enter is pressed).
- **Pre-state:** Previous `titleText` and `titleRuns`.
- **Post-state:** New `titleText` and `titleRuns`.
- **Strategy:** Do NOT push per-keystroke. Push only on blur or Enter key. This prevents undo fatigue and keeps history manageable.
- **Command label:** "Edit Title"
- **Implementation notes:**
  - `titleRuns` is an array of run objects. Snapshot must deep-copy the runs array.
  - The undo function restores both `titleText` and `titleRuns`.

#### Title Formatting (Bold/Italic/Underline)

- **Trigger:** User toggles bold, italic, or underline on selected title text.
- **Pre-state:** Previous `titleRuns` array.
- **Post-state:** New `titleRuns` array with formatting applied.
- **Command label:** "Format Title"
- **Implementation notes:**
  - Each toggle is a separate command (user may want to undo just the italic, not the bold).
  - Deep-copy `titleRuns` for the snapshot.

#### Title Style Changes (Font, Size, Color, Alignment, Opacity)

- **Trigger:** User changes any title style property (font family, font size, font color, background color, alignment, font opacity, bg opacity, show background).
- **Strategy:** Batch all style changes into a single "Title Style" command per interaction. Snapshot on first style change, push on blur/interaction end.
- **Command label:** "Change Title Style"

#### Background Changes

- **Trigger:** User changes background style, color, gradient, or background image.
- **Pre-state:** Previous background configuration.
- **Command label:** "Change Background"

#### Overlay Changes

- **Trigger:** User adds/removes overlay image, changes blend mode or opacity.
- **Command label:** "Change Overlay"

---

## Actions That Should NOT Be Undoable

| Action | Reason |
|--------|--------|
| Per-keystroke title input | Creates massive history bloat; use blur/Enter strategy instead |
| Per-slider-tick layout options | Creates undo fatigue; use start/end batching |
| Export | Destructive action with no meaningful undo |
| Settings persistence | Internal state, not user-visible |
| Image loading progress | UI state, not data mutation |

---

## Implementation Approach

### General Pattern

Each undoable action follows the same pattern:

```javascript
// 1. Snapshot pre-state
const preState = { /* relevant state */ };

// 2. Perform the action (mutates state)

// 3. Capture post-state
const postState = { /* relevant state */ };

// 4. Push command (using local copies, NOT captured variables)
this.undoManager.push({
    label: 'Action Name',
    undo: () => {
        // Restore preState values
        this.someProperty = preState.someProperty;
    },
    redo: () => {
        // Restore postState values
        this.someProperty = postState.someProperty;
    }
});
this._updateUndoState();
```

### Critical Rules

1. **Always copy values into local constants** before building the undo/redo closures. Never capture mutable variables that may be reassigned (see title undo bug above).
2. **Use `disposeImage()` for cleanup** — never splice arrays without disposing image elements and revoking object URLs.
3. **Regenerate layout after undo** — most undo operations need to call `_regenerateAndRender()` to update the canvas layout.
4. **Guard against disposed image elements** — if an image was disposed and the user tries to undo its removal, show a toast instead of crashing.
5. **Batch related changes** — group multiple related mutations (e.g., adding 5 images) into a single undo command.

### Where to Add Commands

| Action | Location |
|--------|----------|
| Add images | `createFileHandlers.js` — after `imageLibrary.addImages()` resolves |
| Remove image | `createImagePanelHandlers.js` — in `removeImage()` |
| Clear all | `createImagePanelHandlers.js` — in `clearAllImages()` |
| Layout style | `createLayoutHandlers.js` — in `onLayoutStyleChange()` |
| Layout options | `createLayoutHandlers.js` — in gutter/angle/spacing handlers |
| Title text | `createTitleHandlers.js` — in `onTitleTextChange()` (blur/Enter only) |
| Title formatting | `createTitleHandlers.js` — in toggle handlers |
| Title style | `createTitleHandlers.js` — in style change handlers |
| Background | `createBackgroundHandlers.js` — in change handlers |
| Overlay | `createOverlayHandlers.js` — in change handlers |

### Handler Module Changes

The handler modules (`createLayoutHandlers`, `createTitleHandlers`, etc.) currently accept a render callback. To push undo commands, they need access to `this.undoManager` and `this._updateUndoState()`. Two approaches:

**Option A — Pass undo callback:** Add an `onUndoCommand` callback parameter to handler factories. The callback receives `{ preState, postState, label, undoFn, redoFn }` and the wiring layer pushes the command.

**Option B — Pass undo manager directly:** Add `getUndoManager` and `onUpdateUndoState` to handler factory parameters. Handlers push commands directly.

**Recommendation:** Option A keeps handlers decoupled from the undo manager and preserves the callback injection pattern. The wiring layer (`createCollageMethods.js`) is the composition point — it knows about both handlers and the undo manager.

---

## Phased Rollout

### Phase 1 — Fix Title Undo Bug
- Fix the closure bug in `createCollageLifecycle.js` title interaction
- Add tests for title undo/redo

### Phase 2 — Image Operations
- Add images (undo = remove added images)
- Remove image (undo = re-add image, with disposed-image guard)
- Clear all images

### Phase 3 — Layout Changes
- Layout style change
- Layout options (batched)

### Phase 4 — Title & Styling
- Title text (blur/Enter)
- Title formatting
- Title style
- Background
- Overlay

---

## Testing Strategy

Each new undoable action requires:

1. **Unit test:** Verify command is pushed with correct pre/post state
2. **Unit test:** Verify undo restores pre-state and triggers render
3. **Unit test:** Verify redo restores post-state and triggers render
4. **Unit test:** Verify disposed-image guard shows toast (for image removal undo)
5. **E2E test (Playwright):** User performs action → Cmd+Z → state restored → Cmd+Shift+Z → state re-applied

---

## Success Criteria

- All P0 actions are undoable via keyboard (Cmd+Z / Cmd+Shift+Z) and toolbar buttons
- Undo icon reflects accurate state (enabled when commands exist, disabled when empty)
- No console errors during undo/redo operations
- All 1,382+ existing tests continue to pass
- New tests cover each undoable action at unit and E2E levels
