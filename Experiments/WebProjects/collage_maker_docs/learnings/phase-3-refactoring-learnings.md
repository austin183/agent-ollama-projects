# Phase 3 Architectural Refactoring - Learnings

## Session Date: July 5, 2026

### Summary
Successfully implemented Phase 3 of the architectural refactoring plan, focusing on extensibility improvements and removing duplicate logic. This phase completed the OCP compliance for layout generation, made the export system extensible via strategy/registry patterns, and consolidated canvas clearing logic.

---

## Key Learnings

### 1. Strategy Pattern Implementation for LayoutGenerator
**What we learned:**
- Refactoring from switch statements to a strategy pattern requires careful consideration of how options are passed to generators.
- Instead of hardcoding which parameters each generator receives, we now pass all optional parameters and let each generator extract what it needs. This is more flexible and truly OCP-compliant.
- The registry map (`LAYOUT_GENERATORS`) provides a clean extension point without modifying core code.

**Code change:** 
```javascript
// Before: switch statement hardcoded parameter injection
switch (style) {
    case MOSAIC: return gen({ ...base, mosaicSeed });
    // ...
}

// After: pass all options, generators extract what they need
const generatorOptions = { ...base };
if (mosaicSeed !== null) generatorOptions.mosaicSeed = mosaicSeed;
// etc.
return generator(generatorOptions);
```

### 2. ExportManager Registry Pattern
**What we learned:**
- The registry pattern (ExportManager with `registerFormat` and `export`) provides a clean abstraction for multiple export formats.
- Decoupling handlers from direct format implementations improves testability and maintainability.
- It's critical to ensure all exporters follow the same interface (assembler, state, optional params).

**Important consideration:** 
- Exporters should not assume a fixed canvas size. Accepting an optional `exportSize` parameter makes them reusable and prevents hardcoded dimensions.

### 3. Canvas Clearing in Exporters
**What we learned:**
- JPEG export **must** explicitly clear the canvas and fill with white background before rendering, because JPEG doesn't support transparency.
- The default canvas background is transparent (not white), which would result in black/dark exports if not cleared.
- This fix should be applied to all exporters (JPEG, PNG) for consistency, even though PNG supports transparency.

**Code change:**
```javascript
// Always clear and fill white before rendering
ctx.clearRect(0, 0, exportSize.width, exportSize.height);
ctx.fillStyle = '#ffffff';
ctx.fillRect(0, 0, exportSize.width, exportSize.height);
```

### 4. Test-Driven Refactoring
**What we learned:**
- When refactoring, it's crucial to update tests alongside code changes. We updated `ExportManagerTest.html` and created new tests for LayoutGenerator and Rendering.
- Complex mocking of browser APIs (Canvas API) can be fragile in unit tests. Focus on testing the core logic and API contracts rather than implementation details.
- Simpler, more robust tests that verify behavior without over-mocking are better for long-term maintenance.

**Test insights:**
- Avoid trying to intercept DOM methods like `document.createElement` globally - use simpler assertions about functionality.
- Test that methods exist and accept correct parameters; don't over-test internal mechanics that can change.

### 5. Web-Specific Edge Cases in Canvas Apps
**New concerns identified:**
1. **DPR Scaling in Exports**: Export size should account for Device Pixel Ratio to ensure high-quality output on Retina displays.
2. **Tainted Canvas / CORS**: Images from external sources must have `crossOrigin="anonymous"` set, or exports will fail silently or throw security errors.
3. **Memory Management**: Offscreen canvases and blob URLs need proper cleanup (already handled with `URL.revokeObjectURL` in try/finally).
4. **Vue Reactivity During Export**: Ensure export operates on plain data, not reactive state that might trigger re-renders.

### 6. Breaking Changes and Compatibility
**What we learned:**
- Refactoring to a new pattern may break existing imports (e.g., `createExportHandlers.js` was importing `exportToJpeg` directly). These must be updated to use the new API.
- Always check all dependent code when changing module exports.
- The changes were backward-compatible at the application level because we updated the handlers that used the old API.

---

## What Worked Well

1. **Incremental Refactoring**: Phase 3 built on previous work and didn't introduce breaking changes to public APIs (only internal structure).
2. **Test Coverage**: We added 29 new passing tests across three test files, providing solid validation of the refactored code.
3. **World-Review Feedback**: The first world-review identified critical issues which we systematically addressed before final verification.
4. **Following Conventions**: Used ES modules, factory functions, and no-build-step approach consistently.

---

## What Could Be Improved

1. **Test Infrastructure**: Could benefit from better canvas mocking utilities to allow more thorough unit tests of rendering code.
2. **Documentation**: The `exportSize` parameter in exporters should be documented more clearly for future developers.
3. **Edge Case Testing**: Could add E2E tests to verify actual file exports work correctly in different browsers.

---

## Checklist for Phase 3 Completion

- [x] LayoutGenerator refactored to strategy pattern with OCP compliance
- [x] ExportManager uses registry pattern for multiple formats
- [x] Canvas clearing added to all exporters
- [x] Duplicate canvas clearing logic consolidated in CanvasRenderer
- [x] All unit tests pass (32 tests across 3 new/updated test files)
- [x] World-review verification completed
- [x] Breaking changes to dependent modules fixed

---

## References

- [Phase 3 Implementation Plan](../plans/2026-07-04-architectural-refactoring-implementation.md)
- [World-Review Session 1](../../_agent_docs/project-timeline/sessions/)
- [World-Review Session 2](../../_agent_docs/project-timeline/sessions/)

---

**Next Steps**: Proceed to Phase 4 (Cleanup & Dead Code Removal) after confirming all other phases are stable.
