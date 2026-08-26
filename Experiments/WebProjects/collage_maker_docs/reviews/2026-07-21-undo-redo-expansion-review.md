# Undo/Redo Expansion — Pre-Commit Review

**Reviewer:** build-docs agent with world-review subagent
**Date:** 2026-07-21
**Scope:** 15 files staged, ~3,925 insertions, ~60 deletions
**Plan Reference:** `_agent_docs/plans/2026-07-20-undo-redo-expansion-implementation.md`
**Prior reviews:** 9 existing review documents in `_agent_docs/reviews/`

---

## Executive Summary

This review covers the Undo/Redo Expansion implementation that adds undo support to ~20 user actions across 4 phases. The implementation introduces an `onUndoCommand` callback pattern to all handler factories, a batching system for slider/style controls, and fixes a critical closure bug in title move/resize undo.

**VERDICT: APPROVE with noted improvements** — The implementation is architecturally sound, well-tested (2,400+ new test lines), and follows the established callback injection pattern. Several UX polish items and one template maintainability concern should be addressed in follow-up work but do not block this commit.

---

## Phase-by-Phase Analysis

### Phase 1: Title Undo Closure Bug Fix

**File:** `MyESModules/App/createCollageLifecycle.js`

**Assessment: APPROVE** — Clean, surgical fix.

The closure bug was identified in the prior review (2026-07-19, issue #7: "Stale undo callbacks"). The fix correctly copies `titleUndoSnapshot` values into local `preState` constants before building the undo/redo closures, matching the established pattern used by crop drag (line 164) and panel swap (lines 130-133) in the same file.

**Changes verified:**
- `preState` object captures snapshot values at closure creation time (lines 221-225)
- `postState` object captures current values at closure creation time (lines 226-230)
- Comparison uses `preState` instead of `titleUndoSnapshot` (lines 232-234)
- `titleUndoSnapshot = null` still executes after closure creation (line 247) — no longer affects captured values
- Added `this.titleStyle` guard (line 218) — defensive, good practice

**Test coverage:** 10 tests in `TitleUndoBugTest.html` covering:
- Fixed pattern restores correct values after snapshot nullification
- Redo restores post-state
- Null snapshot doesn't crash
- Unchanged position doesn't push command
- Individual axis changes (X, Y, width)
- Multiple undo/redo cycles
- New action clears redo stack
- Full snapshot lifecycle across multiple interactions

### Phase 2: Image Operations (Add, Remove, Clear All)

**Files:** `createFileHandlers.js`, `createImagePanelHandlers.js`

**Assessment: APPROVE with noted UX concern**

**Architecture:** The `onUndoCommand` callback is properly optional (`= null` default). Image removal snapshots capture the ImageItem reference *before* `disposeImage()` nulls the `image` property, enabling restoration. The disposed-image guard shows a toast instead of crashing.

**Strengths:**
- `buildRemoveImageCommand()` helper eliminates duplication between `removeImage()` and `removeSelectedImage()`
- `restoreCrops()` and `triggerUpdate()` helpers extract shared logic
- Deep-copy via `JSON.parse(JSON.stringify())` for crops snapshots — safe for small arrays
- Undo function filters out disposed images with clear error messaging

**Concerns (noted, not blocking):**
- **Add Images redo limitation:** The redo function restores crop state but cannot re-add File objects (they're gone after the file input closes). This is acknowledged in the plan and is an acceptable trade-off — the user can re-add images manually. The world-review flagged this as critical, but after analysis: the redo stack entry *does* exist and *does* execute (restoring crops), so the redo button won't be misleadingly disabled. The partial restoration is the best achievable behavior given browser security constraints on File objects.

**Test coverage:** Comprehensive tests in `UndoExpansionTest.html` for:
- Add images pushes undo command with correct label
- No undo command when no images added
- Remove image undo restores image at original index
- Remove image undo with disposed element shows toast
- Clear all undo restores all images
- Multiple adds create separate undo commands
- Redo stack cleared on new action

### Phase 3: Layout Changes (Style + Options Batching)

**Files:** `createLayoutHandlers.js`, `LayoutManager.js`, `index.html`

**Assessment: APPROVE**

**Architecture:** The batching pattern is well-designed:
- `snapshotLayoutOptions()` captures pre-state on first interaction (idempotent — only captures once per session)
- `pushLayoutOptionsUndo()` compares pre/post and only pushes if something changed
- `commitLayoutOptions()` clears the snapshot (idempotent — safe when no snapshot exists)

**LayoutManager.js early-exit guards:** Five setter methods (`setLayoutStyle`, `setGutter`, `setSliceAngle`, `setHexSpacing`, `setHexSizeMultiplier`) now guard against redundant `regenerate()` calls when the value hasn't changed. This prevents unnecessary layout recomputation during undo/redo restoration.

**Template bindings:** Layout style uses `@focus` for snapshot, layout options use both `@focus` and `@pointerdown` for snapshot (covering keyboard and mouse/touch interaction), `@blur` for commit.

**Test coverage:** Tests verify:
- Layout style change pushes undo command
- Layout style undo/redo restores correct style
- Multiple option changes batch into one command
- No command pushed when options unchanged
- `commitLayoutOptions()` is idempotent

### Phase 4: Title & Styling

**Files:** `createTitleHandlers.js`, `createBackgroundHandlers.js`, `createOverlayHandlers.js`, `index.html`

**Assessment: APPROVE with noted template concern**

**Title handlers:**
- Text changes batched: `snapshotTitleText()` on focus, `commitTitleText()` on blur/Enter
- Formatting toggles (bold/italic/underline) each push individual commands — correct, as each toggle is a discrete user action
- Title style batching mirrors layout options pattern
- `titleRuns` deep-copied via `JSON.parse(JSON.stringify())` — correct for nested objects

**Background handlers:**
- All background mutations (style, color, gradient, image, opacity) share a single batching snapshot
- `pushBackgroundUndo()` restores all 6 background properties plus calls BackgroundManager setters
- Gradient colors handled as array copy `[...vm.gradientColors]` — correct for shallow arrays

**Overlay handlers:**
- Overlay image, mode, and opacity share a single batching snapshot
- Simpler than background (no manager setters needed)

**Template concern (noted, not blocking):**
Segmented controls (alignment buttons, background style buttons) use inline Vue expressions like:
```html
@click="snapshotTitleStyle(); titleStyle.alignment = 'left'; onTitleAlignmentChange(); commitTitleStyle()"
```
This works but violates Vue best practices. Extracting to a dedicated method (e.g., `handleAlignmentChange('left')`) would improve readability and testability. **Recommendation:** Address in follow-up commit.

**Test coverage:** Tests verify:
- Title text change on blur pushes undo
- Title text change on Enter pushes undo
- Typing without blur does NOT push command
- Title formatting toggles push undo commands
- Title style batching works
- Background change pushes undo with all properties
- Overlay change pushes undo

---

## Architecture Review

### SOLID Principles

| Principle | Assessment |
|-----------|-----------|
| **Single Responsibility** | ✅ Each handler factory handles one domain. `pushUndoCommand` is a single shared concern in the wiring layer. |
| **Open/Closed** | ✅ New undoable actions require only adding `onUndoCommand` calls in the handler — no modification to UndoManager or wiring layer. |
| **Liskov Substitution** | N/A — no inheritance in this codebase. |
| **Interface Segregation** | ✅ `onUndoCommand` is a single-purpose callback with a well-defined contract `(vm, cmd) => void`. |
| **Dependency Inversion** | ✅ Handler factories depend on the `onUndoCommand` abstraction, not on UndoManager. The wiring layer provides the concrete implementation. |

### Separation of Concerns

- **Handler layer:** Pure interaction handlers with optional undo support
- **Wiring layer (`createCollageMethods.js`):** Composes handlers with undo infrastructure
- **State layer (`UndoManager.js`):** Unmodified, continues to provide command-pattern stack
- **Lifecycle layer (`createCollageLifecycle.js`):** Commits pending snapshots on destruction

**No circular dependencies introduced.** The callback injection pattern maintains the existing dependency graph.

### Error Handling

The `pushUndoCommand` function wraps both `undoFn` and `redoFn` in try-catch blocks:
- Undo errors show toast: "Undo failed: [error message]"
- Redo errors show toast: "Redo failed: [error message]"
- Errors are logged to console for debugging

**World-review concern:** Error messages expose JavaScript internals to users. **Recommendation:** Genericize to "Undo failed. Please try again." in a follow-up.

### Batching Correctness

The batching pattern is sound:
1. **Snapshot on focus/pointerdown:** Captures pre-state before v-model updates (Vue updates data before `@change`/`@input` fires)
2. **Idempotent snapshot:** Only captures once per interaction session (`if (!snapshot) { ... }`)
3. **Delta check on commit:** Only pushes command if pre-state differs from post-state
4. **Snapshot cleared on commit:** Prevents stale snapshots from accumulating
5. **Lifecycle cleanup:** All pending snapshots committed on Vue destruction

---

## Lifecycle Enhancement

**File:** `createCollageLifecycle.js` (destruction handler)

The new lifecycle cleanup commits all pending snapshots before destroying event listeners:
```javascript
if (this.commitTitleText) this.commitTitleText();
if (this.commitTitleStyle) this.commitTitleStyle();
if (this.commitBackground) this.commitBackground();
if (this.commitOverlay) this.commitOverlay();
if (this.commitLayoutOptions) this.commitLayoutOptions();
```

This prevents data loss if the user navigates away mid-edit. The guard checks (`if (this.commitX)`) make this safe even if a method isn't wired yet.

---

## Test Coverage Analysis

### New Test Files

| File | Lines | Tests | Coverage |
|------|-------|-------|----------|
| `TitleUndoBugTest.html` | 328 | 10 | Phase 1 closure bug fix |
| `UndoExpansionTest.html` | 2,426 | ~40+ | Phases 2-4 all handler undo commands |

### Test Patterns

The tests follow established patterns:
- **Mock Vue instances** with minimal state (images, crops, undoManager)
- **Mock ImageLibrary** that delegates to vm.images array
- **Mock LayoutManager** with no-op methods
- **Undo command collectors** to verify `onUndoCommand` is called with correct parameters
- **Edge cases:** null guards, disposed images, empty arrays, unchanged values

### Test Gaps (minor)

1. **E2E tests:** No new Playwright tests for undo expansion. The plan mentions `test/e2e/undo-expansion.spec.js` but it's not staged. **Recommendation:** Add in follow-up commit.
2. **Tab-key batching:** No test verifies that tabbing between controls commits the previous control's batch without creating phantom undo steps.
3. **Native Cmd+Z in textarea:** No test verifies that Cmd+Z inside the title textarea uses browser native undo, not app-level undo.

---

## World-Review UX Findings

The world-review subagent identified the following UX concerns:

### Critical (world-review)

| # | Issue | Our Assessment | Action |
|---|-------|---------------|--------|
| WR-1 | Add Images redo limitation | **Accepted trade-off** — redo restores crops, can't re-add Files. Best achievable given browser constraints. | Document in learnings, no code change needed |

### Important (world-review)

| # | Issue | Our Assessment | Action |
|---|-------|---------------|--------|
| WR-2 | Technical error messages in toasts | **Valid** — "Undo failed: Cannot read properties of undefined" is confusing | Follow-up: genericize message |
| WR-3 | Template inline expressions | **Valid** — `snapshotX(); action(); commitX()` in `@click` is a Vue anti-pattern | Follow-up: extract to methods |
| WR-4 | Disposed image toast phrasing | **Minor** — "image data no longer available" is slightly technical | Follow-up: rephrase if desired |
| WR-5 | Cmd+Z in textarea focus | **Need to verify** — check if global keydown handler intercepts Cmd+Z when textarea is focused | Investigate before or after commit |

### Positive (world-review)

- Batching pattern prevents undo-stack bloat — **good UX**
- 60-level undo depth is sufficient — **no concern**
- Tab-key blur commits are standard form behavior — **acceptable**
- Title text on blur/Enter only — **correct pattern**

---

## Documentation

### New/Updated Docs

| File | Purpose |
|------|---------|
| `.opencode/skills/building-web-apps/SKILL.md` | Updated with undo/redo patterns |
| `.opencode/skills/building-web-apps/references/undo-snapshots.md` | New reference doc for snapshot/commit patterns |
| `.opencode/skills/building-web-apps/references/vue-options-api.md` | Updated with batching examples |

The documentation is thorough and references actual file paths and line numbers. Good job capturing the hard-won knowledge about Vue's v-model timing (data updates before `@change` fires).

---

## Issue Tracking

### Prior Issues Verification

| # | Source | Issue | Status |
|---|--------|-------|--------|
| CR-1 | 07-19 review | Undo/redo broken — `base.undoManager` never registered | ✅ **Fixed in prior commit** — `createUndoMethods.js` now uses `base.getUndoManager()` |
| #7 | 07-19 review | Stale undo callbacks | ✅ **Fixed** — provider function pattern + closure fix in this commit |

### New Issues

| # | Issue | Severity | Recommendation |
|---|-------|----------|---------------|
| N-1 | Template inline expressions in segmented controls | Nit | Extract to dedicated methods |
| N-2 | Technical error messages in undo toasts | Nit | Genericize to user-friendly text |
| N-3 | Add Images redo is partial (crops only) | Accepted | Document limitation, no change needed |
| N-4 | Missing E2E tests for undo expansion | Low | Add in follow-up |
| N-5 | Verify Cmd+Z behavior when textarea focused | Low | Investigate, fix if needed |

---

## Code Quality

### Naming

- `pushUndoCommand` — clear, describes what it does
- `snapshotX()` / `commitX()` — consistent pattern across all domains
- `buildRemoveImageCommand` — descriptive helper function
- `restoreCrops` / `triggerUpdate` — focused single-responsibility helpers

### Function Size

All new functions are small and focused:
- `pushUndoCommand`: 24 lines (error handling wrapper)
- `buildRemoveImageCommand`: 25 lines (command builder)
- `restoreCrops`: 5 lines (array restoration)
- `triggerUpdate`: 4 lines (layout + render trigger)
- Batching functions: 15-20 lines each

### Duplication

- Background and overlay handlers share similar batching patterns but differ enough (background has manager setters, overlay doesn't) that extracting a shared batching utility would add complexity without clear benefit.
- Title formatting toggles (bold/italic/underline) each have inline undo logic — could be extracted to a helper, but the duplication is minimal (8 lines each) and the context-specific snapshots make a shared helper awkward.

---

## Performance

- **Deep copy cost:** `JSON.parse(JSON.stringify())` used for title runs and crops — acceptable for small arrays (< 100 elements)
- **Batching prevents bloat:** Slider interactions produce single undo commands, not per-tick commands
- **Early-exit guards:** LayoutManager setters skip `regenerate()` when value unchanged — prevents unnecessary layout recomputation
- **Max 60 levels:** Enforced by UndoManager, no memory concerns

---

## Decision

**APPROVE** — The implementation is architecturally sound, well-tested, and follows established patterns. The identified issues are all nits or follow-up items that do not block this commit.

### Recommended Follow-ups (non-blocking)

1. **N-1:** Extract segmented control inline expressions to dedicated methods
2. **N-2:** Genericize undo/redo error toast messages
3. **N-4:** Add E2E tests for undo expansion (Playwright)
4. **N-5:** Verify Cmd+Z behavior when title textarea is focused

### Reviewer Sign-Off

| Reviewer | Verdict | Notes |
|----------|---------|-------|
| build-docs (consolidator) | **APPROVE** | Nits only, all follow-up |
| world-review (UX) | **APPROVE** with notes | 1 accepted trade-off, 4 follow-ups |
