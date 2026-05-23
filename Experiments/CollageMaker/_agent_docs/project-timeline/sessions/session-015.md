# Session 15 — 2026-05-14

### Round 3, Phase 3: Panel Drag-to-Reorder

**Goal:** Implement Phase 3 of the round-3 plan: canvas-level panel drag-to-reorder — click and drag a panel to swap its image with another panel's image.

**Files Modified:**
- `ViewModel/CollageViewModel.swift` — Added `customImageOrder: [Int]` (persisted JSON array, permutation of image indices). Added `swapPanelImages(sourceId:targetId:)` — swaps two entries in the permutation, updates `panelAssignments`, triggers preview. Modified `moveImages(from:to:)` to apply inverse permutation mapping so canvas arrangement stays stable when sidebar is reordered. Modified `regenerateLayout()` to reset `customImageOrder` when image count changes, pass it to `LayoutGenerator`, and populate `panelAssignments` from the order. Modified `clearAll()` to reset `customImageOrder`. Added `jsonEncoder`/`jsonDecoder` properties and `buildMoveMapping(fromFirst:fromLast:to:count:)` helper.
- `Services/LayoutGenerator.swift` — Added `imageOrder: [Int]?` parameter to `generate()` and all three layout styles (uniform, hero, mosaic). When provided, each panel slot uses `imageOrder[slot]` as the `imageIndex` instead of the sequential index.
- `Views/CollageEditorView.swift` — Added drag state: `dragSourcePanelId`, `dragTargetPanelId`, `dragCursorLocation`, `dragSourceImageIndex`. Added `DragGesture(minimumDistance: 5)` at ZStack level — hit-tests `startLocation` on first `onChanged` to lock source panel, hit-tests current `location` for target panel, calls `viewModel.swapPanelImages()` on `onEnded`. Visual feedback: cyan stroke on source panel, green stroke on target panel, semi-transparent thumbnail ghost follows cursor. Guards against title drag with `isDraggingTitle` check.

**Key Design Decisions:**
- `customImageOrder` is a permutation, not a reordering of the `images` array — panel frames and crop state stay stable
- `panelAssignments` is populated from `customImageOrder` in `regenerateLayout()` and updated in `swapPanelImages()` — the assembler reads `panelAssignments`, never the permutation directly
- Three `simultaneousGesture` DragGestures now coexist on the ZStack (title drag, panel reorder drag, scroll pan via overlay) — each uses a locking flag and cross-gesture guards
- Ghost cursor uses the pre-generated 64x64 thumbnail, not the full-resolution image

**Build Issues Encountered and Resolved:**
- None — build succeeded on first attempt, all 50 tests passed

**Current State:**
- Build: **SUCCEEDED** — zero errors, zero new warnings
- Tests: **50 tests pass** (all existing tests, no new tests added for Phase 3)
- Panel drag-to-reorder: **Working** (cyan source, green target, ghost cursor)
- Sidebar reorder stability: **Working** (canvas arrangement preserved when sidebar order changes)
- UserDefaults persistence: **Working** (JSON-encoded `[Int]` array)
- Gesture coexistence: **Working** (title drag, panel drag, scroll pan, pinch zoom all coexist)

**Learnings Documented:**
- `_agent_docs/learnings/panel-drag-reorder-learnings.md`
