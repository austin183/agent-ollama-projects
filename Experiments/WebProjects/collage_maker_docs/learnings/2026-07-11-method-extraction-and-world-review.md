# Method Extraction and World-Review Edge Cases

**Date:** 2026-07-11
**Context:** Phase 5 Follow-Up (CR-FU-09) — completing the method extraction from `createCollageMethods.js` that was previously deferred.

## 1. Deferred Extraction Can Still Be Valuable

The original decision to defer module extraction from `createCollageMethods.js` was sound: callback injection was the stronger DIP improvement, and internal functions already had clear boundaries. However, the actual extraction still delivered tangible benefits:

- **Clearer module boundaries** — each extracted module has a single, well-documented responsibility
- **Independent testability** — `createRenderMethods`, `createCropPreviewRenderer`, and `createUndoMethods` can each be tested in isolation with focused mocks
- **Reduced cognitive load** — `createCollageMethods.js` went from 576 to 392 lines; the composition layer is now a wiring diagram rather than intertwined logic
- **Easier future refactoring** — if render logic needs to change, only `createRenderMethods.js` needs attention

**Rule refinement:** If internal functions have clear boundaries AND the file exceeds ~400 lines, extraction is worth considering even if callback injection is already in place. The callback injection is the *primary* DIP improvement; module extraction is the *secondary* SRP improvement.

## 2. World-Review Catches Edge Cases Tests Miss

The world-review subagent found 2 critical issues that the unit test suite did NOT catch:

### Critical 1: Assembler captured outside callback
```javascript
// BEFORE (broken): assembler captured at call time, used in callback
const asm = assembler();
renderer.scheduleRender(function (ctx, width, height) {
    asm.render(ctx, { ... }); // THROWS if asm is undefined
});

// AFTER (fixed): assembler looked up inside callback
renderer.scheduleRender(function (ctx, width, height) {
    const asm = assembler();
    if (!asm) return;
    asm.render(ctx, { ... });
});
```

**Why tests missed it:** The test mock always returned a valid assembler. The edge case (assembler being undefined at render time) was not exercised.

### Critical 2: Missing optional chaining on `vm.panels`
```javascript
// BEFORE (broken): throws if vm.panels is undefined
const selectedPanel = vm.panels.find(p => p.id === vm.selectedPanelId);

// AFTER (fixed): safe guard
const selectedPanel = vm.panels?.find(p => p.id === vm.selectedPanelId);
```

**Why tests missed it:** Test mocks always provided `vm.panels` as an array. The edge case (panels array not yet populated) was not exercised.

**Lesson:** World-review provides a different kind of safety net than tests. Tests verify *specified* behavior; world-review questions *assumed* behavior. Always run world-review on refactoring work.

## 3. Callback Wiring in Extracted Modules

When extracting modules that depend on each other, the composition layer must wire callbacks explicitly:

```javascript
// Undo methods need render callbacks to trigger re-renders after state changes
const undoMethods = createUndoMethods(base, {
    onRenderScheduled: (vm) => renderMethods._scheduleRender(vm),
    onCropPreviewRender: (vm) => cropPreviewMethods._scheduleCropPreviewRender(vm)
});
```

**Key insight:** The extracted `createUndoMethods` does NOT import `createRenderMethods` — that would create a circular dependency. Instead, it accepts callbacks as factory parameters. The composition layer (`createCollageMethods`) wires them together.

**Pattern:** Extracted modules that need to trigger cross-module behavior should accept callback objects, not import other modules. This preserves the dependency flow: `Composition → Extracted Modules` (one-way).

## 4. Optional Chaining Consistency Across Modules

The world-review caught an inconsistency in how modules access the `base` service locator:

```javascript
// In createCollageMethods.js (safe):
() => base?.getCropManager?.() ?? null

// In createCropPreviewRenderer.js (unsafe — before fix):
() => base.getCropManager()
```

**Lesson:** When multiple modules access the same service locator, use the same access pattern everywhere. The safest pattern for optional services is `base?.getService?.() || null`. Document this convention so future extractions follow the same pattern.
