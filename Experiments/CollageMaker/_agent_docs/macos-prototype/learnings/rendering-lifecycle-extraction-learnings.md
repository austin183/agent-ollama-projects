# Rendering Lifecycle Extraction & Thread Safety — Learnings

**Date:** 2026-05-28
**Session:** 59
**Purpose:** Document learnings from extracting PreviewManager, adding RenderQueue serial dispatch, and decoupling ScrollPanManager.

---

## What Worked

### Rendering lifecycle extraction into dedicated @Observable manager

When `CollageViewModel` owned 5 async rendering tasks (`previewTask`, `backgroundTask`, `titleTask`, `panelPreviewTask`, `previewDebounceTask`) plus 4 pieces of rendered image state, the class was doing two things: orchestrating user actions AND managing rendering lifecycle. Extracting the rendering concerns into `PreviewManager` (@Observable + @MainActor) gave us:

- **Clear single responsibility** — ViewModel triggers renders, manager owns the task lifecycle and image state
- **Cleaner computed property delegation** — ViewModel exposes `previewImage`, `previewBackgroundImage`, `panelRenderedImages`, `titleImage` as computed properties reading from `previewManager`. This scales the delegation pattern from session-058 to a full subsystem.
- **Testable in isolation** — `PreviewManager` can be tested with a `MockAssembler` without constructing a full ViewModel

### Serial dispatch queue for NSGraphicsContext.current thread safety

Each `Task.detached` rendering call creates its own `NSBitmapImageRep` and sets `NSGraphicsContext.current` to a new context. The assumption was that each task has an isolated context. But concurrent tasks can interleave between `NSGraphicsContext.saveGraphicsState()` and `NSGraphicsContext.current = ...`, causing one task's `current` to be clobbered.

**Fix:** A serial `DispatchQueue(label: "...render")` wrapping each rendering method's body. This is simpler than an actor (no async overhead) and sufficient since the rendering is already off-main-actor via `Task.detached`.

### Pure accumulator manager pattern

`ScrollPanManager` was refactored from accepting crop-capturing closures (`applyLive: { ... crop logic ... }, commit: { ... crop logic ... }`) to being a pure accumulator. The manager now only:
- Tracks active panel ID
- Accumulates scroll deltas with sensitivity
- Exposes `accumulator` and `activePanelId`

The ViewModel owns crop computation, commit timing, and preview scheduling. This inverts the dependency: the manager knows nothing about crops, panels, or images.

## What Didn't Work / Gaps

### MockAssembler.renderTitle returns nil in tests

The existing `MockAssembler` in `CollageViewModelTests` returns `nil` for `renderTitle`. When `PreviewManagerTests` used the same mock, `updateTitleImageRendersImage` failed because the mock returned `nil` for non-empty strings. **Fix:** Create a dedicated test assembler that returns `NSImage(size: canvasSize)` for non-empty title strings.

### Task pattern for @Observable state updates from detached work

The pattern `Task { [weak self] in let result = await Task.detached { ... }.value; self.property = result }` is needed when:
1. You need to capture `self` (an @Observable @MainActor class) to update state
2. The rendering work must run off-main-actor (NSGraphicsContext is not thread-safe)
3. You want cancellation to propagate

This differs from the original `Task.detached { [weak self] ... Task { @MainActor in self.property = result } }` pattern because `await Task.detached { ... }.value` allows the outer `Task` (which inherits MainActor) to cancel the inner work naturally.

## Key Patterns

### When to extract a manager from a ViewModel

| Signal | Threshold |
|---|---|
| Async task count | 3+ related tasks |
| State properties | 3+ related stored properties |
| Method responsibility | Methods doing both orchestration AND rendering |
| Test complexity | Tests need to mock rendering separately from business logic |

### NSGraphicsContext thread safety decision tree

| Scenario | Risk | Mitigation |
|---|---|---|
| Single rendering call per task | Low | `saveGraphicsState()` / `restoreGraphicsState()` sufficient |
| Multiple concurrent tasks, each with own bitmap | Medium | Serial `DispatchQueue` wraps each method |
| Shared bitmap across tasks | High | Must serialize + coordinate access |

### Manager coupling spectrum

```
Tightly coupled: Manager accepts closures capturing domain state
Moderately coupled: Manager returns events, caller handles logic
Pure accumulator: Manager only stores raw data, caller owns all logic
```

Prefer "pure accumulator" when the domain logic (crop computation, undo, preview timing) belongs to the ViewModel. The manager's job is to accumulate and report, not to decide.

## Skill Improvements

- `building-macos-apps/references/state/swift-concurrency.md`: Add the `Task { [weak self] ... await Task.detached { ... }.value }` pattern for @Observable state updates from background work
- `building-macos-apps/references/graphics/coreimage-filters.md`: Add note about `NSGraphicsContext.current` thread safety with concurrent `Task.detached` rendering — serial `DispatchQueue` as mitigation

## Next Steps

- Fix `PreviewManagerTests/updateTitleImageRendersImage` test with dedicated test assembler
- Consider documenting the "pure accumulator" manager pattern in the skill

---
**Status:** Closed
**Follow-up:** Deferred items from arch review (M5 memory retention, LayoutManager/ExportManager extraction)
