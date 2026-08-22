# Session 17 — 2026-05-15

### Round 4.1: Fix Overlapping Title/Panel Gestures

**Goal:** Fix the overlapping actions bug from round-4.1: clicking on the title overlay also triggers the panel drag-to-reorder gesture because both `simultaneousGesture` DragGestures fire on the same ZStack.

**Bug Discovered and Fixed:**

1. **Panel drag locks on title region** — `CollageEditorView.swift:226-253`. The panel reorder `DragGesture` hit-tests `value.startLocation` against `scaledPanelFrames` on first `onChanged`. When the title overlaps a panel, `panelAt()` returns the panel underneath, so `dragSourcePanelId` locks before the title drag gesture has a chance to lock. The title drag's `isDraggingTitle` guard fires too late — the panel drag has already captured the gesture. Fixed by checking `scaledTitleFrame.contains(value.startLocation)` before the panel hit-test, returning early if the drag started on the title.

2. **Tap gesture selects panel under title** — `CollageEditorView.swift:273-284`. The `.onTapGesture` hit-tests against `scaledPanelFrames` but doesn't check the title frame. Tapping the title overlay selects the panel underneath instead of doing nothing. Fixed by checking `scaledTitleFrame.contains(location)` before the panel hit-test, returning early if the tap landed on the title.

**Key Design Decision:**
- Title takes priority over panels at the gesture level — both the panel drag and tap gestures check for title overlap first and bail out. The title drag gesture already has its own locking mechanism (`dragTitleLocked` + `isDraggingTitle`), so it will capture the drag independently.
- To interact with a panel underneath the title, the user must drag the title out of the way first.

**Production Code Changes:**
- `Views/CollageEditorView.swift` — Added `scaledTitleFrame.contains(value.startLocation)` guard in panel drag `onChanged` (line 232-234). Added `scaledTitleFrame.contains(location)` guard in `onTapGesture` (line 277-279).

**Current State:**
- Build: **SUCCEEDED** — zero errors, zero new warnings
- Tests: **68 tests pass** (unchanged)
- Title/panel gesture priority: **Fixed** (title wins over panel when they overlap)

**Learnings Documented:**
- `_agent_docs/learnings/gesture-priority-overlapping-regions.md`
