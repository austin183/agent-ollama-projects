# Rich Text Run-Based Architecture

**Date:** 2026-07-02
**Session:** 12 (Phase 3 implementation)

## Summary

The CollageMaker title system uses a **run-based** architecture for per-character formatting (bold, italic, underline). Instead of storing formatting as character-level attributes, contiguous stretches of identically-formatted text are grouped into "runs" (`TitleRun` objects). This is the same approach used by word processors and rich text frameworks.

## Data Model

```javascript
// A run: contiguous text with identical formatting
{ text: 'Hello ', bold: false, italic: false, underline: false }
{ text: 'World', bold: true, italic: false, underline: false }
```

Two runs with identical formatting are **merged** to keep the array minimal:
```javascript
// Before merge: [{ text: 'Hi', bold: true }, { text: ' there', bold: true }]
// After merge:  [{ text: 'Hi there', bold: true }]
```

## Key Pattern: Run Splitting on Format Change

When formatting a range of text (e.g., toggle bold on characters 5-10), the algorithm must:
1. Find which runs overlap with the range
2. Split overlapping runs at range boundaries
3. Apply formatting to the inside portion
4. Merge adjacent runs with identical formatting

## Critical Bug: `break` in Run-Processing Loops Drops Subsequent Runs

The original `insertChar` implementation used `break` to exit the loop after inserting a character at the start of a run. This caused **all subsequent runs to be silently dropped**, resulting in data loss.

```javascript
// BUGGY: break stops processing remaining runs
for (const run of runs) {
    if (index <= runStart) {
        newRuns.push(charRun);
        newRuns.push(cloneTitleRun(run));
        break; // ← All runs after this one are LOST
    }
    // ...
}
```

### Fix: Flag-Based Insertion

Use an `inserted` flag to track whether the character has been placed, allowing the loop to continue processing all remaining runs:

```javascript
let inserted = false;
for (const run of runs) {
    if (!inserted && index <= runStart) {
        newRuns.push(charRun);
        inserted = true;
    }
    // Always process the current run
    if (!inserted && index < runEnd) {
        // Split in middle of this run
        newRuns.push(beforePart);
        newRuns.push(charRun);
        newRuns.push(afterPart);
        inserted = true;
    } else {
        newRuns.push(cloneTitleRun(run));
    }
}
if (!inserted) {
    newRuns.push(charRun); // Append at end
}
```

## Gotchas

1. **Always merge after mutations** — After any split or format change, call `mergeAdjacentRuns()` to keep the array minimal. Without merging, the run count grows unboundedly.
2. **Empty runs must be avoided** — After splitting, discard any run with `text.length === 0`. Empty runs cause rendering artifacts and incorrect measurements.
3. **Run order matters** — Runs are ordered left-to-right. The character offset tracking (`charOffset`) must be maintained correctly through the loop.
4. **`break` is dangerous in run-processing loops** — Any operation that transforms runs must process ALL runs. Using `break` to "optimize" early exit is a data loss bug waiting to happen.

## File Reference

- `MyESModules/Models/TitleRun.js` — Run factory and formatting helpers
- `MyESModules/State/TitleManager.js` — Run manipulation logic
- `MyESModules/Rendering/TitleRenderer.js` — Run-based canvas rendering
