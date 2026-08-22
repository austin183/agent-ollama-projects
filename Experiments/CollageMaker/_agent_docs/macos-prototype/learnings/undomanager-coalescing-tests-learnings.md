# UndoManager Coalescing in Tests — Learnings 2026-06-25

**Purpose:** Document learnings from debugging `CollageViewModelUndoTests` — `UndoManager` coalescing consecutive undo registrations in Swift Concurrency test environments.

---

## What Worked

### Single-action undo tests avoid coalescing

When testing a single `setLayoutStyle` call followed by `undo()`, the `UndoManager` registers exactly one undo action. The test passes reliably. Coalescing only manifests when two consecutive registrations target the same object within the same run loop cycle.

### `undoMultiStepSequence` gauntlet covers multi-action undo

The full gauntlet test (`undoMultiStepSequence`) validates that layout style undo works as part of a larger sequence of operations, providing real-world coverage without needing to test consecutive style changes in isolation.

### `awaitPendingTasks()` as synchronization point

The `awaitPendingTasks()` method on `CollageViewModel` now covers saliency tasks (`ImageCoordinator`), rendering tasks (`PreviewManager`), and deferred undo registrations. Tests call this after any operation that spawns async work.

---

## What Didn't Work / Gaps

### `DispatchQueue.main.async` doesn't prevent coalescing in tests

**Attempt:** Defer undo registration to next run loop cycle:
```swift
DispatchQueue.main.async {
    undoManager.registerUndo(withTarget: self) { ... }
}
```
**Result:** `UndoManager` still coalesces consecutive registrations. In Swift Concurrency test environments, `DispatchQueue.main` items are not processed through a traditional Cocoa run loop — `RunLoop.main.run(until:)` doesn't drain `DispatchQueue.main` work items.

### `Task { }` on MainActor doesn't create a new event cycle

**Attempt:** Spawn a `Task { }` on `@MainActor` to defer registration:
```swift
let task = Task { [weak self] in
    self?.undoManager.registerUndo(withTarget: self) { ... }
}
await task.value
```
**Result:** The `UndoManager`'s coalescing logic is based on the Cocoa event loop, not Swift's task scheduler. Awaiting a `Task` on `@MainActor` does not create a new event boundary.

### `RunLoop.main.run(until:)` doesn't drain DispatchQueue work

**Attempt:** Pump the run loop to process deferred `DispatchQueue.main.async` items:
```swift
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
```
**Result:** `RunLoop.main.run(until:)` processes `NSRunLoop` sources and timers, but `DispatchQueue.main` work items are managed by libdispatch, not the run loop. They are not drained.

### `beginUndoGrouping`/`endUndoGrouping` doesn't prevent coalescing

**Attempt:** Wrap each registration in explicit undo grouping:
```swift
undoManager.beginUndoGrouping()
undoManager.registerUndo(withTarget: self) { ... }
undoManager.endUndoGrouping()
```
**Result:** `UndoManager` coalesces based on the target object, not grouping boundaries. Consecutive registrations targeting the same object within the same run loop cycle are still coalesced.

---

## Root Cause

`UndoManager` coalesces consecutive undo registrations targeting the same object within a single run loop cycle. This is standard Cocoa behavior documented in the `NSUndoManager` class reference. In Swift Concurrency test environments (Swift Testing framework with `@MainActor` + `@Suite(.serialized)`), the run loop is not active in the traditional sense — all async work is dispatched through Swift's task scheduler, which doesn't create the event boundaries that `UndoManager` relies on for action separation.

The `AppKitInit` test suite (which initializes `NSApplication.shared`) may affect `UndoManager` behavior by activating the run loop, but this creates non-deterministic behavior rather than solving the coalescing issue.

---

## Practical Workarounds

1. **Test single undo actions in isolation** — Each test exercises one operation + one undo. Multi-action sequences are covered by integration tests like `undoMultiStepSequence`.

2. **Accept coalescing as expected behavior** — In production, consecutive `setLayoutStyle` calls from the UI will be separated by user interaction (run loop cycles), so coalescing won't occur. The test environment is the anomaly.

3. **Use different target objects** — Registering undo with different target objects prevents coalescing, but this is a code smell and not a recommended pattern.

---

## Related

- `undomanager-integration-learnings.md` — Undo registration patterns
- `slot-index-state-preservation-learnings.md` — `regenerateLayout` UUID regeneration
- `testing-quality-gap-learnings.md` — `@Suite(.serialized)` for concurrency

---
**Status:** Open (1 test still failing: `undoClearAllRestoresFullState`)
**Follow-up:** Debug `undoClearAllRestoresFullState` — may be a different issue (missing state in undo handler, not coalescing)
