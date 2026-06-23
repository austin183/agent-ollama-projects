# deinit Outside Actor Isolation — Learnings

**Date:** 2026-06-23
**Context:** Adding `deinit` to `@MainActor` `Debouncer` class to cancel pending tasks on deallocation.

## Problem

`Debouncer` is a `@MainActor` class that stores `[String: Task<Void, Never>]`. When its owner (`CollageViewModel`) is deallocated, pending debounce tasks continue running with dangling captures. The fix is to add a `deinit` that cancels all tasks.

The naive implementation calls the existing `cancelAll()` method:

```swift
@MainActor
final class Debouncer {
    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    deinit {
        cancelAll()  // ERROR: Call to main actor-isolated instance method in a synchronous nonisolated context
    }
}
```

**This fails to compile.** `deinit` runs outside any actor isolation — even though the class is `@MainActor`, the destructor executes in a nonisolated context.

## Fix

Inline the `Sendable` operations directly in `deinit`:

```swift
deinit {
    tasks.values.forEach { $0.cancel() }
}
```

`Task.cancel()` is `Sendable` and safe to call from any isolation context. We only need to cancel — we don't need `tasks.removeAll()` because the object is being deallocated anyway.

## General Rule

**`deinit` always runs outside actor isolation, regardless of the class's actor annotation.** You cannot call any actor-isolated method from `deinit`. Only `Sendable` operations (or `nonisolated` methods) are available.

| Operation | Safe in `deinit`? |
|-----------|-------------------|
| `Task.cancel()` | Yes (`Sendable`) |
| `@MainActor` method call | No |
| `nonisolated` method call | Yes |
| Stored property access | Yes (reading own state) |

## Related

- `swift6-synchronous-closure-concurrency-learnings.md` — Swift 6 concurrency in synchronous closures
- `computed-property-actor-boundary-learnings.md` — computed properties evaluate on destination thread

---
**Status**: Closed
**Follow-up**: None
