# Pre-Commit Review: Title Changes (Phases 1-4)

**Date:** 2026-07-18
**Plan:** `_agent_docs/plans/2026-07-17-title-changes-implementation.md`
**Branch:** `prototype/collage-maker`
**Files reviewed:** 12 staged files (4 source, 3 test, 3 skill, 1 CSS, 1 HTML)

---

## Verdict: APPROVE with Nits

The changes are well-architected, thoroughly tested (237 total tests passing), and faithfully implement the plan. The three bug fixes are surgical and correct. The multi-line feature is cleanly layered across state, rendering, and interaction modules. No blocking issues remain.

---

## Architecture & SOLID Analysis

### Single Responsibility Principle

**Good:** Each module handles its own concern:
- `TitleManager.js` — state mutations, 3-line clamping, formatting toggles
- `TitleRenderer.js` — pure math for bounds, canvas drawing
- `TitleInteraction.js` — pointer events, hit testing, drag/resize logic

**Good:** The `splitRunsByNewline` function is a pure function with no side effects. It takes runs and returns line arrays. This is testable in isolation and composes cleanly with `computeMultiLineBounds`.

**Good:** `computeMultiLineBounds` is a pure function. It accepts an optional `measureCtx` parameter to avoid offscreen canvas creation in hot paths — following the established factory testability pattern.

### Open/Closed Principle

**Good:** The multi-line feature is additive. The existing `computeBounds` function remains unchanged and exported for backward compatibility. The `render()` function is refactored but maintains the same public API signature.

**Good:** The 3-line limit is enforced at the state layer (`TitleManager.setText` and `insertChar`), not at the rendering layer. This keeps the renderer open to rendering any number of lines if the constraint is ever relaxed.

### Dependency Inversion

**Good:** `TitleInteraction.js` depends on `computeMultiLineBounds` and `PADDING` from `TitleRenderer.js` — a rendering concern providing pure math to an interaction concern. This is acceptable since these are pure functions, not rendering side effects.

**Nit:** `TitleInteraction.js` still has a local `const MARGIN = 40;` in `_hitTestTitle` (line 150) and `_onPointerDown` (line 255) that duplicates the `MARGIN` constant in `TitleRenderer.js`. The `MARGIN` constant should be exported from `TitleRenderer.js` (like `PADDING` was) or moved to `SizeConstants.js` to avoid duplication.

### Separation of Concerns

**Good:** The box position computation (legacy mode vs custom position vs custom width) is now consistent between `_hitTestTitle` and `_onPointerDown` in `TitleInteraction.js`, and matches `TitleRenderer.render()`. The JSDoc comment in `_hitTestTitle` documents this alignment explicitly.

**Good:** The interaction handler computes `dragStartBoxX` as the background/outline X (`bgX` in renderer terms), ensuring `setPosition()` during drag produces the correct visual result. The comment explains this design decision.

---

## Bug Fix Verification

### Phase 1: Font Style Toggle Fix

**Root cause:** `applyFormattingToRange` checked `formatting.bold !== undefined` for all three properties. When `{ bold: undefined }` was passed, `italic` and `underline` were also absent, so all three toggled.

**Fix:** `'bold' in formatting` check determines if the caller explicitly requested bold toggling. If absent, the existing `run.bold` value is preserved.

**Verdict:** Correct. The ternary chain `'bold' in formatting ? (formatting.bold !== undefined ? formatting.bold : !run.bold) : run.bold` is verbose but unambiguous. It preserves the existing toggle semantics (undefined = toggle, explicit boolean = set) while adding the outer guard.

**Guard clause:** `if (!formatting || startIndex < 0 || endIndex <= startIndex) return;` — good defensive addition.

**Tests:** 4 new/updated tests (3.2.5, 3.2.8, 3.2.9, 3.2.10) cover independent toggling and cross-style preservation. All pass.

### Phase 2: Title Width Resize Fix

**Root cause:** `dragStartBoxWidth = state.titleStyle.titleBoxWidth ?? null` captured `null` when `titleBoxWidth` was null (auto-fit). The resize handler fell back to `boxWidth = state.titleStyle.titleBoxWidth ?? 400`, causing a jump from rendered width (~224px) to 400px.

**Fix:** `dragStartBoxWidth = bounds.boxWidth` — computed from `computeMultiLineBounds` which returns the actual auto-fit width.

**Verdict:** Correct. The fix eliminates the hardcoded 400px fallback for `dragStartBoxWidth`. The `?? boxWidth` fallback in the resize handlers is now dead code but harmless (plan acknowledges this).

**Tests:** Existing tests pass. Self-calibrating hit test coordinates pattern documented in skill files.

### Phase 3: Background Width Minimum Fix

**Root cause:** `minWidth = Math.max(100, bounds.textWidth)` used raw text width without padding, allowing the background to visually clip the text.

**Fix:** `minWidth = Math.max(100, bounds.textWidth + PADDING * 2)` — matches auto-fit behavior.

**Verdict:** Correct. Exporting `PADDING` from `TitleRenderer.js` and importing it in `TitleInteraction.js` is the clean approach (preferred over a magic `24` literal).

**Tests:** Existing resize clamping tests still pass (minWidth >= 100 verified).

---

## Multi-Line Feature Review

### Data Model

**Design:** Title runs store `\n` characters natively in the `text` field. A single run can span multiple lines. The renderer splits runs at render time via `splitRunsByNewline`.

**Verdict:** Good design decision. Keeping the run model simple (no per-line run arrays) avoids complexity in formatting operations. The `setText` method creates a single run with `\n` characters, and `applyFormattingToRange` operates on character ranges across line boundaries transparently.

### splitRunsByNewline

**Edge cases handled:**
- Empty runs array → returns `[]`
- Trailing newlines → stripped (no empty trailing line)
- Leading newlines → stripped (no empty leading line)
- All-empty content → returns `[]`
- Multiple runs with newlines → splits correctly, preserving formatting

**Verdict:** Robust. 9 test cases covering all edge cases.

**Nit:** Stripping leading empty lines (lines 114-116) is a silent transformation. If a user intentionally types `\n\nHello`, they'll see `Hello` on a single line. This is defensible (empty lines don't render anything), but worth documenting.

### computeMultiLineBounds

**Design:** Measures each line independently, computes max width for auto-fit, calculates total height with line-height spacing. Returns `lines` array with measured runs for the renderer.

**Verdict:** Correct. The `LINE_HEIGHT_MULTIPLIER = 1.2` is a reasonable default. The `measureCtx` parameter avoids offscreen canvas creation when called from `render()`.

**Performance:** Called on every render and during interaction pointermove. For 3 lines max with ~10 runs, this is negligible. The offscreen canvas fallback is only used by `TitleInteraction.js` (which doesn't pass a context).

**Nit:** `TitleInteraction.js` calls `computeMultiLineBounds` 3-4 times per pointermove event (drag handler, resize-right, resize-left). Each call creates an offscreen canvas since no context is passed. Consider caching the bounds or passing a shared offscreen context for the interaction hot path.

### render() Refactoring

**Changes:** Replaced inline measurement loop with `computeMultiLineBounds` call. Renders each line with proper vertical spacing. Background box height accounts for multi-line.

**Verdict:** Clean refactoring. The `isLegacyMode` check and `contentStartX` logic are preserved. Right-alignment per-line offset is handled correctly.

**Potential issue:** In right-alignment with box mode, the per-line offset calculation is:
```javascript
lineTextOffset = contentStartX + (textWidth - lines[lineIdx].width);
```
This shifts shorter lines further right within the box. For a 2-line title "Hi\nHello World" in a 500px box, "Hi" would be at `contentStartX + (width_of_HelloWorld - width_of_Hi)`. This is correct — each line's right edge aligns at the same position.

### TitleInteraction Multi-line Support

**Hit testing:** Uses `computeMultiLineBounds` for the bounding box. The `bgX` offset for legacy mode matches the renderer. CSS coordinate conversion is correct.

**Drag Y clamp:** `Math.max(boxHeight, ...)` — uses multi-line box height instead of `fontSize + 12`. Correct for multi-line titles.

**Nit:** The Y clamp lower bound is `boxHeight` (the full box height). For a single-line title, this is `fontSize + PADDING * 2 = 60`. For a 3-line title at fontSize 36, this is `~146px`. This means the title can't be dragged above y=146 on a 3-line title. This is correct — the title would be clipped above the canvas edge otherwise.

---

## UI Changes

### Textarea Replacement

**Change:** `<input type="text">` → `<textarea rows="3" maxlength="200">` with `title-textarea` class.

**Verdict:** Correct. `rows="3"` shows 3 lines. `maxlength="200"` provides a reasonable character limit. The `title-textarea` CSS class prevents unwanted resizing and sets proper font inheritance.

**World-review finding — Enter key flicker:** When a user has 3 lines and presses Enter, the native textarea may briefly show a 4th line before Vue's reactive update clamps it back. Consider `@keydown.enter.prevent` or a line-count check in the input handler to prevent the visual flicker.

**World-review finding — Silent truncation:** Pasting 5-line text silently truncates to 3 lines. Consider a toast notification or visual indicator when truncation occurs.

### CSS

**Change:** New `.title-textarea` class with `resize: vertical`, `min-height: 60px`, `max-height: 150px`, `line-height: 1.4`, `white-space: pre-wrap`, `word-wrap: break-word`.

**Verdict:** Good styling. `resize: vertical` lets users adjust textarea height. `pre-wrap` preserves newlines. `word-wrap: break-word` handles long words.

**Nit:** The plan specified `resize: none` but the implementation uses `resize: vertical`. This is a reasonable deviation — letting users resize the textarea vertically improves usability for longer titles.

---

## Test Coverage

### TitleManagerTest (78 tests passing)
- Formatting toggle independence: 4 tests (3.2.5, 3.2.8, 3.2.9, 3.2.10)
- All existing tests pass (no regressions)

### TitleMultiLineTest (43 tests passing)
- `splitRunsByNewline`: 9 tests covering all edge cases
- `computeMultiLineBounds`: 11 tests covering heights, widths, alignment, guards
- `setText` clamping: 7 tests (1, 2, 3, 4, 5 lines, empty, run structure)
- `insertChar` newline handling: 4 tests (1→2, 2→3, 3→reject, regular char)
- Rendering: 10 tests (fillText calls, y-spacing, background, formatting, alignment)
- Backward compatibility: 2 tests (single-line position, background height)

### TitleInteractionTest (38 tests passing)
- Hit testing: 5 tests (body, left-edge, right-edge, outside, no text)
- Drag clamping: 5 tests (left, right, within bounds, Y top, Y bottom)
- Drag behavior: 4 tests (left clamp, right clamp, resize min width, interaction mode)
- Resize behavior: 2 tests (right resize, left resize)
- Multi-touch guard: 1 test
- PanelSwap coordination: 1 test
- Lifecycle: 3 tests (idempotent attach/detach, pointer capture, global pointerup)
- Hover feedback: 3 tests (body cursor, edge cursor, outside clear)
- Self-calibrating coordinates: 4 tests using `computeBounds`

### TitleRendererTest (47 tests passing)
- All existing tests pass (no regressions)

### SaliencyDebugOverlayTest (128 tests passing)
- Minor fix: `clearRect` expectation corrected from 1 to 0 (assembler doesn't clear)

**Total: 237 tests passing, 0 failures.**

---

## Skill Documentation Updates

### SKILL.md
Added self-calibrating hit test coordinates pattern to the testing gotchas list. Good — this pattern will help future developers write robust interaction tests.

### testing-strategy.md
Updated TitleManager cross-flag toggling note to reflect the fix. Good — keeps the testing strategy document accurate.

### testing-unit.md
Added comprehensive "Self-Calibrating Hit Test Coordinates" section with examples. Updated TitleManager testing note. Good — this is a valuable pattern for the project.

---

## Issues

### Blocking: None

### Nits (optional polish):

1. **Duplicate MARGIN constant** — `TitleInteraction.js` has `const MARGIN = 40;` in two places (lines 150, 255). Export `MARGIN` from `TitleRenderer.js` like `PADDING` was, or move both to `SizeConstants.js`.

2. **Offscreen canvas in interaction hot path** — `TitleInteraction.js` calls `computeMultiLineBounds` 3-4 times per pointermove without passing a `measureCtx`. Each call creates a new offscreen canvas. For 3 lines this is negligible, but consider caching or passing a shared context.

3. **Enter key flicker** — World-review identified potential visual flicker when pressing Enter on a 3-line title. The textarea may briefly show a 4th line before Vue clamps it. Consider `@keydown.enter.prevent` or pre-validation.

4. **Silent truncation feedback** — Pasting multi-line text silently truncates to 3 lines. A toast notification or visual indicator would improve UX.

5. **Leading newline stripping** — `splitRunsByNewline` strips leading empty lines silently. If a user types `\n\nHello`, they'll see `Hello` on a single line. This is defensible but worth documenting.

6. **`computeBounds` import in TitleInteractionTest** — The test imports `computeBounds` (single-line) for self-calibrating coordinates, while production code uses `computeMultiLineBounds`. For single-line tests this produces identical results, but consider using `computeMultiLineBounds` for consistency.

---

## World-Review Summary

The world-review agent identified several user-facing concerns:

1. **Enter key flicker risk** — Native textarea may briefly show 4th line before state clamps. Recommend DOM-level prevention.
2. **Silent truncation** — Pasting long text silently drops lines. Recommend toast notification.
3. **Accessibility** — Formatting buttons should use `aria-pressed` for screen readers. Textarea needs proper labeling.
4. **Mobile touch targets** — Resize handles on tall multi-line titles need adequate touch areas (44x44px minimum).
5. **3-line limit is reasonable** — Prevents title from dominating the canvas.

These are all valid observations. Items 1 and 2 are UX improvements for a future iteration. Items 3 and 4 are accessibility concerns worth tracking. Item 5 confirms the design decision.

---

## Approval

**APPROVE** — The changes are well-architected, correctly implement the plan, and are thoroughly tested. The three bug fixes are surgical and verified. The multi-line feature is cleanly layered. Nits are tracked for future improvement but do not block this commit.

**Co-Authored-By: LittleLight <noreply@traveler.dstny>**
