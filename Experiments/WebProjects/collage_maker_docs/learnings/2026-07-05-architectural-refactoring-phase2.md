# Architectural Refactoring Phase 2 — Learning Debrief

**Date**: 2026-07-05  
**Purpose**: Complete Phase 2 of architectural refactoring, address critical bugs and memory leaks identified through world-review, and capture insights for future development.

---

## What Worked Well

### 1. World-Review Process
The world-review subagent proved invaluable in identifying:
- A **critical bug** (TitleManager missing methods called by handlers) that would have caused runtime errors
- **Memory leak patterns** in BackgroundManager and overlay image handling
- **Vue reactivity concerns** with array reassignments
- **Inconsistencies** in state manager mutation patterns

Without this external review, these issues might have remained hidden until causing problems in production.

### 2. Handler Composition Pattern
Breaking `createCollageMethods.js` (791 lines) into smaller handler modules is working well:
- Clear separation of concerns: handlers handle Vue events, managers handle state mutations
- All handler modules exist and are properly composed
- Testability improved as handlers can be tested with mocks without Vue context

### 3. Action Function Pattern for CropManager
CropManager's use of action functions (`setCropAction`, `resetCropAction`) from `actions.js` is a good model:
- Pure action functions are testable without Vue context
- Decouples state mutations from manager implementation
- Makes undo/redo integration straightforward (if needed)

### 4. Memory Cleanup in Phase 1
Phase 1's focus on memory leaks set the right foundation:
- `ImageLibrary.disposeImage()` and `clearAll()` properly dispose image references
- `beforeUnmount` lifecycle cleanup calls `imageLibrary.clearAll()`
- This pattern was extended to BackgroundManager and overlay handlers

---

## What Didn't Work / Gaps

### 1. TitleManager/Handler Mismatch
The fact that `createTitleHandlers.js` called methods that didn't exist on `TitleManager.js` reveals:
- **Test coverage gap**: No unit tests for the TitleManager API surface area
- **Design communication gap**: Handlers and manager were developed somewhat independently
- **Integration testing needed**: End-to-end UI testing might catch this, but better to have unit tests

**Lesson**: When breaking a God Module into smaller pieces, ensure all interfaces are tested together. Integration tests between handlers and managers are crucial.

### 2. Image Disposal Oversight
BackgroundManager and overlay handlers didn't dispose old images when replacing them:
- This is a subtle memory leak that's easy to miss
- Only caught through systematic review, not typical usage testing
- Reinforces that memory leaks require explicit cleanup patterns

**Lesson**: Any code that replaces an image reference should explicitly null out the old reference. Create utility functions or enforce this pattern in managers.

### 3. Vue Reactivity with Arrays
The TitleManager's `mergeAdjacentRuns()` and `applyFormattingToRange()` reassigned `state.titleRuns` instead of mutating the existing array:
- Vue 3 detects reassignment, but it creates a new array reference
- External observers or code that caches the array reference will become stale
- Using `splice()` or `length = 0; push()` preserves the reference

**Lesson**: Even with Vue 3's reactivity system, preserving array references is better for predictability and external observers. Use mutations over reassignments when possible.

---

## What Was Confusing

### 1. Action Function Scope
Determining which state changes should use action functions vs. direct mutation was ambiguous:
- CropManager uses actions (complex data structures, potential undo)
- BackgroundManager uses direct mutation (simple primitive values)
- TitleManager text operations don't use actions (no undo integration currently)

**Clarification**: Action functions are most valuable when:
- State mutations are complex and need to be testable in isolation
- You anticipate needing undo/redo functionality
- The same mutation logic needs to be used in multiple contexts

For simple UI configuration changes (background color, layout style), direct mutation is acceptable.

### 2. Callback Naming Inconsistency
State managers use different callback names:
- `onCropChanged` (CropManager)
- `onChange` (BackgroundManager, TitleManager)

This isn't a critical issue but adds cognitive load when switching between managers. However, fixing it requires renaming and could break existing code if not done carefully.

**Lesson**: Establish a naming convention early (e.g., `onStateChange`, `onUpdate`) and document it. But don't refactor for consistency alone if the risk outweighs the benefit.

---

## Skill Improvements & Updates Needed

### 1. Update `building-web-apps` Skill
Add or enhance these references:

#### `references/vue-options-api.md`
- **Array Mutation Pattern**: "Prefer array mutations (`splice()`, `length = 0; push()`) over reassignment to preserve Vue reactivity reference. While Vue 3 detects reassignments, mutations maintain the same array reference for external observers."

#### `references/memory-management.md`
- **Image Disposal Pattern**: "When replacing an image reference (background, overlay, etc.), explicitly null out the old reference before assigning the new one to allow garbage collection."
- **disposeImageItem() Utility**: "Use a centralized utility function like `disposeImageItem()` to ensure consistent disposal of image items."

#### `references/testing.md`
- **Integration Test Pattern**: "After breaking a God Module into smaller components, write integration tests that verify handlers and managers work together. Test the composed API, not just individual units."

### 2. Create New Reference: `references/manager-patterns.md`
Document the different patterns for state managers:
- Action-based managers (CropManager)
- Direct mutation managers (BackgroundManager)
- When to use each pattern
- Integration with undo/redo systems

### 3. Update World-Review Checklist
Add these items to the world-review checklist:
- "Check for missing methods in managers that are called by handlers"
- "Verify image disposal when replacing image references"
- "Review array assignments for potential reference preservation issues"
- "Confirm all state mutation patterns are intentional and documented"

---

## Key Insights for Future Refactoring

### 1. Incremental Refactoring with Testing
The phased approach worked well:
- **Phase 1**: Memory leaks (critical, prevents issues during subsequent refactoring)
- **Phase 2**: Architecture decoupling (breaks down God Module, improves testability)
- **Phase 3**: Extensibility (strategy patterns, OCP compliance)
- **Phase 4**: Cleanup (dead code removal)

Each phase is independently testable and provides incremental value. Don't try to do everything at once.

### 2. World-Review at Critical Junctures
Schedule world-review after:
- Breaking down a large module into smaller pieces
- Completing a major phase of refactoring
- Before finalizing any new architectural pattern

An external reviewer catches blind spots and ensures consistency.

### 3. Memory Management is Everyone's Responsibility
Memory leaks are subtle and easily introduced:
- Always dispose old image references before replacing them
- Clean up in `beforeUnmount` lifecycle hooks
- Use centralized disposal utilities
- Test memory usage with DevTools after major changes

### 4. Document Your Intentions
Comments like "This is a configuration change not tracked by UndoManager" prevent future confusion. When you make a design decision (direct mutation vs. actions, undoable vs. non-undoable), document why.

---

## Next Steps

1. **Complete Phase 3**: Implement strategy pattern for LayoutGenerator and multiple export formats
2. **Add Integration Tests**: Write tests that verify handlers work with managers together
3. **Consider Undo for Title**: Evaluate if title text formatting should be undoable; if so, refactor to use action functions
4. **Standardize Callbacks (Optional)**: If risk is low, rename callbacks to consistent `onStateChange` pattern
5. **Create New Reference Documents**: As identified above

---

## Summary

Phase 2 of architectural refactoring was successfully completed with the help of world-review. The process revealed critical bugs, memory leaks, and Vue reactivity concerns that would have been difficult to catch through standard testing alone. The handler composition pattern is sound, and the phased approach allows for incremental improvements with continuous testing. Key learnings around image disposal, array mutations, and action function scoping will inform future development and should be captured in updated skills and references.

**Outcome**: Success — All unit tests pass (875 total passes, 0 failures). Critical bug fixed, memory leaks addressed, architecture more maintainable.

---

**Status**: Closed  
**Follow-up**: Phase 3 extensibility improvements
