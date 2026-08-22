# Session 126 — Review Fixes Phase 2

**Date:** 2026-06-23
**Plan:** `2026-06-23-review-fixes-plan.md` Phase 2

## Summary

Implemented Phase 2 (data correctness) of the review fixes plan: C0 (SaliencyAnalyzer index mismatch) and C1 (CropInfo Codable path degradation). Both fixes are low-risk, well-scoped. diff-review-g31 caught 2 issues (shadow implementation test, unsafe array access) which were fixed before landing. All tests pass (3 pre-existing failures unrelated).

## Changes

### C0 — SaliencyAnalyzer.analyzeAll index mismatch

**File:** `Services/SaliencyAnalyzer.swift:137-149`

Bug: When individual image analysis fails, the error was logged but the result was silently omitted from the `[Int: SaliencyResult]` dict. The caller (`ImageCoordinator.analyzeSaliency`) enumerated the shorter results array with `.enumerated()`, assigning results to wrong indices — silently corrupting the saliency-to-image mapping.

Fix: Return a fallback `SaliencyResult` for failed indices (image center, 1/3 min-dimension radius, 0.5 confidence). Same fallback pattern already used in `analyze()` for empty-points images.

### C1 — CropInfo Codable preserves .path vertex data

**Files:** `Models/ImagePanel.swift:49-90`, `Models/PanelGeometry.swift:31-47`

Bug: `CropInfo.encode` only persisted `destination.boundingRect`. Deserializing a `.path` geometry replaced the original `CGPath` with a plain rectangle. Diagonal slices and hexagonal layouts silently degraded to rectangular panels after persistence.

Fix: Added `destinationPathVertices` coding key. Encode extracts `[CGPoint]` via `PanelGeometry.extractPathPoints()`. Decode reconstructs the `CGPath` via new `PanelGeometry.path(fromVertices:boundingRect:)` factory. Legacy data without vertex data falls back to a rect path. Added `pathVertices` computed property on `PanelGeometry`.

### diff-review Findings (caught and fixed)

**Shadow implementation:** `PartialFailureSaliencyMock.analyzeAll()` in the test duplicated the production fallback logic verbatim. The test was testing the mock, not the production code. Replaced with `analyzeAllPreservesIndexOrderingForDifferentSizedImages` that exercises the production `SaliencyAnalyzer` with differently-sized images to verify index ordering.

**Unsafe array access:** `PanelGeometry.path(fromVertices:boundingRect:)` accessed `vertices[0]` without an empty-array guard. Added `guard !vertices.isEmpty else { return .rect(boundingRect) }`.

## Tests

- `SaliencyAnalyzerTests`: Added `analyzeAllPreservesIndexOrderingForDifferentSizedImages`
- `CropInfoCodableTests`: Renamed `pathShapeIsLostAfterRoundTrip` → `pathShapeIsPreservedAfterRoundTrip` with vertex assertions. Added `diagonalSliceRoundTripPreservesVertices`, `hexagonalRoundTripPreservesVertices`, `legacyPathWithoutVerticesFallsBackToRectPath`

## Verification

- Build: succeeded
- Tests: `SaliencyAnalyzerTests` and `CropInfoCodableTests` suites pass. Full suite: 3 pre-existing failures (`FontMergerTests/veryLargeTargetSize`, `FontMergerTests/emptyFamilyReturnsBoldSystemFont`, `TitleManagerTests/finishDragCancelsDebouncerAndSaves`)
- diff-review-g31: 2 findings, both fixed

## New Learnings

None. All patterns exercised in this session are already documented:
- Shadow implementation anti-pattern → `cgpath-apply-compiler-crash-testing-learnings.md`
- CGPath construction from vertices → `cgpath-construction-patterns-learnings.md`
- Vertex guard propagation → `polygon-clip-and-vertex-guard-propagation.md`
- Weak switch assertions → `cgpath-apply-compiler-crash-testing-learnings.md`

---
**Status**: Closed
**Follow-up**: Phase 3 (C3, R18, R14, R5, R13) next
