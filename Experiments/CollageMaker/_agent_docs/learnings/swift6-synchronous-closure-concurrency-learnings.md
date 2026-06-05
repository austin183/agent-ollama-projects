# Swift 6 Concurrency in Synchronous Dispatch Queue Closures

**Date:** 2026-06-05
**Context:** Writing RenderSchedulerTests — testing an actor that bridges async/await to synchronous DispatchQueue work

## Problem

`RenderScheduler.render<T>(_ work: @escaping @Sendable () -> T) async -> T` takes a **synchronous** closure — it runs on a `DispatchQueue` via `withCheckedContinuation`. The closure signature is `@Sendable () -> T`, not `@Sendable () async -> T`.

In Swift 6 strict concurrency mode:
- `await` inside a synchronous closure is a compile error: *"cannot pass function of type '@concurrent @Sendable () async -> T' to parameter expecting synchronous function type"*
- `actor` methods require `await` to call, but the closure can't use `await`
- Mutable captured state from concurrent tasks causes *"mutation of captured var in concurrently-executing code"*

## Solution: Thread-Safe Class with NSLock

```swift
final class ThreadSafeArray<Element: Sendable>: @unchecked Sendable {
    private var items: [Element] = []
    private let lock = NSLock()

    func append(_ item: Element) {
        lock.lock()
        defer { lock.unlock() }
        items.append(item)
    }

    func getItems() -> [Element] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}
```

Usage in test:
```swift
let tracker = ThreadSafeArray<String>()
await scheduler.render {
    tracker.append("enter")  // Synchronous, thread-safe
    Thread.sleep(forTimeInterval: 0.001)
    tracker.append("exit")
    return ()
}
```

## Why Not Other Approaches

| Approach | Why It Doesn't Work |
|----------|-------------------|
| `actor` + `await` | Closure is synchronous — `await` is illegal |
| `NSLock` on local var | Swift 6 forbids mutation of captured vars in concurrent code |
| `@MainActor` | Queue runs on background thread, not main actor |
| `UnsafeMutablePointer` | Unsafe, defeats the purpose of safe concurrency |

## Key Points

- `@unchecked Sendable` is safe here because `NSLock` provides mutual exclusion for all access to `items`
- `Thread.sleep(forTimeInterval:)` is the synchronous equivalent of `Task.sleep` — works inside dispatch queue closures
- The pattern applies whenever you need to collect results from synchronous closures that may execute concurrently on different threads

## Related

- `async-protocol-bridge-learnings.md` — `withCheckedContinuation` for bridging dispatch queues to async/await
- `testing-async-viewmodels-coordinate-math-learnings.md` — testing async ViewModel patterns
