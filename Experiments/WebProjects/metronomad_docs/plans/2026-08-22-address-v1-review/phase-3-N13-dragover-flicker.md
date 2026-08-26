# Phase 3 — N-13: Drop-zone dragover flicker

**Source:** review N-13 — `drop-zone--dragover` flickers as the cursor crosses children (dragenter/leave pairs).

## Change (scoping deviation from the review's "cheapest" option)

The review lists `pointer-events: none` on `.drop-zone > *` — **rejected for this markup**: the drop zone's children include `#browseBtn` (and the hidden file input), and `pointer-events: none` would make Browse unclickable. Instead, guard `onDragLeave` with `relatedTarget`:

```js
onDragLeave(event) {
    const zone = event && event.currentTarget;
    const related = event && event.relatedTarget;
    if (zone && related && zone.contains(related)) return; // child crossing, not a leave
    this.isDragOver = false;
}
```

`relatedTarget` is the element being entered — a child of the zone means the drag is still inside (no flicker); outside/absent (e.g. leaving the window) is a real leave. No counter state, no CSS change, Browse untouched.

## Scenarios (inline; canonical in `behavior-specs.md` §7)

- **R-N13.1** — `isDragOver` true; `onDragLeave` with `relatedTarget` inside the zone → stays true; outside → false; absent → false. (Mock-VM with real DOM elements for `currentTarget`/`relatedTarget`.)

## Success criteria

- [ ] R-N13.1 RED first, then green.
- [ ] Browse button remains clickable (R-I1.2 E2E surface untouched); both suites green at the item commit.

Status: ✅ done (2026-08-22)
