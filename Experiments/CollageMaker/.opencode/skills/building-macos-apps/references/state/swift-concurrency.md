# Swift Concurrency — @MainActor, Tasks, and Actors

## `@MainActor` — Isolation Rules

Marks a type, method, or property as isolated to the main thread. The compiler enforces:
- `@MainActor` properties can only be read/written from the main actor
- Non-`@MainActor` code must `await` to access `@MainActor` properties
- `@MainActor` methods can freely access each other without `await`

```swift
@MainActor
class ViewModel: ObservableObject {
    @Published var items: [Item] = []
    
    func analyze() async {
        let analyzer = HeavyAnalyzer()  // actor
        let results = try? await analyzer.analyzeAll(items)
        // Back on MainActor — can update @Published
    }
}
```

## `Task` vs `Task.detached`

### `Task { }` — Inherits Actor Context
```swift
@MainActor
func loadImages() {
    Task { [weak self] in  // Runs on MainActor
        guard let self else { return }
        await self.heavyWork()
        // Can update @Published properties
    }
}
```

### `Task.detached` — No Actor Inheritance
```swift
@MainActor
func loadImages() {
    Task.detached {  // Runs off MainActor
        let data = try await loadData()
        return data
    } value: { [weak self] data in  // Back on MainActor
        self?.someImage = NSImage(data: data)
    }
}
```

### `Task.detached` with `@MainActor` class — Value Capture Pattern

When accessing `@MainActor`-isolated properties from `Task.detached`, you CANNOT use `await` directly in the detached closure. Instead, capture all needed values as `let` constants before the detached task:

```swift
@MainActor
func updatePreview() {
    // Capture @MainActor-isolated values BEFORE Task.detached
    let cgImages = self.images.map { $0.cgImage }
    let panelFrames = self.panels.map { $0.frame }

    previewTask?.cancel()
    previewTask = Task.detached {
        let result = renderPreview(cgImages: cgImages, frames: panelFrames)
        return result
    } value: { [weak self] image in
        self?.previewImage = image
    }
}
```

**Why:** `self.images.map { $0.cgImage }` inside a `Task.detached` closure on an `@MainActor` class would require `await`, making the whole closure `async`. The capture pattern avoids this by reading values on MainActor before detaching.
```

## AppKit Objects Across Thread Boundaries

AppKit types (`NSImage`, `NSColor`, `NSBitmapImageRep`) are **not thread-safe**. Capturing their reference in a `Task.detached` closure doesn't crash, but **calling methods on them from a background thread can silently fail** (e.g., `cgImage(forProposedRect:)` returns `nil`).

| Type | Thread-Safe? | Safe to Use in `Task.detached`? |
|---|---|---|
| `NSImage` | No | Reference survives capture, but **don't call methods** |
| `NSColor` | No | Reference survives capture, but **don't call methods** |
| `NSAttributedString` | No | **Not Sendable** — capture as `let` on main thread first |
| `CGImage` | Yes | Fully safe — value type, no thread affinity |
| `CGColor` | Yes | Fully safe — value type, no thread affinity |
| `NSBitmapImageRep` | No | Don't use on background thread |

**Rule:** Extract `CGImage` from `NSImage` and `CGColor` from `NSColor` on the main thread **before** passing to `Task.detached`. Also capture `NSAttributedString` as a local `let` — it's not `Sendable`.

```swift
@MainActor
func updatePreview() {
    // Extract thread-safe types on main thread
    let cgImage: CGImage? = backgroundNSImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    let startCGColor: CGColor? = gradientStartColor.cgColor
    let endCGColor: CGColor? = gradientEndColor.cgColor

    previewTask?.cancel()
    previewTask = Task.detached {
        // Safe — only CoreGraphics types, no AppKit method calls
        let result = renderBackground(cgImage: cgImage, start: startCGColor, end: endCGColor)
        return result
    } value: { [weak self] image in
        self?.previewImage = image
    }
}
```

**Diagnostic clue:** If `NSImage.cgImage(forProposedRect:)` returns `nil` intermittently or only in background tasks, check that you're calling it on the main thread.

### NSAttributedString is Not Sendable

`NSAttributedString` does not conform to `Sendable`. Capturing `self.titleAttrString` inside `Task.detached { [weak self] in ... }` produces a compile error. The fix mirrors the `NSColor`/`NSImage` pattern — capture as a local `let` on the main thread:

```swift
@MainActor
func updatePreview() {
    let titleAttrString = self.titleAttrString  // captured on @MainActor
    let cgImages = self.images.map { $0.cgImage }

    previewTask = Task.detached {
        let result = renderPreview(cgImages: cgImages, title: titleAttrString)
        return result
    } value: { [weak self] image in
        self?.previewImage = image
    }
}
```

| Scenario | Use |
|---|---|
| Need to update UI/ViewModel after async work | `Task { }` |
| Heavy computation that shouldn't block main actor | `Task.detached { }` with `value:` |
| Calling an `actor` method | `Task { }` (actor hop is automatic) |
| Fire-and-forget background work | `Task.detached { }` |

## `[weak self]` Capture

```swift
// DANGEROUS — strong capture
Task {
    await self.heavyWork()  // self stays alive until task completes
}

// SAFE — weak capture
Task { [weak self] in
    guard let self else { return }
    await self.heavyWork()
}
```

**Critical for:** Long-running tasks, tasks that may outlive the ViewModel, timer callbacks.

## `MainActor.assumeIsolated` Crash

### What It Is
Internal Swift runtime call that asserts the current thread is the main actor. Used by SwiftUI in Button closures, onChange, etc.

### The Crash Scenario
```swift
struct EditorView: View {
    @ObservedObject var viewModel: ViewModel  // Stored property
    
    var body: some View {
        Button("Action") {
            viewModel.doSomething()  // Captures stale self
        }
    }
}
```

1. SwiftUI creates view instance A
2. Button closure captures instance A
3. State change creates view instance B
4. Button tap references stale instance A
5. **SIGABRT** — `MainActor.assumeIsolated` fails

### The Fix
Use `@EnvironmentObject` so the View struct doesn't store the reference:
```swift
@EnvironmentObject var viewModel: ViewModel
```

## Cancellable Operations

```swift
@MainActor
class ViewModel: ObservableObject {
    private var currentTask: Task<Void, Error>?
    
    func analyze() async {
        currentTask?.cancel()
        
        currentTask = Task {
            try Task.checkCancellation()
            // ... async work
            try Task.checkCancellation()  // Check periodically
        }
    }
    
    func clearAll() {
        currentTask?.cancel()
        currentTask = nil
    }
}
```

## `withThrowingTaskGroup` — Preserving Order

`withThrowingTaskGroup` doesn't guarantee result order. To preserve input order:

```swift
func analyzeAllOrdered(_ images: [NSImage]) async throws -> [Result] {
    try await withThrowingTaskGroup(of: (Int, Result).self) { group in
        for (index, image) in images.enumerated() {
            group.addTask {
                (index, try await self.analyze(image))
            }
        }

        var ordered: [(Int, Result)] = []
        for try await tuple in group {
            ordered.append(tuple)
        }
        ordered.sort { $0.0 < $1.0 }
        return ordered.map { $0.1 }
    }
}
```

## Limiting Concurrency

For resource-intensive operations, limit concurrent tasks with `DispatchSemaphore`:

```swift
func analyzeAllLimited(_ images: [NSImage], maxConcurrent: Int = 4) async throws -> [Result] {
    let semaphore = DispatchSemaphore(value: maxConcurrent)
    var results: [Result] = []
    let lock = NSLock()

    try await withThrowingTaskGroup(of: Result.self) { group in
        for image in images {
            semaphore.wait()
            group.addTask {
                defer { semaphore.signal() }
                return try await self.analyze(image)
            }
        }

        for try await result in group {
            lock.lock()
            results.append(result)
            lock.unlock()
        }
    }

    return results
}
```

**Use when:** Saliency analysis on many images, file I/O with many files, network requests with rate limits.

## Processing Indicator Pattern

```swift
@MainActor
class ViewModel: ObservableObject {
    @Published var isProcessing: Bool = false
    
    func process() async {
        isProcessing = true
        defer { isProcessing = false }  // Always reset, even on error
        
        do {
            let results = try await service.processAll(items)
            // Update state on MainActor
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

## Task.detached Priority Propagation

A `Task.detached` does not inherit priority from its creation context — it runs at `.medium` QoS by default. Choose an appropriate priority for background work:

```swift
// Default .medium — fine for most background work
Task.detached {
    heavyComputation()
}

// .background — for work that shouldn't interrupt interactive tasks
Task.detached(priority: .background) {
    persistence.save(data)
}

// .userInitiated — for work triggered directly by user action
Task.detached(priority: .userInitiated) {
    processUserSelection()
}
```

**Rule:** Use `.background` for persistence saves and cache updates. Use `.userInitiated` for work the user is waiting for. Default `.medium` for analysis and rendering.

## Summary Rules

1. **Mark ViewModel as `@MainActor`** — all `@Published` properties are main-thread-safe
2. **Use `actor` for background services** — not `@MainActor`
3. **Use `Task { [weak self] }`** for async operations that update the ViewModel
4. **Use `Task.detached`** for heavy computation without immediate MainActor access
5. **Use `withThrowingTaskGroup`** for concurrent batch operations
6. **Never store `@ObservedObject` in View structs** with `@MainActor` ViewModel — use `@EnvironmentObject`
7. **Use `defer { isProcessing = false }`** to ensure processing state is always reset
8. **Extract CoreGraphics types on main thread before `Task.detached`** — Convert `NSImage` → `CGImage` and `NSColor` → `CGColor` on the main thread. Never call AppKit methods from a detached task.

## Pitfalls

- **`Task` without `[weak self]`** — retain cycle if task outlives ViewModel
- **Stale `Task` references** — cancel previous `Task` before starting new one
- **`@ObservedObject` + `@MainActor`** — `MainActor.assumeIsolated` crash. Use `@EnvironmentObject`
- **`[weak self]` on struct produces compile error** — `self` in a SwiftUI `struct` view is a value type, not a reference. Either capture `self` by value (no weak needed — structs have value semantics) or move timer/state to a `@MainActor final class` (e.g., `CollageViewModel`).

## Task vs Task.detached

```swift
// Task { } — inherits @MainActor context
Task { [weak self] in
    await self?.heavyWork()  // Can update @Published after
}

// Task.detached — runs off MainActor
Task.detached {
    let data = try await loadData()  // Background
    return data
} value: { [weak self] data in  // Back on MainActor
    self?.image = NSImage(data: data)
}
```

## [weak self] Capture

Always use `[weak self]` in `Task` closures for long-running operations to prevent retain cycles:

```swift
Task { [weak self] in
    guard let self else { return }
    await self.process()
}
```

## Cancellable Operations

```swift
private var currentTask: Task<Void, Error>?

func start() async {
    currentTask?.cancel()
    currentTask = Task {
        try Task.checkCancellation()
        // ... work
    }
}

func stop() {
    currentTask?.cancel()
    currentTask = nil
}
```

## Processing Indicator

```swift
func process() async {
    isProcessing = true
    defer { isProcessing = false }  // Always reset, even on error
    do {
        let results = try await service.process(items)
        // update state
    } catch {
        errorMessage = error.localizedDescription
    }
}
```
