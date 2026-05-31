# Generation Counter & Actor Queue Wrapper — Learnings

**Date:** 2026-05-31
**Session:** 69
**Purpose:** Document learnings from implementing generation-based stale render discard in PreviewManager and the RenderScheduler actor pattern.

---

## What Worked

### Generation counter to discard stale async results

Task cancellation (`task?.cancel()`) alone is insufficient when rendering work runs on a serial `DispatchQueue`. A cancelled task's work is still submitted to the queue and runs to completion — the continuation just never resumes. But with multiple `update*` calls racing, each creates its own task, and the serial queue processes them FIFO. An older render can complete after a newer one, producing a stale frame that overwrites fresh UI state.

**Fix:** A generation counter at the caller level. Each `update*` call increments its counter before starting work. After `await`, the result is only applied if the captured generation still matches:

```swift
func updatePreview(...) {
    previewGeneration += 1
    let gen = previewGeneration
    previewTask?.cancel()
    previewTask = Task { [weak self, gen, ...] in
        guard let self else { return }
        let result = await assembler.assemblePreviewWithCGImages(...)
        guard gen == self.previewGeneration else { return } // stale, discard
        self.previewImage = result
    }
}
```

**Why this works:** The counter is only ever incremented (never decremented), so a captured `gen` value can only become stale if a newer `update*` call has already incremented past it. The guard is O(1) and runs on the main actor where `previewGeneration` lives.

### Per-panel generation tracking for batch operations

When `updateAllPanelPreviews` calls `updatePanelPreview` in a loop, a single `panelGeneration: Int` counter would only match the last panel's render — every earlier panel's render would see a mismatched generation and be discarded.

**Fix:** `panelGenerations: [UUID: Int]` — one counter per panel ID:

```swift
func updatePanelPreview(..., panelId: UUID) {
    panelGenerations[panelId, default: 0] += 1
    let gen = panelGenerations[panelId]!
    panelPreviewTask?.cancel()
    panelPreviewTask = Task { [weak self, gen, panelId, ...] in
        guard let self, gen == self.panelGenerations[panelId] else { return }
        let result = await assembler.renderPanel(...)
        guard gen == self.panelGenerations[panelId] else { return }
        self.panelRenderedImages[panelId] = result
    }
}
```

Each panel has independent generation tracking. `updateAllPanelPreviews` increments each panel's counter independently, and all renders match their respective generations.

### Dual generation check (pre-await and post-await)

For panel previews, the generation is checked both before and after the `await`:

- **Pre-check** (`guard gen == self.panelGenerations[panelId]` before `await`) — Guards against starting work that's already superseded. If a newer `updatePanelPreview` call for the same panel ran between task creation and task execution, the generation will have advanced and we skip the render entirely.
- **Post-check** (same guard after `await`) — Guards against the result being stale when it completes.

The pre-check is an optimization (saves wasted CPU on the render queue). The post-check is correctness (ensures stale results don't update UI state). For simpler render types (preview, background, title) where only one task exists at a time, the post-check alone is sufficient.

### Actor as DispatchQueue wrapper

Phase 2's `withCheckedContinuation` + `queue.async` pattern required each of the 5 rendering methods to contain the same 4-line boilerplate:

```swift
await withCheckedContinuation { cont in
    renderQueue.async {
        // ... method-specific rendering ...
        cont.resume(returning: result)
    }
}
```

Phase 3 consolidates this into a `RenderScheduler` actor:

```swift
actor RenderScheduler {
    private let queue = DispatchQueue(label: "...render")

    func render<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { cont in
            queue.async {
                let result = work()
                cont.resume(returning: result)
            }
        }
    }
}
```

Callers become:
```swift
await scheduler.render {
    // ... method-specific rendering ...
    return result
}
```

**Benefits:**
- Continuation boilerplate lives in one place
- Each rendering method reads like a synchronous function with `return` instead of `cont.resume(returning:)`
- The actor boundary provides structured concurrency integration (cancellation propagation, task grouping)
- `@escaping` on the closure parameter is required because `withCheckedContinuation` captures it for later execution on the queue thread

## What Didn't Work / Gaps

### `@escaping` required on actor closure parameter

The initial attempt used `@Sendable () -> T` without `@escaping`, producing "Escaping closure captures non-escaping parameter" because `withCheckedContinuation` stores the closure for later execution. Adding `@escaping` is correct — the closure escapes to the queue thread.

### Wasted CPU on cancelled renders

Generation counters discard stale results at the caller level, but the rendering work still executes on the serial queue. A future optimization could explore queue-level cancellation (e.g., checking `Task.isCancelled` inside the render closure and returning early), but this adds complexity inside rendering methods that should be focused on CoreGraphics work.

## Key Patterns

### When to use generation counters

| Scenario | Solution |
|---|---|
| Single in-flight async task, cancel before new call | `task?.cancel()` + new task |
| Serial queue, cancelled work still runs FIFO | Generation counter at caller level |
| Batch operations (per-item updates) | Per-item generation: `[ID: Int]` |
| Need to skip starting superseded work | Pre-await generation check |
| Need to skip applying stale results | Post-await generation check |

### Actor wrapping DispatchQueue — when and when not to

| Consideration | Actor wrapper | Raw `withCheckedContinuation` |
|---|---|---|
| Single method needs async queue bridge | Overkill — inline the continuation | Preferred |
| 3+ methods share the same queue | Actor consolidates boilerplate | Repetitive |
| Need actor isolation for other state | Actor is natural fit | Not available |
| Method-specific queue configuration | Not suitable — each method needs its own queue | Natural |

## Skill Improvements

- `building-macos-apps/references/state/swift-concurrency.md`: Add generation counter pattern for discarding stale async results when serial queue work runs to completion despite task cancellation
- `building-macos-apps/references/state/swift-concurrency.md`: Add actor-as-DispatchQueue-wrapper pattern for consolidating `withCheckedContinuation` boilerplate across multiple methods

## Next Steps

- All 3 phases of preview update performance plan are complete
- Manual stress testing: rapid slider drags, scroll-wheel panning, pinch gestures should feel responsive with no "catch up" delay

---
**Status:** Closed
**Follow-up:** Manual performance verification
