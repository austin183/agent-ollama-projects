# UndoManager.registerUndo Requires AnyObject — Protocol Target Workaround

**Date:** 2026-06-15
**Session:** 107
**Purpose:** Document the `UndoManager.registerUndo(withTarget:)` constraint when using protocol-based dependency inversion.

---

## The Problem

When refactoring managers to depend on protocols instead of a concrete `CollageViewModel`, undo registration in the coordinator broke:

```swift
// ImageCoordinator depends on ImageCoordinationTarget protocol
private let target: ImageCoordinationTarget

func removeImage(at index: Int) {
    undoManager.registerUndo(withTarget: target) { _ in
        // restore state
    }
}
```

**Error:** `instance method 'registerUndo(withTarget:handler:)' requires that 'any ImageCoordinationTarget' be a class type`

`UndoManager.registerUndo<TargetType>(withTarget:handler:)` has a generic constraint `where TargetType : AnyObject`. A plain protocol (even one marked `AnyObject`) cannot be used directly as the `withTarget` argument when the variable is typed as `any ProtocolName`.

## The Fix: Two-Part Solution

### 1. Make the protocol a class protocol

```swift
protocol ImageCoordinationTarget: AnyObject {
    // ...
}
```

This satisfies the `AnyObject` constraint at the protocol level, but the compiler still rejects `registerUndo(withTarget: target)` because the variable is an existential (`any ImageCoordinationTarget`), not a concrete class type.

### 2. Use `self` as the undo target

```swift
func removeImage(at index: Int) {
    undoManager.registerUndo(withTarget: self) { _ in
        self.imageLibrary.images.insert(removed, at: at)
        self.target.regenerateLayout()
    }
}
```

**Why this works:**
- `self` is the concrete coordinator class, which satisfies `AnyObject`
- The coordinator owns the `target` reference, so it can mutate state through `self.target.property = value`
- The undo closure captures `self` (the coordinator), not the protocol target
- When undo fires, the coordinator is still alive (it's owned by the ViewModel) and can route the mutation back through `target`

## When This Pattern Applies

Any time you:
1. Have broken a circular dependency using a protocol (DIP)
2. Need to register undo actions that mutate state on the protocol target
3. Use `UndoManager` (or any API requiring `AnyObject` targets)

## Alternative (Not Used)

You could pass the concrete ViewModel as a second parameter solely for undo registration:

```swift
init(target: ImageCoordinationTarget, undoTarget: CollageViewModel)
```

This defeats the purpose of the protocol abstraction — the coordinator would still import `CollageViewModel`. The `self`-as-target pattern is cleaner.

## Related

- `undomanager-integration-learnings.md` — original undo patterns (property assignment, collection mutations)
- SRP remediation plan Phase 2 — breaking C1 circular dependencies

---
**Status:** Closed
