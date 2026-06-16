# Session 108 — SRP Remediation Phase 3: Decompose ImageCoordinator (C2)

**Date:** 2026-06-16
**Plan:** `_agent_docs/plans/2026-06-15-srp-remediation-plan.md` § Phase 3

## Summary

Implemented Phase 3 of the SRP remediation plan — decomposed `ImageCoordinator` from a second orchestrator with cross-manager reset authority into a domain-specific manager (images, saliency) that returns data for undo. The ViewModel became the single orchestrator for cross-manager operations.

## Changes

### ImageCoordinator: Domain-Only Operations (3.1, 3.3)

**New state structs:**
- `ImageDomainState` — snapshot of `images`, `panels`, `cropMap` for undo restoration
- `SwapState` — snapshot of `customOrder`, panel assignments, and crops for swap undo

**Method signature changes:**
| Before | After |
|--------|-------|
| `clearAll()` — clears all managers, registers undo | `clearDomain() -> ImageDomainState` — clears image library + saliency only, returns state |
| `removeImage(at:)` — registers undo | `removeImage(at:) -> (item, at)?` — returns removed data |
| `moveImages(from:to:)` — registers undo | `moveImages(from:to:) -> [Int]` — returns old order |
| `swapPanelImages(sourceId:targetId:)` — registers undo | `swapPanelImages(sourceId:targetId:) -> SwapState?` — returns swap state |

**Target property:** Changed from `private let target` to `var target` (IUO) to break circular initialization — VM can't pass `self` until `imageCoordinator` is initialized (see learnings).

### CollageViewModel: Orchestrator Methods (3.2, 3.5)

**`imageCoordinator` IUO removed** — now a non-optional `var`, set via post-init `imageCoordinator.target = self` after all stored properties are initialized.

**New methods:**
- `clearAll()` — calls `imageCoordinator.clearDomain()`, then resets layoutManager, cropManager, previewManager, backgroundManager, titleManager, selectedPanelId, errorMessage. Registers full undo with captured state from all managers.
- `removeImage(at:)` — calls coordinator, registers undo (insert + regenerateLayout)
- `moveImages(from:to:)` — calls coordinator, registers undo (restore customImageOrder + regenerateLayout)
- `swapPanelImages(sourceId:targetId:)` — calls coordinator, registers undo (restore order, assignments, crops + regenerateLayout)

### View Updates

- `ContentView.swift:65` — `viewModel.imageCoordinator.clearAll()` → `viewModel.clearAll()`

### Test Updates

- `CollageViewModelTests.swift` — `imageCoordinator.clearAll()` → `clearAll()`, `imageCoordinator.moveImages()` → `moveImages()` (4 tests)
- `ExportFlowTests.swift` — `imageCoordinator.clearAll()` → `clearAll()`, `imageCoordinator.swapPanelImages()` → `swapPanelImages()` (3 tests)

## Verification

- `xcodebuild build` — Succeeded, zero errors (5 warnings: unused return values from coordinator methods in views — Phase 4 will route through VM)
- `xcodebuild test` — All 296 tests passed, zero failures
- `bash script/build_and_run.sh --verify` — Build succeeded, app launched

## Files Changed

| File | Changes |
|------|---------|
| `ViewModel/ImageCoordinator.swift` | Added state structs, `clearAll`→`clearDomain`, undo extracted from 3 methods, `target` IUO |
| `ViewModel/CollageViewModel.swift` | `imageCoordinator` IUO removed, 4 new orchestrator methods, post-init target assignment |
| `ContentView.swift` | `clearAll()` routed through VM |
| `CollageViewModelTests.swift` | 5 call sites updated to VM methods |
| `ExportFlowTests.swift` | 3 call sites updated to VM methods |

## New Learnings

- `circular-init-post-init-assignment.md` — Breaking `self`-before-initialization with IUO + post-init assignment

---
**Status:** Complete
**Follow-up:** Phase 4 (VM-Level Accessors & Mechanical View Pass) from the same plan.
