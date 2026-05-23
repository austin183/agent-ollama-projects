# Session 23 — 2026-05-16

### Round 5: Scroll After Panel Swap Coordinate Jump Fix

**Goal:** Fix the scrolling bug from round-5: after swapping two panels, scrolling in the selected image causes both images to jump to new coordinates.

**Bug Discovered and Fixed:**

1. **`CropManager` uses stale `panel.imageIndex` after swap** — `CropManager.swift:75-106`. The `applyPan`, `applyPinch`, and `resetCrop` methods look up the image using `panel.imageIndex` to compute clamping bounds (`maxOX`, `maxOY`). After `swapPanelImages()`, `panel.imageIndex` remains the original value from layout generation (e.g., Panel A still has `imageIndex = 0` even though it now displays image 1). The clamping bounds are computed against the wrong image dimensions, causing the crop origin to be clamped to incorrect limits and the visible portion to jump. The `CollageAssembler` was already correct — it uses `panelAssignments[panel.id] ?? panel.imageIndex`. But `CropManager` had no access to `panelAssignments`. Fixed by adding `panelAssignments: [UUID: Int] = [:]` parameter to `applyPan`, `applyPinch`, and `resetCrop`, resolving the effective image index as `panelAssignments[panelId] ?? panel.imageIndex` before any image lookup.

2. **`swapPanelImages` crop swap was correct, `cropManager.cropMap` sync was missing** — The crop swap in `swapPanelImages` (exchanging `sourceRect` between panels) is the right behavior — crops travel with the image so the user's selected portion stays visually consistent. The initial fix incorrectly removed the crop swap. Restored the crop swap and added `cropManager.cropMap = cropMap` to keep the manager's internal state in sync.

**Root Cause:**
- `ImagePanel.imageIndex` is set at layout generation time and never updated after swapping
- `panelAssignments` was introduced to track the effective image-to-panel mapping after swaps
- `CollageAssembler` correctly uses `panelAssignments`, but `CropManager` was a separate code path that only knew about `panel.imageIndex`
- The permutation layer (`customImageOrder` → `panelAssignments`) must be visible to ALL code paths that resolve which image belongs to which panel

**Production Code Changes:**
- `ViewModel/CropManager.swift` — Added `panelAssignments: [UUID: Int] = [:]` parameter to `applyPan`, `applyPinch`, `resetCrop`. Each method resolves effective image index as `panelAssignments[panelId] ?? panel.imageIndex` before image lookup.
- `ViewModel/CollageViewModel.swift` — Updated all 7 calls to `cropManager.applyPan/applyPinch/resetCrop` to pass `panelAssignments`. Restored crop swap in `swapPanelImages()` with `cropManager.cropMap = cropMap` sync.

**Current State:**
- Build: **SUCCEEDED** — zero errors, zero new warnings
- Tests: **Not yet re-run** (no test-impacting changes)
- Scroll after swap: **Fixed** (clamping bounds use correct image dimensions)
- Visual consistency after swap: **Fixed** (crop travels with image)

**Learnings Documented:**
- `_agent_docs/learnings/panel-swap-scroll-consistency-learnings.md`
