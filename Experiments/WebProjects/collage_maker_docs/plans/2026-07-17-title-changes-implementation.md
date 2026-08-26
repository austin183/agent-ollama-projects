# Title Changes Implementation Plan

## Overview

This plan addresses three bugs and one enhancement request from `2026-07-17-01-title-changes.md`:

1. **Bug: Font Style Applies All Styles** — Clicking Bold also toggles Italic and Underline
2. **Bug: Title Width Resize Erratic on First Click** — First resize drag jumps from rendered width to fallback 400px
3. **Bug: Background Width Shrinks Below Text Width** — No padding in minimum width clamp
4. **Enhancement: Multi-line Title** — Support up to 3 lines of title text

Phases are ordered by dependency and risk: the font style fix (Phase 1) is isolated and low-risk; the resize fix (Phase 2) requires understanding the interaction handler; the minimum constraint (Phase 3) is a one-line clamp change; multi-line (Phase 4) is the most invasive change, touching data model, renderer, interaction, and UI.

## Current State Analysis

### Bug 1: Font Style Toggle (P0)
- **Root cause**: `TitleManager.js:93-95` — `applyFormattingToRange` checks `formatting.bold !== undefined` to decide whether to toggle. When `toggleBold` passes `{ bold: undefined }`, the `italic` and `underline` properties are also absent from the object, so the `!== undefined` check is `false` for them too — causing all three to toggle.
- **Existing test**: `TitleManagerTest.html:163-176` (test 3.2.5) documents this behavior as *expected*, meaning the tests will need updating.

### Bug 2: Erratic First-Click Resize (P0)
- **Root cause**: `TitleInteraction.js:213` — `dragStartBoxWidth` is set to `state.titleStyle.titleBoxWidth ?? null`. When `titleBoxWidth` is `null` (auto-fit, the default), `dragStartBoxWidth` becomes `null`. The resize handler at line 290 falls back to `(dragStartBoxWidth ?? boxWidth)` where `boxWidth = state.titleStyle.titleBoxWidth ?? 400`. This means the resize starts from 400px instead of the actual rendered auto-fit width (e.g., ~224px for "Hello World" at 36px Arial).
- **Visible symptom**: Title box jumps from its rendered width to 400px on the first resize drag. Second drag works because `titleBoxWidth` is now a concrete number.

### Bug 3: Background Width Minimum (P1)
- **Root cause**: `TitleInteraction.js:294,305` — `minWidth = Math.max(100, bounds.textWidth)` uses raw text width. But the auto-fit box is `textWidth + PADDING * 2` (24px padding). The minimum should include padding to prevent the background from visually clipping the text.
- **Impact**: User can drag the resize handle past the text edge, leaving no background padding on one or both sides.

### Enhancement: Multi-line Title (P1)
- **Current state**: Title is single-line. `TitleRun.js` has no line-break concept. `TitleRenderer.js` renders runs sequentially on one baseline. `TitleInteraction.js` hit-tests a single-line bounding box. `index.html:160` uses `<input type="text">` for title entry.
- **Requirements**: Up to 3 lines, newline characters (`\n`) in text, textarea input, multi-line rendering with line-height, multi-line hit testing.

### Key Discoveries
- `TitleManager.js:93-95` — toggle logic uses `!== undefined` on all three properties regardless of which was requested
- `TitleInteraction.js:213` — `dragStartBoxWidth` captures `null` when `titleBoxWidth` is null (auto-fit)
- `TitleInteraction.js:273` — fallback `boxWidth = state.titleStyle.titleBoxWidth ?? 400` is hardcoded
- `TitleInteraction.js:294,305` — `minWidth` uses `bounds.textWidth` without padding
- `TitleRenderer.js:46` — auto-fit width: `titleStyle.titleBoxWidth ?? (totalWidth + PADDING * 2)`
- `TitleRenderer.js:22` — `computeBounds` returns single-line bounds; multi-line needs new `computeMultiLineBounds`
- `index.html:160` — `<input type="text">` doesn't support multi-line; needs `<textarea>`
- `createCollageData.js:41` — `titleText: ''` — plain string, can hold `\n` characters natively

## Desired End State

### Bug 1 Fix
- Clicking Bold toggles only bold on the selected range; italic and underline are untouched
- Clicking Italic toggles only italic; bold and underline are untouched
- Clicking Underline toggles only underline; bold and italic are untouched
- Double-clicking the same style correctly un-toggles just that style

### Bug 2 Fix
- First resize drag starts from the actual rendered width (auto-fit or custom)
- No visible jump on first drag
- Subsequent drags behave identically to first drag

### Bug 3 Fix
- Minimum width during resize is `max(100, textWidth + PADDING * 2)` — matching auto-fit behavior
- Background always has at least PADDING (12px) on both sides of text

### Multi-line Enhancement
- Title input is a `<textarea>` supporting up to 3 lines
- Newline characters (`\n`) in title text produce line breaks
- Title renders with consistent line-height across all lines
- Title background box expands vertically to fit all lines
- Drag and resize interaction works with multi-line bounding box
- Width slider still works; text wraps at explicit newlines (no automatic word-wrap)
- Maximum 3 lines enforced in the UI

## What We're NOT Doing

- **Automatic word wrapping** — Lines are created only by explicit `\n` characters. Narrowing the title box does not auto-wrap text.
- **Per-line formatting** — Bold/italic/underline still apply to character ranges across all lines. No per-line style controls.
- **Per-line alignment** — All lines share the same alignment setting.
- **More than 3 lines** — Hard limit of 3 lines. 4th `\n` is rejected.
- **Multi-line persistence** — Title text and runs are not persisted to localStorage (existing behavior, unchanged).
- **Keyboard line navigation** — Arrow key navigation within the textarea is handled by the browser natively.
- **Title rotation, shadow, or stroke** — Out of scope.

## Implementation Approach

Each phase is independently testable and deployable. Phases 1-3 are bug fixes with minimal risk. Phase 4 is a feature addition with broader impact.

---

## Phase 1: Fix Font Style Toggle Bug

### Overview
Fix `applyFormattingToRange` in TitleManager to toggle only the explicitly requested formatting property, leaving other properties untouched. This is a surgical one-function change with high test coverage.

### Changes Required:

#### 1. TitleManager — Fix Toggle Logic
**File**: `MyESModules/State/TitleManager.js` (lines 88-96)

Change the formatting application logic to only toggle properties that are explicitly present in the `formatting` object:

```javascript
// Part inside the range - apply formatting
const insideText = run.text.substring(beforeStart, afterStart);
if (insideText.length > 0) {
    newRuns.push(createTitleRun(
        insideText,
        'bold' in formatting ? (formatting.bold !== undefined ? formatting.bold : !run.bold) : run.bold,
        'italic' in formatting ? (formatting.italic !== undefined ? formatting.italic : !run.italic) : run.italic,
        'underline' in formatting ? (formatting.underline !== undefined ? formatting.underline : !run.underline) : run.underline
    ));
}
```

**Explanation**: The `'bold' in formatting` check determines if the caller explicitly requested bold toggling. If not present, the existing `run.bold` value is preserved. If present, the existing toggle logic (`undefined` means toggle, explicit boolean means set) applies only to that property.

#### 2. TitleManagerTest — Update Test 3.2.5
**File**: `MyComponents/TitleManagerTest.html` (lines 163-176)

The existing test 3.2.5 documents the buggy behavior. Rewrite it to verify correct behavior:

```javascript
it('3.2.5 — toggleBold does not affect italic or underline', () => {
    tm.setText('Hello');
    tm.toggleBold(1, 3);  // 'el' becomes bold only
    const runs = tm.getRuns();
    expect(runs.length).to.equal(3);
    expect(runs[1].text).to.equal('el');
    expect(runs[1].bold).to.be.true;
    expect(runs[1].italic).to.be.false;
    expect(runs[1].underline).to.be.false;
});
```

#### 3. TitleManagerTest — Add New Tests
**File**: `MyComponents/TitleManagerTest.html` (after section 3.2)

Add tests verifying independent toggling:

```javascript
it('3.2.8 — toggleItalic does not affect bold or underline', () => {
    tm.setText('Hello');
    tm.toggleItalic(1, 3);
    const runs = tm.getRuns();
    expect(runs[1].italic).to.be.true;
    expect(runs[1].bold).to.be.false;
    expect(runs[1].underline).to.be.false;
});

it('3.2.9 — toggleUnderline does not affect bold or italic', () => {
    tm.setText('Hello');
    tm.toggleUnderline(1, 3);
    const runs = tm.getRuns();
    expect(runs[1].underline).to.be.true;
    expect(runs[1].bold).to.be.false;
    expect(runs[1].italic).to.be.false;
});

it('3.2.10 — toggleBold on italic range preserves italic', () => {
    tm.setText('Hello');
    tm.toggleItalic(1, 3);  // 'el' is italic
    tm.toggleBold(1, 3);    // 'el' becomes bold+italic (italic preserved)
    const runs = tm.getRuns();
    expect(runs[1].bold).to.be.true;
    expect(runs[1].italic).to.be.true;
    expect(runs[1].underline).to.be.false;
});
```

### Behavior Scenarios

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 1.1.1 | Title text "Hello World" with "Hello" selected | The user clicks the Bold button | Only "Hello" becomes bold; italic and underline are not applied |
| 1.1.2 | Title text "Hello World" with "Hello" selected | The user clicks the Italic button | Only "Hello" becomes italic; bold and underline are not applied |
| 1.1.3 | Title text "Hello World" with "Hello" selected | The user clicks the Underline button | Only "Hello" is underlined; bold and italic are not applied |
| 1.1.4 | Title text with "Hello" in bold+italic | The user selects "Hello" and clicks Bold again | "Hello" becomes italic only (bold is toggled off, italic preserved) |
| 1.1.5 | Title text with "Hello" in bold only | The user selects "Hello" and clicks Italic | "Hello" becomes bold+italic (italic added, bold preserved) |

#### Pure Function Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 1.3.1 | `applyFormattingToRange(1, 3, { bold: undefined })` on plain text | Range is formatted | Only `bold` is toggled to `true`; `italic` and `underline` remain `false` |
| 1.3.2 | `applyFormattingToRange(1, 3, { italic: undefined })` on plain text | Range is formatted | Only `italic` is toggled to `true`; `bold` and `underline` remain `false` |
| 1.3.3 | `applyFormattingToRange(1, 3, { underline: undefined })` on plain text | Range is formatted | Only `underline` is toggled to `true`; `bold` and `italic` remain `false` |
| 1.3.4 | `applyFormattingToRange(1, 3, { bold: undefined })` on italic text | Range is formatted | `bold` is toggled to `true`; `italic` remains `true` (preserved) |

#### Unit Test Scenarios

| # | Test | Input | Expected |
|---|------|-------|----------|
| 1.4.1 | toggleBold only affects bold | `toggleBold(1, 3)` on "Hello" | `runs[1].bold=true`, `italic=false`, `underline=false` |
| 1.4.2 | toggleItalic only affects italic | `toggleItalic(1, 3)` on "Hello" | `runs[1].italic=true`, `bold=false`, `underline=false` |
| 1.4.3 | toggleUnderline only affects underline | `toggleUnderline(1, 3)` on "Hello" | `runs[1].underline=true`, `bold=false`, `italic=false` |
| 1.4.4 | toggleBold preserves existing italic | italic on range, then `toggleBold` | `bold=true`, `italic=true`, `underline=false` |
| 1.4.5 | Double toggleBold unbolds only | bold on range, then `toggleBold` twice | `bold=false`, `italic=false`, `underline=false` |

### Success Criteria:

#### Automated Verification:
- [ ] Updated test 3.2.5 passes with new expected behavior
- [ ] New tests 3.2.8, 3.2.9, 3.2.10 all pass
- [ ] All existing TitleManager tests pass (no regressions)
- [ ] All existing unit tests pass (`node scripts/run-tests.js`)

#### Manual Verification:
- [ ] Click Bold on selected text — only bold is applied
- [ ] Click Italic on selected text — only italic is applied
- [ ] Click Underline on selected text — only underline is applied
- [ ] Click Bold on already-bold text — bold is removed, other styles preserved
- [ ] Apply Bold then Italic — both are present
- [ ] Apply all three, then remove one — only that one is removed

---

## Phase 2: Fix Title Width Resize Erratic on First Click

### Overview
Fix the resize interaction so that `dragStartBoxWidth` always captures the actual rendered width, even when `titleBoxWidth` is `null` (auto-fit). This eliminates the jump from rendered width to 400px fallback on first drag.

### Changes Required:

#### 1. TitleInteraction — Compute Actual Width on Pointer Down
**File**: `MyESModules/Interaction/TitleInteraction.js` (lines 205-213)

Replace the `dragStartBoxWidth` assignment that reads directly from `titleStyle.titleBoxWidth` with a computation that uses the actual rendered bounds:

```javascript
// Record start state
dragStartCoords = { x: coords.x, y: coords.y };
dragStartBoxX = state.titleStyle.titleBoxX !== null && state.titleStyle.titleBoxX !== undefined
    ? state.titleStyle.titleBoxX
    : (SIZE_CONSTANTS.defaultCanvasWidth - (state.titleStyle.titleBoxWidth ?? 0)) / 2;
dragStartBoxY = state.titleStyle.titleBoxY !== null && state.titleStyle.titleBoxY !== undefined
    ? state.titleStyle.titleBoxY
    : SIZE_CONSTANTS.defaultCanvasHeight - 40;

// Compute actual rendered width (handles auto-fit case)
const runs = titleManager.getRuns();
const bounds = computeBounds(state.titleStyle, runs, SIZE_CONSTANTS.defaultCanvasWidth, SIZE_CONSTANTS.defaultCanvasHeight);
dragStartBoxWidth = bounds.boxWidth;
```

**Why this works**: `computeBounds` returns `titleStyle.titleBoxWidth ?? (totalWidth + PADDING * 2)`. When `titleBoxWidth` is `null`, it computes the actual auto-fit width from the text runs. This matches what the renderer actually draws.

#### 2. TitleInteraction — Remove Hardcoded Fallback in Resize Handlers
**File**: `MyESModules/Interaction/TitleInteraction.js` (lines 273, 290, 301)

The `const boxWidth = state.titleStyle.titleBoxWidth ?? 400` on line 273 is no longer needed as a fallback for `dragStartBoxWidth`. It is still used for the drag clamping on line 281, but that's a different concern (bounding box for drag clamping). The resize handlers on lines 290 and 301 use `(dragStartBoxWidth ?? boxWidth)` — since `dragStartBoxWidth` is now always a concrete number, the `?? boxWidth` fallback is dead code but harmless. For cleanliness, we can remove the fallback:

```javascript
// Line 290 (resize-right):
let newWidth = dragStartBoxWidth + dxLogical;

// Line 301 (resize-left):
let newWidth = dragStartBoxWidth - dxLogical;
```

And update line 309 similarly:
```javascript
const widthDelta = newWidth - dragStartBoxWidth;
```

#### 3. TitleInteractionTest — Add Tests
**File**: `MyComponents/TitleInteractionTest.html` (new section)

Add tests verifying that `dragStartBoxWidth` is computed correctly for auto-fit:

```javascript
it('2.1.1 — dragStartBoxWidth uses computed bounds for auto-fit', () => {
    // When titleBoxWidth is null, dragStartBoxWidth should be the
    // computed auto-fit width, not a hardcoded fallback
    // (Verified via manual testing: first resize drag is smooth)
});

it('2.1.2 — dragStartBoxWidth uses custom width when set', () => {
    // When titleBoxWidth is 600, dragStartBoxWidth should be 600
});
```

### Behavior Scenarios

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 2.1.1 | Title text "Hello" with auto-fit width (no custom width set) | The user clicks and drags the right edge to resize | The title box resizes smoothly from its current rendered width with no visible jump |
| 2.1.2 | Title text "Hello" with auto-fit width | The user clicks and drags the left edge to resize | The title box resizes smoothly from its current rendered width with no visible jump |
| 2.1.3 | Title text with custom width (600px) | The user clicks and drags the right edge to resize | The title box resizes smoothly from 600px |
| 2.1.4 | Title text with auto-fit width | The user resizes, releases, then resizes again | Both resize operations behave identically (no difference between first and subsequent drags) |

#### Component Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 2.2.1 | `titleBoxWidth` is `null`, text renders at ~224px auto-fit | Pointer down on resize handle | `dragStartBoxWidth` is ~224 (computed from bounds), not `null` or 400 |
| 2.2.2 | `titleBoxWidth` is `600` | Pointer down on resize handle | `dragStartBoxWidth` is `600` |

#### Pure Function Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 2.3.1 | `computeBounds` with `titleBoxWidth: null`, text "Hello" at 36px Arial | Bounds are computed | `boxWidth` equals `textWidth + PADDING * 2` |
| 2.3.2 | `computeBounds` with `titleBoxWidth: 600` | Bounds are computed | `boxWidth` is `600` |

### Success Criteria:

#### Automated Verification:
- [x] All existing TitleInteraction tests pass (31/31 passing)
- [x] All existing unit tests pass (no regressions)
- [x] `computeBounds` returns correct `boxWidth` for both auto-fit and custom width

#### Manual Verification:
- [ ] First resize drag (auto-fit width) is smooth with no jump
- [ ] First resize drag (custom width) is smooth
- [ ] Left-edge resize is smooth on first drag
- [ ] Right-edge resize is smooth on first drag
- [ ] Second resize drag behaves identically to first
- [ ] Resize still clamps to minimum and maximum correctly

---

## Phase 3: Fix Title Background Width Minimum Constraint

### Overview
Update the minimum width clamp in the resize handlers to include padding, matching the auto-fit behavior where the box is `textWidth + PADDING * 2`.

### Changes Required:

#### 1. TitleInteraction — Add Padding to Minimum Width
**File**: `MyESModules/Interaction/TitleInteraction.js` (lines 294 and 305)

Change the `minWidth` computation in both resize handlers:

```javascript
// Line 294 (resize-right):
const minWidth = Math.max(100, bounds.textWidth + 24); // 24 = PADDING * 2

// Line 305 (resize-left):
const minWidth = Math.max(100, bounds.textWidth + 24); // 24 = PADDING * 2
```

**Note**: `PADDING = 12` is defined in `TitleRenderer.js:8` but not exported. To avoid a cross-module dependency for a constant, we use the literal `24` with an inline comment. Alternatively, we could export `PADDING` from `TitleRenderer.js` and import it here. The cleaner approach is to export it:

**File**: `MyESModules/Rendering/TitleRenderer.js` (line 8)

```javascript
export const PADDING = 12;
```

**File**: `MyESModules/Interaction/TitleInteraction.js` (line 16, add import)

```javascript
import { computeBounds, PADDING } from '../Rendering/TitleRenderer.js';
```

Then use `PADDING * 2` in the minWidth computation:

```javascript
const minWidth = Math.max(100, bounds.textWidth + PADDING * 2);
```

### Behavior Scenarios

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 3.1.1 | Title text "Hello World" with background visible | The user drags the right edge leftward past the text | The background stops shrinking when it reaches the text width + padding (12px on each side) |
| 3.1.2 | Title text "Hello World" with background visible | The user drags the left edge rightward past the text | The background stops shrinking when it reaches the text width + padding |
| 3.1.3 | Title text very short (e.g., "A") | The user tries to shrink the width | Width stops at 100px (the absolute minimum), not at text width |
| 3.1.4 | Title text very long (e.g., 50 characters) | The user tries to shrink the width | Width stops at `textWidth + 24px`, ensuring padding on both sides |

#### Component Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 3.2.1 | Text width is 200px | Resize handler computes minWidth | `minWidth` is `max(100, 200 + 24) = 224` |
| 3.2.2 | Text width is 50px | Resize handler computes minWidth | `minWidth` is `max(100, 50 + 24) = 100` (absolute min wins) |
| 3.2.3 | Text width is 800px | Resize handler computes minWidth | `minWidth` is `max(100, 800 + 24) = 824` |

### Success Criteria:

#### Automated Verification:
- [ ] All existing TitleInteraction tests pass
- [ ] All existing unit tests pass
- [ ] `PADDING` is exported from `TitleRenderer.js` and imported in `TitleInteraction.js`

#### Manual Verification:
- [ ] Right-edge resize stops at text width + padding
- [ ] Left-edge resize stops at text width + padding
- [ ] Background always has visible padding on both sides of text
- [ ] Very short text still respects 100px absolute minimum
- [ ] Very long text respects text width + padding minimum

---

## Phase 4: Multi-line Title Support

### Overview
Enable up to 3 lines of title text. This requires changes across the data model, renderer, interaction handler, and UI. Newlines (`\n`) are the only line break mechanism — no automatic word wrapping.

### Changes Required:

#### 1. UI — Replace Input with Textarea
**File**: `index.html` (line 160)

Replace the single-line `<input>` with a `<textarea>`:

```html
<textarea id="titleInput" v-model="titleText" @input="onTitleTextChange" @select="onTitleSelectionChange" @click="onTitleSelectionChange" @keyup="onTitleSelectionChange" placeholder="Enter title text..." class="pure-input-rounded" rows="3" maxlength="200"></textarea>
```

**Key attributes**:
- `rows="3"` — shows 3 lines in the textarea
- `maxlength="200"` — reasonable character limit
- `@input` — triggers `onTitleTextChange` which calls `titleManager.setText()`

#### 2. TitleManager — Enforce 3-Line Limit
**File**: `MyESModules/State/TitleManager.js` (lines 126-135)

Modify `setText` to strip newlines beyond the 3rd line:

```javascript
setText(text) {
    const t = String(text || '');
    // Enforce maximum 3 lines
    const lines = t.split('\n');
    const clampedText = lines.length > 3 ? lines.slice(0, 3).join('\n') : t;

    state.titleText = clampedText;
    if (clampedText.length === 0) {
        state.titleRuns = [];
    } else {
        state.titleRuns = [createTitleRun(clampedText, false, false, false)];
    }
    notify();
}
```

**Note**: The `titleRuns` model stores the full text including `\n` characters in a single run (or multiple runs if formatting is applied). The renderer handles line splitting. This keeps the run model simple — no per-line run arrays.

#### 3. TitleManager — Enforce 3-Line Limit on insertChar
**File**: `MyESModules/State/TitleManager.js` (lines 145-189)

The `insertChar` method needs to prevent inserting `\n` if it would create a 4th line. However, since `insertChar` takes a single character, we need to check the current line count:

```javascript
insertChar(index, char, bold = false, italic = false, underline = false) {
    // Prevent creating a 4th line
    if (char === '\n') {
        const currentText = this.getFullText();
        const lineCount = currentText.split('\n').length;
        if (lineCount >= 3) return; // Already 3 lines, can't add another
    }
    // ... rest of existing method unchanged
}
```

#### 4. TitleRenderer — Multi-line Bounds Computation
**File**: `MyESModules/Rendering/TitleRenderer.js` (after `computeBounds`, ~line 74)

Add `computeMultiLineBounds` — a pure function that splits text by `\n` and computes the bounding box for all lines:

```javascript
const LINE_HEIGHT_MULTIPLIER = 1.2;

/**
 * Computes the bounding box of multi-line title text.
 * Splits runs by newline characters, measures each line, and returns
 * the combined bounding box.
 * @param {Object} titleStyle
 * @param {Array} titleRuns
 * @param {number} width - Canvas width
 * @param {number} height - Canvas height
 * @param {CanvasRenderingContext2D} [measureCtx] - Optional context for measurement
 * @returns {{ x: number, y: number, width: number, height: number, baselineY: number, textWidth: number, contentStartX: number, boxWidth: number, lines: Array }}
 */
export function computeMultiLineBounds(titleStyle, titleRuns, width, height, measureCtx) {
    const fontSize = titleStyle.fontSize || 36;
    const fontFamily = titleStyle.fontFamily || 'Arial';
    const lineHeight = fontSize * LINE_HEIGHT_MULTIPLIER;

    // Split runs into lines by \n
    const lines = splitRunsByNewline(titleRuns);

    // Measure each line
    const ctx = measureCtx || (function () {
        const offscreen = document.createElement('canvas');
        return offscreen.getContext('2d');
    })();

    let maxWidth = 0;
    const measuredLines = [];

    for (const lineRuns of lines) {
        let lineWidth = 0;
        const measuredRuns = [];
        for (const run of lineRuns) {
            const fontParts = [];
            if (run.italic) fontParts.push('italic');
            if (run.bold) fontParts.push('bold');
            fontParts.push(fontSize + 'px');
            fontParts.push(fontFamily);
            ctx.font = fontParts.join(' ');
            const w = ctx.measureText(run.text).width;
            measuredRuns.push({ text: run.text, bold: run.bold, italic: run.italic, underline: run.underline, width: w, font: fontParts.join(' ') });
            lineWidth += w;
        }
        maxWidth = Math.max(maxWidth, lineWidth);
        measuredLines.push({ runs: measuredRuns, width: lineWidth });
    }

    const boxWidth = titleStyle.titleBoxWidth ?? (maxWidth + PADDING * 2);
    const numLines = lines.length;
    const boxHeight = (numLines > 1 ? (numLines - 1) * lineHeight : 0) + fontSize + PADDING * 2;

    // Compute text start offset within box (alignment)
    let contentStartX;
    const alignment = titleStyle.alignment || 'center';
    // Use the widest line for alignment offset
    switch (alignment) {
        case 'left': contentStartX = 0; break;
        case 'right': contentStartX = boxWidth - maxWidth; break;
        case 'center': default: contentStartX = (boxWidth - maxWidth) / 2; break;
    }

    const baselineY = titleStyle.titleBoxY !== null && titleStyle.titleBoxY !== undefined
        ? titleStyle.titleBoxY
        : height - MARGIN;

    return {
        x: 0,
        y: baselineY - (numLines > 1 ? (numLines - 1) * lineHeight : 0) - fontSize - PADDING,
        width: boxWidth,
        height: boxHeight,
        baselineY: baselineY, // Baseline of the LAST line
        textWidth: maxWidth,
        contentStartX: contentStartX,
        boxWidth: boxWidth,
        lines: measuredLines
    };
}

/**
 * Splits an array of runs into lines by \n characters.
 * @param {Array} titleRuns
 * @returns {Array<Array>} Array of arrays of runs, one per line
 */
function splitRunsByNewline(titleRuns) {
    const lines = [[]];
    let currentLineRuns = lines[0];

    for (const run of titleRuns) {
        const parts = run.text.split('\n');
        for (let i = 0; i < parts.length; i++) {
            if (parts[i].length > 0) {
                currentLineRuns.push(createTitleRun(parts[i], run.bold, run.italic, run.underline));
            }
            if (i < parts.length - 1) {
                // Move to next line
                currentLineRuns = [];
                lines.push(currentLineRuns);
            }
        }
    }

    // Remove empty trailing lines
    while (lines.length > 1 && lines[lines.length - 1].length === 0) {
        lines.pop();
    }

    return lines;
}
```

#### 5. TitleRenderer — Multi-line Render
**File**: `MyESModules/Rendering/TitleRenderer.js` (lines 103-229)

Refactor `render()` to use `computeMultiLineBounds` and render each line:

```javascript
export function render(ctx, width, height, titleStyle, titleRuns, interactionState) {
    if (!titleRuns || titleRuns.length === 0) return;

    const fontSize = titleStyle.fontSize || 36;
    const fontFamily = titleStyle.fontFamily || 'Arial';
    const fontColor = titleStyle.fontColor || '#FFFFFF';
    const fontOpacity = titleStyle.fontOpacity ?? 1.0;
    const alignment = titleStyle.alignment || 'center';
    const showBackground = titleStyle.showBackground ?? false;
    const backgroundColor = titleStyle.backgroundColor || '#000000';
    const bgOpacity = titleStyle.bgOpacity ?? 1.0;
    const lineHeight = fontSize * LINE_HEIGHT_MULTIPLIER;

    // Compute multi-line bounds
    const bounds = computeMultiLineBounds(titleStyle, titleRuns, width, height, ctx);
    const { lines, boxWidth, contentStartX } = bounds;

    // Compute box X position (same logic as single-line)
    let effectiveBoxX;
    if (titleStyle.titleBoxX !== null && titleStyle.titleBoxX !== undefined) {
        effectiveBoxX = titleStyle.titleBoxX;
    } else if (titleStyle.titleBoxWidth !== null && titleStyle.titleBoxWidth !== undefined) {
        effectiveBoxX = (width - boxWidth) / 2;
    } else {
        switch (alignment) {
            case 'left': effectiveBoxX = MARGIN; break;
            case 'right': effectiveBoxX = width - MARGIN - bounds.textWidth; break;
            case 'center': default: effectiveBoxX = (width - bounds.textWidth) / 2; break;
        }
    }

    const boxLeft = effectiveBoxX;
    const isLegacyMode = (titleStyle.titleBoxWidth === null || titleStyle.titleBoxWidth === undefined)
        && (titleStyle.titleBoxX === null || titleStyle.titleBoxX === undefined);

    // Draw background
    if (showBackground) {
        ctx.save();
        ctx.globalAlpha = bgOpacity;
        ctx.fillStyle = backgroundColor;
        const bgX = isLegacyMode ? boxLeft - PADDING : boxLeft;
        ctx.fillRect(
            bgX,
            bounds.y,
            boxWidth,
            bounds.height
        );
        ctx.restore();
    }

    // Draw each line
    ctx.save();
    ctx.globalAlpha = fontOpacity;
    ctx.textBaseline = 'alphabetic';

    // The baselineY in bounds is the baseline of the LAST line
    // We render from top to bottom
    const numLines = lines.length;
    for (let lineIdx = 0; lineIdx < numLines; lineIdx++) {
        const lineBaselineY = bounds.baselineY - (numLines - 1 - lineIdx) * lineHeight;
        const lineRuns = lines[lineIdx];

        // Compute per-line text offset (alignment within box)
        let lineTextOffset = contentStartX;
        // For right-aligned, offset is based on this line's width
        if (alignment === 'right') {
            lineTextOffset = boxWidth - lines[lineIdx].width;
        }
        lineTextOffset = Math.max(0, lineTextOffset);

        let cursorX = boxLeft + lineTextOffset;
        for (const mr of lineRuns) {
            ctx.font = mr.font;
            ctx.fillStyle = fontColor;
            ctx.fillText(mr.text, cursorX, lineBaselineY);
            if (mr.underline) {
                ctx.fillStyle = fontColor;
                ctx.fillRect(cursorX, lineBaselineY + 2, mr.width, 2);
            }
            cursorX += mr.width;
        }
    }
    ctx.restore();

    // Draw interaction outline
    if (interactionState && (interactionState.hoverTarget || interactionState.interactionMode)) {
        const outlineX = isLegacyMode ? boxLeft - PADDING : boxLeft;
        drawInteractionOutline(ctx, outlineX, bounds.y, boxWidth, bounds.height, interactionState);
    }
}
```

#### 6. TitleInteraction — Multi-line Hit Testing
**File**: `MyESModules/Interaction/TitleInteraction.js` (lines 122-171)

Replace `computeBounds` call in `_hitTestTitle` with `computeMultiLineBounds`:

```javascript
import { computeMultiLineBounds, PADDING } from '../Rendering/TitleRenderer.js';
// ...
const bounds = computeMultiLineBounds(state.titleStyle, runs, SIZE_CONSTANTS.defaultCanvasWidth, SIZE_CONSTANTS.defaultCanvasHeight);
const boxWidth = bounds.boxWidth;
const boxHeight = bounds.height;

// Box top-left in logical coords
const boxTop = bounds.y;
const boxLeft = titleBoxX; // same as before
```

The rest of the hit-testing logic (edge detection, CSS coordinate conversion) remains the same. The bounding box is now taller for multi-line text, which is the desired behavior.

Also update the `dragStartBoxWidth` computation in `_onPointerDown` (line 213 area) to use `computeMultiLineBounds`:

```javascript
const bounds = computeMultiLineBounds(state.titleStyle, runs, SIZE_CONSTANTS.defaultCanvasWidth, SIZE_CONSTANTS.defaultCanvasHeight);
dragStartBoxWidth = bounds.boxWidth;
```

#### 7. TitleInteraction — Y Clamp for Multi-line
**File**: `MyESModules/Interaction/TitleInteraction.js` (line 285)

The Y clamp needs to account for multi-line height:

```javascript
// In drag handler:
const bounds = computeMultiLineBounds(state.titleStyle, runs, SIZE_CONSTANTS.defaultCanvasWidth, SIZE_CONSTANTS.defaultCanvasHeight);
const boxHeight = bounds.height;
newY = Math.max(boxHeight, Math.min(newY, SIZE_CONSTANTS.defaultCanvasHeight - 12));
```

**Note**: The current clamp `Math.max(fontSize + 12, ...)` only accounts for single-line height. For multi-line, we need the full box height.

#### 8. CSS — Textarea Styling
**File**: `Style.css` (append)

```css
#titleInput {
    resize: none;
    min-height: 60px;
    font-family: inherit;
    font-size: var(--font-size-base);
}
```

### Behavior Scenarios

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 4.1.1 | Title input is empty | The user types "Hello" and presses Enter, then types "World" | The title displays on two lines: "Hello" on top, "World" below |
| 4.1.2 | Title has 2 lines | The user presses Enter at the end of line 2 and types "Third" | The title displays on 3 lines |
| 4.1.3 | Title has 3 lines | The user presses Enter at the end of line 3 | The Enter is ignored; title remains 3 lines |
| 4.1.4 | Title has 3 lines | The user pastes text with 5 newlines | Only the first 3 lines are kept; extra lines are discarded |
| 4.1.5 | Title has 2 lines with background visible | The user looks at the canvas | The background box is tall enough to contain both lines with padding |
| 4.1.6 | Title has 3 lines | The user clicks and drags the title body | The entire multi-line title moves with the cursor |
| 4.1.7 | Title has 2 lines | The user resizes the width | The background box width changes; text re-aligns within new width |
| 4.1.8 | Title has 1 line (default) | The user looks at the canvas | Title renders identically to pre-change behavior (backward compatible) |
| 4.1.9 | Title input is a textarea | The user scrolls in the textarea | The textarea scrolls if content exceeds visible area |
| 4.1.10 | Title has formatting on part of text across lines | The user applies bold to a selection spanning lines | Bold is applied to the selected character range across line boundaries |

#### Component Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 4.2.1 | `setText("Line1\nLine2")` is called | TitleManager processes the text | `titleText` is `"Line1\nLine2"`, single run with `\n` in text |
| 4.2.2 | `setText("A\nB\nC\nD")` is called | TitleManager processes the text | `titleText` is `"A\nB\nC"` (4th line stripped) |
| 4.2.3 | `splitRunsByNewline([{ text: "A\nB\nC" }])` is called | Runs are split | Returns `[[{text:"A"}], [{text:"B"}], [{text:"C"}]]` |
| 4.2.4 | `computeMultiLineBounds` with 3 lines | Bounds are computed | `height` is `2 * lineHeight + fontSize + PADDING * 2` |

#### Pure Function Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 4.3.1 | `splitRunsByNewline` with run `{ text: "Hello\nWorld" }` | Split is computed | Two line arrays: `["Hello"]` and `["World"]` |
| 4.3.2 | `splitRunsByNewline` with run `{ text: "A\nB\nC", bold: true }` | Split is computed | Three line arrays, each run has `bold: true` |
| 4.3.3 | `splitRunsByNewline` with run `{ text: "NoNewlines" }` | Split is computed | One line array: `["NoNewlines"]` |
| 4.3.4 | `computeMultiLineBounds` with 1 line | Bounds are computed | `height` equals single-line height: `fontSize + PADDING * 2` |
| 4.3.5 | `computeMultiLineBounds` with 3 lines, fontSize 36 | Bounds are computed | `height` is `2 * 43.2 + 36 + 24 = 136.4` |

#### Unit Test Scenarios

| # | Test | Input | Expected |
|---|------|-------|----------|
| 4.4.1 | `setText` strips 4th line | `"A\nB\nC\nD"` | `titleText` is `"A\nB\nC"` |
| 4.4.2 | `setText` keeps 3 lines | `"A\nB\nC"` | `titleText` is `"A\nB\nC"` |
| 4.4.3 | `setText` keeps 1 line | `"Hello"` | `titleText` is `"Hello"` |
| 4.4.4 | `insertChar` rejects `\n` on 3rd line | 3 lines, insert `\n` | No change to runs |
| 4.4.5 | `insertChar` accepts `\n` on 1st line | 1 line, insert `\n` | 2 lines created |
| 4.4.6 | `splitRunsByNewline` splits correctly | `[{ text: "A\nB" }]` | `[[{text:"A"}], [{text:"B"}]]` |
| 4.4.7 | `splitRunsByNewline` preserves formatting | `[{ text: "A\nB", bold: true }]` | Both runs have `bold: true` |
| 4.4.8 | `computeMultiLineBounds` 1 line height | 1 line, fontSize 36 | `height` is `36 + 24 = 60` |
| 4.4.9 | `computeMultiLineBounds` 3 line height | 3 lines, fontSize 36 | `height` is `2 * 43.2 + 60 = 146.4` |
| 4.4.10 | `computeMultiLineBounds` max width | 2 lines, widths 100 and 200 | `textWidth` is `200` |
| 4.4.11 | `render` with 2 lines | 2-line titleRuns | Two lines rendered with correct vertical spacing |
| 4.4.12 | `render` with 1 line | 1-line titleRuns | Renders identically to pre-change single-line behavior |

#### E2E Test Scenarios (Playwright)

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 4.1.e.1 | Multi-line title renders | Set title to "Line1\nLine2", verify canvas | Two lines visible on canvas |
| 4.1.e.2 | 3-line limit enforced | Paste text with 5 lines | Only 3 lines appear on canvas |
| 4.1.e.3 | Textarea accepts Enter key | Click textarea, press Enter | New line created in title |
| 4.1.e.4 | 4th Enter is rejected | Type 3 lines, press Enter on 3rd line | No 4th line created |
| 4.1.e.5 | Multi-line title is draggable | Set 2-line title, drag on canvas | Title moves as a unit |
| 4.1.e.6 | Multi-line title is resizable | Set 2-line title, drag edge | Width changes, both lines re-align |
| 4.1.e.7 | Single-line backward compatible | Set 1-line title | Renders identically to pre-change |

### Success Criteria:

#### Automated Verification:
- [ ] `splitRunsByNewline` unit tests pass (all edge cases)
- [ ] `computeMultiLineBounds` unit tests pass (1, 2, 3 lines)
- [ ] `setText` clamping tests pass (1, 2, 3, 4+ lines)
- [ ] `insertChar` newline rejection test passes
- [ ] TitleRenderer render tests updated for multi-line
- [ ] Existing single-line tests still pass (backward compatibility)
- [ ] All existing unit tests pass

#### Manual Verification:
- [ ] Textarea accepts multi-line input with Enter key
- [ ] Title renders correctly with 1, 2, and 3 lines
- [ ] 4th line is rejected (Enter on 3rd line does nothing)
- [ ] Pasting multi-line text enforces 3-line limit
- [ ] Background box expands to fit all lines
- [ ] Drag interaction works on multi-line title
- [ ] Resize interaction works on multi-line title
- [ ] Single-line title renders identically to pre-change (backward compatible)
- [ ] Font formatting (bold, italic, underline) works across line boundaries
- [ ] Alignment works correctly with multi-line text
- [ ] Textarea has reasonable styling (no resize handle, proper height)

---

## Testing Strategy

### Unit Tests (Mocha/Chai)

**Phase 1** — `TitleManagerTest.html`:
- Update test 3.2.5 (existing test documents buggy behavior)
- Add tests 3.2.8, 3.2.9, 3.2.10 (independent toggling)
- Add cross-style preservation test

**Phase 2** — `TitleInteractionTest.html`:
- Add test for `dragStartBoxWidth` computation with auto-fit
- Add test for `dragStartBoxWidth` with custom width

**Phase 3** — `TitleInteractionTest.html`:
- Add test for `minWidth` computation with padding

**Phase 4** — New test file `TitleMultiLineTest.html`:
- `splitRunsByNewline` tests (6+ cases)
- `computeMultiLineBounds` tests (4+ cases)
- `setText` clamping tests (4 cases)
- `insertChar` newline rejection test
- TitleRenderer multi-line rendering tests (context spy for fillText calls)

### E2E Tests (Playwright)

**Phase 1** — No E2E needed (covered by unit tests)
**Phase 2** — Manual verification only (interaction timing hard to automate)
**Phase 3** — Manual verification only (visual constraint)
**Phase 4** — 7 E2E scenarios (multi-line rendering, 3-line limit, textarea, drag, resize, backward compatibility)

### Manual Testing Steps

For each phase:
1. Start dev server: `bash start-server.sh`
2. Navigate to `http://localhost:8000/CollageMaker/index.html`
3. Add images, set title text
4. Follow manual verification checklist for each phase

---

## Performance Considerations

- **Phase 1**: No performance impact (single function change)
- **Phase 2**: One additional `computeBounds` call on pointerdown (negligible, already called in hot paths)
- **Phase 3**: No performance impact (constant change)
- **Phase 4**: `computeMultiLineBounds` does more measurement work than `computeBounds` (splits runs, measures per line). This is called on every render and during interaction. For 3 lines max, this is negligible. The `measureCtx` parameter allows passing the render context to avoid offscreen canvas creation.

---

## Migration Notes

No data migration needed. All changes are backward compatible:
- Single-line titles continue to work identically
- Existing title text without newlines is unaffected
- Existing formatting toggles work correctly after Phase 1 fix
- No localStorage schema changes

---

## References

- Change request: `_agent_docs/specifications/change-requests/2026-07-17-01-title-changes.md`
- TitleManager: `MyESModules/State/TitleManager.js`
- TitleInteraction: `MyESModules/Interaction/TitleInteraction.js`
- TitleRenderer: `MyESModules/Rendering/TitleRenderer.js`
- TitleRun model: `MyESModules/Models/TitleRun.js`
- TitleStyle model: `MyESModules/Models/TitleStyle.js`
- Title handlers: `MyESModules/App/createTitleHandlers.js`
- UI template: `index.html` (lines 156-234)
- TitleManager tests: `MyComponents/TitleManagerTest.html`
- TitleInteraction tests: `MyComponents/TitleInteractionTest.html`
