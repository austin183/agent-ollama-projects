# Canvas Render Order Testing via Context Method Wrapping

## Date
2026-07-12

## Context

Fixing Issue #2 from the pre-merge review: the hex drag target highlight (dashed blue border) was drawn AFTER the selection border (white border) in `CollageAssembler.js`, causing the drag target to visually obscure the selection. The fix required verifying render order through tests.

## Problem

How do you test the **order** in which a rendering pipeline draws different visual elements? The `CollageAssembler` creates its `PanelRenderer` internally, so you can't easily inject a spy. Canvas 2D operations are imperative and stateful — there's no built-in call log.

## Solution: Wrap Canvas Context Methods

Wrap `ctx.stroke()` and `ctx.strokeRect()` to capture canvas state at the moment each drawing call executes:

```javascript
let callLog = [];
const origStroke = ctx.stroke.bind(ctx);
const origStrokeRect = ctx.strokeRect.bind(ctx);

ctx.stroke = function () {
    callLog.push({
        method: 'stroke',
        lineDash: ctx.getLineDash().join(','),
        strokeStyle: ctx.strokeStyle,
        shadowColor: ctx.shadowColor,
        globalAlpha: ctx.globalAlpha
    });
    return origStroke();
};

ctx.strokeRect = function () {
    callLog.push({
        method: 'strokeRect',
        lineDash: ctx.getLineDash().join(','),
        strokeStyle: ctx.strokeStyle,
        shadowColor: ctx.shadowColor,
        globalAlpha: ctx.globalAlpha
    });
    return origStrokeRect.apply(ctx, arguments);
};
```

After rendering, filter the call log by distinguishing properties (e.g., `strokeStyle === '#4285f4'` for hex drag target, `strokeStyle === '#ffffff'` for selection border) and verify ordering:

```javascript
const hexDragCalls = callLog.filter(c => c.strokeStyle === '#4285f4');
const selectionCalls = callLog.filter(c => c.strokeStyle === '#ffffff');

const firstHexIndex = callLog.indexOf(hexDragCalls[0]);
const firstSelectionIndex = callLog.indexOf(selectionCalls[0]);
expect(firstHexIndex).to.be.lessThan(firstSelectionIndex);
```

## Key Insights

### Pick Stable Distinguishing Properties

Each rendering method sets unique canvas properties. Use these as identifiers:
- **Hex drag target**: `strokeStyle: '#4285f4'`, `lineDash: [6, 4]`, `globalAlpha: 0.8`
- **Selection border**: `strokeStyle: '#ffffff'`, `shadowColor: 'rgba(0, 0, 0, 0.4)'`
- **Hover border**: `strokeStyle: 'rgba(100, 160, 255, 0.7)'`

### Canvas Properties Persist Between Calls

Canvas 2D properties (strokeStyle, lineDash, shadowColor) persist until explicitly changed. This means the captured state at `stroke()` time reflects what the rendering method set, not what was active when the wrapper was installed.

### Restore After Test

Always restore original methods in `afterEach` to prevent test pollution:

```javascript
afterEach(() => {
    ctx.stroke = origStroke;
    ctx.strokeRect = origStrokeRect;
});
```

## Same-Panel Overlap Guard

When two visual overlays target the same panel (e.g., `hexDragTargetId === selectedPanelId`), Canvas 2D anti-aliasing can produce visual artifacts where different border styles (dashed vs. solid) are drawn at identical coordinates. The fix is to skip the lower-priority overlay:

```javascript
// Skip hex drag target if it matches the selected panel
if (hexDragTargetId && panels && hexDragTargetId !== selectedPanelId) {
    panelRenderer.drawHexDragTarget(ctx, targetPanel);
}
```

This is a general pattern: **when multiple overlays can target the same element, the highest-priority overlay should be drawn last, and lower-priority overlays should skip when they would overlap.**

## When to Use This Pattern

Use canvas context method wrapping when:
- You need to verify render order in a rendering pipeline
- The renderer creates internal dependencies that can't be easily mocked
- You need to verify that specific canvas state is set at draw time
- You want to test visual layering without screenshot comparison

## Files Changed

- `MyESModules/Rendering/CollageAssembler.js` — render order fix + same-panel guard
- `MyComponents/RenderingTest.html` — 4 new tests using context wrapping

## Related

- Skill reference: `building-web-apps/references/testing-unit.md` — Canvas 2D Context Mocking (Proxy-based)
- Skill reference: `building-web-apps/references/canvas-2d.md` — Config-based rendering helpers
- Plan: `_agent_docs/plans/2026-07-12-pre-merge-review-fixes.md` — Phase 2
