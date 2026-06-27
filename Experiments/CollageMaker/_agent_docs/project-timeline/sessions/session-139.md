# Performance Review Fixes — Retain Cycle + O(1) Lookups

**Date:** 2026-06-27
**Plan reference:** `_agent_docs/plans/2026-06-27-performance-review-fixes.md` (Phases 1 & 2)
**Goal:** Fix ImageCoordinator retain cycle and replace O(N) panel lookups with O(1) dictionary lookups.

---

## Phase 1 — Retain Cycle Fix

### Changes

- `ImageCoordinator.swift:34`: Changed `var target: ImageCoordinationTarget!` → `weak var target: (any ImageCoordinationTarget)?`
- All call sites updated to optional chaining (`target?.method()`) or guard-let pattern in `scheduleSaliencyAnalysis`

### Verified

- 473 tests pass, build succeeds
- No behavioral change expected — weak reference is valid for VM lifetime

---

## Phase 2 — O(1) Panel Lookups

### Changes

**LayoutManager additions:**
- `panelById: [UUID: ImagePanel]` — panel ID to panel struct
- `panelSlotById: [UUID: Int]` — panel ID to array index
- `panels.didSet` observer calls `rebuildIndexMaps()` to auto-maintain both dictionaries
- `panelForImageIndex(_:)` helper for content-based lookups preserving original ordered semantics

**Collateral cleanup:**
- Removed manual dict population from `regenerateLayout()` and `reset()` — didSet handles it

**Call site replacements:**
- `CollageViewModel.swift:889`: `panels.first(where:)` → `layoutManager.panelById[panelId]`
- `ImageCoordinator.swift:130`: `firstIndex(where:)` → `layoutManager.panelSlotById[panelId]`
- `ImageCoordinator.swift:136`: closure-based search → `layoutManager.panelForImageIndex(_:)`
- `ImageCoordinator.swift:145-146`: two `firstIndex(where:)` → `panelSlotById[]`

### Bug caught by diff-review-g31 and fixed

`panelForImageIndex` initially split into dictionary-first then array-fallback passes, which changed selection priority (assignment always wins over layout position) and introduced non-determinism from dictionary iteration order. Reverted to single-pass `panels.first { ... }` using dictionaries for O(1) condition checks internally.

---

## Verification

- `bash script/run_tests.sh` — 473/473 pass
- `bash script/build_and_run.sh --verify` — BUILD SUCCEEDED
