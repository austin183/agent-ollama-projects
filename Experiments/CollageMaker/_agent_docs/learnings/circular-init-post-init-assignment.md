# Circular Init Workaround — IUO + Post-Init Assignment

**Date:** 2026-06-16
**Session:** 108
**Purpose:** Document the workaround for Swift's "self used before initialized" error when a class needs `self` as a dependency for a sub-object.

---

## The Problem

When a class creates a sub-object that needs `self` as a dependency (e.g., for a protocol target), Swift requires all stored properties to be initialized before `self` can be referenced. This creates a chicken-and-egg problem:

```swift
@Observable
final class CollageViewModel {
    var imageCoordinator: ImageCoordinator  // must be initialized before `self`

    init(...) {
        // ERROR: variable 'self._imageCoordinator' used before being initialized
        self.imageCoordinator = ImageCoordinator(
            target: self,  // can't use `self` yet
            ...
        )
    }
}
```

With an IUO (`var imageCoordinator: ImageCoordinator!`), you could defer the assignment. But IUOs are unsafe — any accidental access before initialization crashes at runtime.

## The Fix: IUO on the Dependency, Not the Owner

Make the **dependency property** (on the sub-object) an IUO, and set it after the owner's init completes:

```swift
// ImageCoordinator.swift
final class ImageCoordinator {
    var target: ImageCoordinationTarget!  // IUO on the dependency

    init(imageLibrary: ..., layoutManager: ...) {
        // No target parameter — set after VM init
        self.imageLibrary = imageLibrary
        // ...
    }
}

// CollageViewModel.swift
@Observable
final class CollageViewModel {
    var imageCoordinator: ImageCoordinator  // non-optional, safe

    init(...) {
        // All stored properties initialized, now `self` is available
        self.imageCoordinator = ImageCoordinator(
            imageLibrary: imageLibrary,
            ...
        )
        imageCoordinator.target = self  // post-init assignment
    }
}
```

**Why this works:**
- `imageCoordinator` is a non-optional `var` — initialized before `self` is used
- `target` on the coordinator is an IUO — safe because it's set immediately after init, before any method calls
- The init order is: create coordinator → assign to VM → set target → VM is fully alive

## When This Pattern Applies

Use when:
1. A class needs to pass `self` as a dependency to a sub-object during init
2. The sub-object stores the dependency as a protocol reference (DIP pattern)
3. You want the owner property to be non-optional (type-safe, no force-unwrap risk)

## Alternatives Considered

| Approach | Drawback |
|----------|----------|
| IUO on the owner (`var coordinator: Coordinator!`) | Runtime crash if accessed before init completes |
| Two-phase init with factory method | More boilerplate, breaks `@Observable` convenience |
| Optional with `guard let` in every method | Verbose, defeats the purpose of the dependency |
| `lazy var` | Can't use in init, thread-safety overhead |

## Related

- `undomanager-anyobject-protocol-target.md` — UndoManager constraints that motivated the protocol-based DIP
- SRP remediation plan Phase 3 — decomposing ImageCoordinator required this pattern

---
**Status:** Closed
