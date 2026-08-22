# Async Protocol Bridge & Sendable Conformance — Learnings

**Date:** 2026-05-30
**Session:** 68
**Purpose:** Document learnings from converting CollageAssembly protocols to async, bridging DispatchQueue with withCheckedContinuation, and adding Sendable conformance to model types.

---

## What Worked

### `withCheckedContinuation` as bridge between serial DispatchQueue and async callers

The existing pattern for off-main-actor rendering was `Task.detached { ... }.value` at every call site. This works but means the caller wraps synchronous work in a detached task, then awaits the result — adding an unnecessary task layer.

**Better pattern:** Make the protocol method itself `async` and use `withCheckedContinuation` to bridge the serial `DispatchQueue`:

```swift
func renderPanel(crop: CropInfo, cgImage: CGImage, panelSize: CGSize) async -> NSImage? {
    await withCheckedContinuation { cont in
        renderQueue.async {
            let result = self.doRendering(crop, cgImage, panelSize)
            cont.resume(returning: result)
        }
    }
}
```

**Why this is better:**
- **Non-blocking queue entry** — `renderQueue.async` returns immediately. The calling thread is freed. Previously `renderQueue.sync` blocked the detached task's thread until the serial queue processed the work.
- **Caller simplification** — `await assembler.renderPanel(...)` instead of `await Task.detached { assembler.renderPanel(...) }.value`. One less task layer, one less closure to capture variables in.
- **Serial queue retained** — `NSGraphicsContext.current` thread safety is preserved because the underlying queue is still serial.
- **Cancellation propagates** — If the calling `Task` is cancelled, `withCheckedContinuation` suspends indefinitely (the continuation is never resumed), which is the correct cancellation behavior. The work may still complete on the queue thread (wasted CPU) but the result is discarded.

**When to use:** Any time you have a serial `DispatchQueue` protecting a non-thread-safe resource (like `NSGraphicsContext.current`) and you want callers to use structured concurrency (`async/await`) instead of blocking (`sync`).

### `@unchecked Sendable` on model types containing AppKit values

Swift's Sendable checker correctly rejects structs that contain `NSColor`, `NSAttributedString`, or other AppKit types — these are not Sendable. But when these types are only ever accessed on a known thread (the serial render queue), the conformance is safe.

**Pattern:**
```swift
struct BackgroundConfig {
    let color: NSColor       // Not Sendable
    let gradientStartColor: NSColor
    // ...
}

extension BackgroundConfig: @unchecked Sendable {}
```

**Safety justification:** The struct is captured by value in an `async` method parameter, then accessed only inside the `withCheckedContinuation` closure which runs on the serial render queue. No concurrent access occurs.

**For `NSAttributedString` specifically:** Apple's Foundation framework doesn't mark it Sendable. The workaround is an extension in the file that uses it:
```swift
extension NSAttributedString: @unchecked Sendable {}
```
This produces a compiler warning about conforming an imported type to an imported protocol — expected and harmless. If Apple ever adds native Sendable conformance, the warning becomes a conflict (at which point the extension can be removed).

### `async` protocol methods cascade cleanly

Making protocol methods `async` required updating:
1. Protocol declarations
2. Concrete implementations
3. All mock implementations in tests
4. Call sites

The cascade is mechanical and the compiler guides you to every location. No behavioral changes beyond the suspension points.

## What Didn't Work / Gaps

### Cancellation doesn't drain the queue

With `withCheckedContinuation` + `async` queue submission, a cancelled task's work is still submitted to the serial queue and runs to completion. The continuation simply never resumes. This means:

- **Wasted CPU:** Cancelled renders still execute on the queue thread
- **Queue contention:** A cancelled render can delay a newer, valid render behind it

This is acceptable for Phase 2 (non-blocking entry was the goal) but is the motivation for Phase 3's generation counter — stale results are discarded before updating UI state, and future work could explore queue-level cancellation.

### `CollageAssembler` needs `@unchecked Sendable`

The class captures `self` in `@Sendable` closures inside `withCheckedContinuation`. Since `CollageAssembler` contains a `DispatchQueue` (which is Sendable) and only accesses state through the serial queue, `@unchecked Sendable` is safe. An alternative would be explicit `self` captures in every closure, but that's verbose and error-prone.

## Key Patterns

### Async bridge decision tree

| Requirement | Pattern |
|---|---|
| Off-main-actor work, no shared mutable state | `Task.detached { ... }.value` |
| Off-main-actor work, serial queue for thread safety | `withCheckedContinuation` + `queue.async` |
| Off-main-actor work, needs cancellation to stop execution | `Task.detached` with `try Task.checkCancellation()` |
| Main-actor state update after background work | `Task { [weak self] ... self.property = result }` |

### Sendable conformance checklist for model types

When adding `@unchecked Sendable` to a struct:
1. Verify all non-Sendable properties are only accessed on a known thread
2. Document the safety justification in a code comment
3. Prefer `extension TypeName: @unchecked Sendable {}` over inline declaration — keeps the struct declaration clean
4. For imported types (e.g., `NSAttributedString`), put the extension in the file that uses it, not a shared file

## Skill Improvements

- `building-macos-apps/references/state/swift-concurrency.md`: Add `withCheckedContinuation` + `DispatchQueue.async` pattern as an alternative to `Task.detached { ... }.value` when a serial queue is needed for thread safety
- `building-macos-apps/references/graphics/coreimage-filters.md`: Note that `withCheckedContinuation` bridge is the recommended pattern for async-exposed rendering methods backed by a serial queue

## Next Steps

- Phase 3: generation tracking in PreviewManager to discard stale render results

---
**Status:** Closed
**Follow-up:** Phase 3 of preview update performance plan
