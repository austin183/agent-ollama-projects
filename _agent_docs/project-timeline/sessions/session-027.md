# Session 27 — 2026-05-18

### Round 9: Title Resize Handle / Panel Drag Overlap Fix

**Goal:** Fix bug from round-9: clicking and dragging on the outside edge of the Title resize handles (left/right edge of the Title text image) causes the panel underneath to also be picked up for drag-and-drop rearrangement.

**Bugs Discovered and Fixed:**

1. **Panel drag fires alongside title resize gesture** — `CollageEditorView.swift:267-298`. Both `simultaneousGesture` handlers fire their `onChanged` in the same pass. The existing `guard !viewModel.isDraggingTitle` in the panel drag `onChanged` (line 270) only works after the first render cycle, but by then `dragSourcePanelId` is already set. The `@Observable` property update doesn't propagate until the next render cycle, so both gestures run with stale state. Fixed with **preemptive region exclusion**: the panel drag `onChanged` now directly checks if `startLocation` falls within the title's left or right resize handle threshold regions (`resizeHandleWidth + 2`), matching the same logic as the title gesture. This check runs before any state mutation, avoiding cross-gesture timing issues.

2. **Panel `onEnded` has no title guard** — `CollageEditorView.swift:288-297`. The panel drag `onEnded` callback had no check for `isDraggingTitle`, so if `dragSourcePanelId` was set from any edge case, it would unconditionally call `swapPanelImages()`. Fixed by adding `guard !viewModel.isDraggingTitle` with cleanup at the top of `onEnded`.

**Files Modified:**
- `Views/CollageEditorView.swift` — Panel drag `onChanged` now checks title resize handle regions preemptively (lines 273-286); `onEnded` guards against title drag state (lines 300-305)

**Build Issues Encountered and Resolved:**
- None — build succeeded on first attempt with zero errors and zero warnings

**Current State:**
- Build: **SUCCEEDED** — zero errors, zero new warnings
- Tests: **Not yet re-run** (no test-impacting changes)
- Title resize / panel drag overlap: **Fixed** (dragging on title resize handles no longer triggers panel rearrangement)

**Learnings Documented:**
- Preemptive region exclusion (checking higher-priority gesture region directly in lower-priority handler) is the correct pattern for overlapping `simultaneousGesture` hit regions — documented in `swiftui-gestures.md` reference
