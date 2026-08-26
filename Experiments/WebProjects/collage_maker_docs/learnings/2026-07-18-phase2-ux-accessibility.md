# Phase 2 UX + Accessibility - Learnings 2026-07-18

**Purpose**: Implement UX polish and accessibility improvements for the title editing system (Enter key guard, truncation toast, ARIA states, touch targets).

## What Worked

- **Return value pattern for side-effect notification**: Having `TitleManager.setText()` return `{ truncated: boolean }` cleanly separates the state mutation concern from the notification concern. The caller (`createTitleHandlers`) decides whether to show a toast. This is a clean DIP application — the manager doesn't know about toasts, and the handler doesn't need to duplicate truncation logic.
- **PointerEvent.pointerType for dynamic thresholds**: Using the built-in `pointerType` property on PointerEvent to select between fine (8px) and coarse (16px) edge thresholds is simpler and more reliable than feature detection or CSS media queries. It's available on every pointer event and covers mouse, touch, and pen.
- **World-review caught real UX gaps**: The automated tests verified correctness, but the world-review identified two user-experience issues that tests alone wouldn't catch: (1) Enter key blocking without feedback feels like a bug, (2) placeholder text isn't announced by screen readers. Both were fixed before shipping.
- **`@keydown.enter` vs `@input` for Enter prevention**: Using `@keydown.enter` on the textarea (not `@input`) is correct because the Enter key needs to be intercepted before Vue's `v-model` processes it. The `@input` event fires after the model update, which is too late for prevention.

## What Didn't Work / Gaps

- **WCAG 2.5.5 touch target compliance**: The 16px coarse threshold is an improvement over 8px but falls short of the WCAG 2.5.5 recommendation of 24x24px touch targets. This is a known gap that should be addressed in a follow-up. The plan specified 16px, but the world-review flagged it as insufficient.
- **Truncation toast timing**: The toast fires on every `@input` event that results in truncation. If a user pastes 10 lines, the toast fires once (correct). But if they then continue typing and the text still exceeds 3 lines, the toast would fire again. In practice this is unlikely, but worth noting.

## What Was Confusing

- **`onTitleEnterKey` binding context**: The handler uses `.call(this, event)` in `createCollageMethods.js` to bind the Vue instance as `this`, so it can access `this.titleText` and `this.showToast`. This pattern is consistent with other title handlers but required careful verification that the new handler followed the same convention.

## Skill Improvements

- **TDD skill**: Add a note that world-review should be run after tests pass but before marking a feature complete. It catches UX gaps that unit tests miss.
- **building-web-apps skill**: Document the `pointerType`-based dynamic threshold pattern as a reusable accessibility pattern for touch target sizing.
- **building-web-apps skill**: Document the `@keydown.enter` pattern for preventing newlines in textareas with line limits.

## Next Steps

- Consider increasing `EDGE_THRESHOLD_COARSE` from 16px to 24px for full WCAG 2.5.5 compliance
- Phase 3 (Progress Bar) is the next item in the plan

---
**Status**: Closed
**Follow-up**: Phase 3 Progress Bar implementation
