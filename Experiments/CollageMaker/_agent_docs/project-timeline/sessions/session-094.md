# Session 94 — Post-Round 99 Review Fixes: Phase A Quick Wins

**Date:** 2026-06-08
**Status:** Complete — 2 of 3 Phase A fixes applied, 1 cancelled (false positive)

## What Was Done

### A1: Actor Serialization Bottleneck (CONC-01)

**Problem:** `SaliencyAnalyzer.analyze(_:)` was an actor-isolated method. `analyzeAll` launched concurrent tasks via `withThrowingTaskGroup`, but each task's `await self.analyze(cgImage)` had to hop through the actor executor, serializing all analysis. No parallelism.

**Fix:** Marked `analyze(_:)` as `nonisolated`. The method is a pure function — only local variables, module-level `private let` logger constants, and Vision APIs. Zero `self.` access to actor-isolated state.

**File:** `Services/SaliencyAnalyzer.swift:27`

### A2: PanelShape Y-Axis Flip (COORD-02)

**Problem:** `PanelShape.path(in:)` transforms a `CGPath` from CoreGraphics canvas coordinates (origin=bottom-left) to SwiftUI coordinates (origin=top-left) without a Y-axis flip. The parallelogram selection outline was drawn upside down — shear leaned the wrong direction for diagonal slices.

**Fix:** Applied Y-axis flip to the `CGAffineTransform`:
```swift
var t = CGAffineTransform(translationX: -boundingRect.origin.x * scaleX, y: boundingRect.origin.y * scaleY + rect.height)
t = t.scaledBy(x: scaleX, y: -scaleY)
```

**File:** `Views/CollageEditorView.swift:350-353`

### A3: Duplicate Property (Cancelled)

**Finding:** Plan referenced a duplicate `private let assembler` at `ExportManager.swift:24`. No duplicate exists — the review finding was a false positive or was already fixed. No action needed.

## Files Changed

| File | Changes |
|------|---------|
| `Services/SaliencyAnalyzer.swift` | `nonisolated` on `analyze(_:)` |
| `Views/CollageEditorView.swift` | Y-axis flip in `PanelShape.path(in:)` transform |

## Verification

- `bash script/build_and_run.sh --verify` — BUILD SUCCEEDED
- diff-review agent: both changes verified correct, no issues found

## Key Decisions

- **`nonisolated` is safe** — Verified method accesses zero actor-isolated state. Protocol `SaliencyAnalysis` doesn't specify isolation, so conformance is valid.
- **Y-flip math verified** — Maps CG bottom (`y = boundingRect.origin.y`) to SwiftUI bottom (`y' = rect.height`), CG top to SwiftUI top (`y' = 0`). Shear direction now matches CoreGraphics rendering.

## New Learnings

- **Actor method `nonisolated` enables genuine task parallelism** — See `_agent_docs/learnings/actor-nonisolated-parallelism-learnings.md`

---
**Status:** Complete
**Follow-up:** Phase B (medium fixes) when ready
