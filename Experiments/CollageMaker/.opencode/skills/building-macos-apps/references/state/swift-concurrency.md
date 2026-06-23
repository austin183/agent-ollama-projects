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

## `deinit` Runs Outside Actor Isolation

`deinit` always executes in a nonisolated context, even on `@MainActor` classes. You cannot call actor-isolated methods from `deinit`.

```swift
@MainActor
final class Debouncer {
    private var tasks: [String: Task<Void, Never>] = [:]

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    deinit {
        cancelAll()  // ERROR: actor-isolated method in nonisolated context
    }
}
```

**Fix — inline the `Sendable` operations:**
```swift
    deinit {
        tasks.values.forEach { $0.cancel() }
        // No need for tasks.removeAll() — object is being deallocated
    }
```

**Rule:** Only `Sendable` operations and `nonisolated` methods are safe in `deinit`. Read your own stored properties directly, then perform `Sendable` actions (e.g., `Task.cancel()`).

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

### Computed Properties Evaluate on Destination Thread

A common trap is using computed properties on structs that cross actor boundaries. The computed property evaluates lazily at *access time* on whatever thread reads it — not at construction time on the source thread.

**The trap:**
```swift
struct BackgroundConfig: @unchecked Sendable {
    let color: NSColor
    var backgroundColor: CGColor { color.cgColor }  // EVALUATES ON ACCESS THREAD
}

// Struct constructed on MainActor, but accessed on background DispatchQueue:
Task.detached {
    let cg = config.backgroundColor  // .cgColor called off-main-thread — UB/crash
}
```

The `@unchecked Sendable` conformance and main-thread construction create a false sense of safety. The `NSColor` stored value crosses the boundary when the struct is captured. The computed property then calls `.cgColor` on the background thread.

**The fix — store the derived value at init time:**
```swift
struct BackgroundConfig: @unchecked Sendable {
    let color: NSColor
    let backgroundColor: CGColor  // captured at init on MainActor

    init(color: NSColor) {
        self.color = color
        self.backgroundColor = color.cgColor  // .cgColor called on MainActor
    }
}
```

**General rule:** Never use computed properties to access MainActor-only types (`NSColor`, `NSAttributedString`, etc.) from non-main contexts. Store the thread-safe derived value at construction time.

**Swift gotcha — memberwise init conflict:** When a struct has all `let` stored properties, Swift synthesizes a memberwise init. Adding a custom `init` in an extension with the same signature causes *"invalid redeclaration of synthesized memberwise init"*. Fix: move the init into the struct body, or use `var` on at least one stored property to suppress synthesis.

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

## Async State Races in @Observable Views

When multiple `Task.detached` tasks update different `@Observable` properties that a view's `body` reads together (e.g., `panelRenderedImages` and `previewImage`), the view may see inconsistent intermediate states. The `body` evaluates synchronously and sees whatever state happens to be set at that moment.

**Symptom:** Rendering mode flips unpredictably during rapid interactions. One rendering path clears its state before the other path's replacement is ready, leaving a blank frame.

**Fixes:**
- **Don't clear old state until new state is confirmed ready** — Keep stale content visible during the async gap
- **Batch related updates** — Use a single `Task { @MainActor in ... }` block to set multiple related properties atomically
- **Consolidate into a single property** — E.g., a `RenderingMode` enum that encapsulates which rendering path is active, rather than inferring mode from independent properties

## @Observable State Updates from Background Work

When updating an `@Observable` `@MainActor` class from heavy background work, prefer `await Task.detached { ... }.value` over nested `Task { @MainActor in ... }`:

```swift
@Observable @MainActor final class PreviewManager {
    var previewImage: NSImage?

    func render() {
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            guard let self else { return }
            let result = await Task.detached {
                // Off-main-actor rendering work
                renderPreview()
            }.value
            self.previewImage = result  // Back on MainActor via outer Task
        }
    }
}
```

**Why this pattern:**
1. Outer `Task` inherits `MainActor` — assignment to `self.previewImage` is safe
2. `[weak self]` prevents retain cycles
3. `await Task.detached { ... }.value` runs work off-main-actor and returns the result
4. Cancellation propagates naturally — cancelling `previewTask` cancels the inner detached task

**Contrast with nested pattern:** `Task.detached { [weak self] in ... Task { @MainActor in self?.previewImage = result } }` works but requires manual actor hopping and doesn't propagate cancellation to the inner work.

## Generation Counters — Discarding Stale Async Results

Task cancellation (`task?.cancel()`) alone is insufficient when rendering work runs on a serial `DispatchQueue`. A cancelled task's work is still submitted to the queue and runs to completion — the continuation just never resumes. But with multiple `update*` calls racing, each creates its own task, and the serial queue processes them FIFO. An older render can complete after a newer one, producing a stale frame that overwrites fresh UI state.

**Fix:** A monotonically increasing generation counter at the caller level. Each `update*` call increments its counter before starting work. After `await`, the result is only applied if the captured generation still matches:

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

### Per-Item Generation Tracking for Batch Operations

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

### Dual Generation Check (Pre-await and Post-await)

For panel previews, the generation is checked both before and after the `await`:

- **Pre-check** (`guard gen == self.panelGenerations[panelId]` before `await`) — Guards against starting work that's already superseded. If a newer `updatePanelPreview` call for the same panel ran between task creation and task execution, the generation will have advanced and we skip the render entirely.
- **Post-check** (same guard after `await`) — Guards against the result being stale when it completes.

The pre-check is an optimization (saves wasted CPU on the render queue). The post-check is correctness (ensures stale results don't update UI state). For simpler render types (preview, background, title) where only one task exists at a time, the post-check alone is sufficient.

### When to Use Generation Counters

| Scenario | Solution |
|---|---|
| Single in-flight async task, cancel before new call | `task?.cancel()` + new task |
| Serial queue, cancelled work still runs FIFO | Generation counter at caller level |
| Batch operations (per-item updates) | Per-item generation: `[ID: Int]` |
| Need to skip starting superseded work | Pre-await generation check |
| Need to skip applying stale results | Post-await generation check |

**Note:** Generation counters discard stale results at the caller level, but the rendering work still executes on the serial queue. For queue-level cancellation, check `Task.isCancelled` inside the render closure and return early — but this adds complexity inside rendering methods that should be focused on CoreGraphics work.

### Cross-Boundary Debounce Cancellation

When a method bypasses a debounced path to render immediately (e.g., `regenerateLayout()` calling `updatePreview()` directly), it must cancel the pending debounce task first. A sleeping debounced task will otherwise wake and re-render over the fresh state — a wasted render that reads current config but still costs CPU.

```swift
func regenerateLayout() {
    previewRenderDebounceTask?.cancel()  // cancel pending debounced render
    // ... layout computation ...
    updatePreview()  // render immediately with fresh state
}
```

This is a one-line addition but prevents a category of wasted renders that only manifests during rapid interaction (slider drag followed immediately by layout change).

### Property Debounce Classification

Not all `didSet` observers need debouncing. The decision is based on event frequency during normal use:

| Control type | Event rate | Debounce? | Rationale |
|---|---|---|---|
| Slider drag | 30-60/sec | Yes (150ms) | Continuous, user sees final value |
| Color picker drag | 30-60/sec | Yes (150ms) | Continuous, user sees final color |
| Typing | ~5/sec | No | Each keystroke should appear |
| Enum picker | ~5-10/sec | No | Discrete, 150ms delay feels sluggish |
| Image selection | ~1/sec | No | Discrete, expensive load warrants immediate feedback |

**Rule of thumb:** If the control produces more than ~10 events per second during normal interaction, debounce it. If the user expects to see each individual change (typing, selection), render immediately.

## `withCheckedContinuation` — Bridging Serial DispatchQueue to Async

When a serial `DispatchQueue` is required for thread safety (e.g., `NSGraphicsContext.current`), use `withCheckedContinuation` to expose async methods instead of blocking with `queue.sync`:

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

**Why over `Task.detached { ... }.value`:**
- **Non-blocking queue entry** — `queue.async` returns immediately, freeing the calling thread. `queue.sync` blocks until the serial queue processes the work.
- **Caller simplification** — `await assembler.renderPanel(...)` instead of wrapping sync work in `Task.detached { ... }.value`
- **Serial queue retained** — `NSGraphicsContext.current` thread safety is preserved
- **Cancellation** — If the calling `Task` is cancelled, the continuation suspends indefinitely and the result is discarded (work may still complete on the queue thread)

**When to use:** Any time you have a serial `DispatchQueue` protecting a non-thread-safe resource (like `NSGraphicsContext.current`) and want callers to use `async/await`.

### Actor as DispatchQueue Wrapper

When 3+ methods share the same serial queue, the `withCheckedContinuation` + `queue.async` pattern requires the same 4-line boilerplate in each method. Consolidate into an actor:

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
- `@escaping` on the closure parameter is required because `withCheckedContinuation` stores the closure for later execution on the queue thread

### Async Bridge Decision Tree

| Requirement | Pattern |
|---|---|
| Off-main-actor work, no shared mutable state | `Task.detached { ... }.value` |
| Off-main-actor work, serial queue for thread safety | `withCheckedContinuation` + `queue.async` |
| 3+ methods share the same serial queue | `RenderScheduler` actor wrapper |
| Off-main-actor work, needs cancellation to stop execution | `Task.detached` with `try Task.checkCancellation()` |
| Serial queue, cancelled work still runs FIFO | Generation counter at caller level |
| Main-actor state update after background work | `Task { [weak self] ... self.property = result }` |

### Synchronous Closures Inside `withCheckedContinuation`

The `RenderScheduler.render` method takes a **synchronous** closure (`@Sendable () -> T`), not an async one. The closure runs on a `DispatchQueue` thread, not an async context.

**Swift 6 traps:**
- `await` inside the closure is a compile error — the closure is synchronous
- `actor` methods require `await` — can't call them from inside the closure
- Mutating captured `var` produces *"mutation of captured var in concurrently-executing code"*

**Solution — Thread-Safe Class with NSLock:**
```swift
final class ThreadSafeArray<Element: Sendable>: @unchecked Sendable {
    private var items: [Element] = []
    private let lock = NSLock()

    func append(_ item: Element) {
        lock.lock(); defer { lock.unlock() }; items.append(item)
    }

    func getItems() -> [Element] {
        lock.lock(); defer { lock.unlock() }; items
    }
}
```

**Usage in tests:**
```swift
let tracker = ThreadSafeArray<String>()
await scheduler.render {
    tracker.append("enter")  // Synchronous, thread-safe
    Thread.sleep(forTimeInterval: 0.001)  // Sync sleep, not Task.sleep
    tracker.append("exit")
    return ()
}
```

**Why not other approaches:**
- `actor` + `await` — closure is synchronous, `await` is illegal
- `NSLock` on local `var` — Swift 6 forbids mutation of captured vars in concurrent code
- `@MainActor` — queue runs on background thread, not main actor
- `UnsafeMutablePointer` — unsafe, defeats the purpose

**Key points:**
- `@unchecked Sendable` is safe here because `NSLock` provides mutual exclusion
- `Thread.sleep(forTimeInterval:)` is the synchronous equivalent of `Task.sleep`
- This pattern applies whenever you need to collect results from synchronous closures executing concurrently

### `@unchecked Sendable` for Model Types with AppKit Values

Swift's Sendable checker rejects structs containing `NSColor`, `NSAttributedString`, or other non-Sendable AppKit types. When these are only ever accessed on a known thread (e.g., the serial render queue), `@unchecked Sendable` is safe:

```swift
struct BackgroundConfig {
    let color: NSColor
    let gradientStartColor: NSColor
}

extension BackgroundConfig: @unchecked Sendable {}
```

**Safety checklist:**
1. Verify all non-Sendable properties are only accessed on a known thread
2. Document the safety justification in a code comment
3. Prefer `extension TypeName: @unchecked Sendable {}` over inline declaration
4. For imported types (e.g., `NSAttributedString`), put the extension in the file that uses it

**Note on `NSAttributedString`:** Apple doesn't mark it `Sendable`. Add `extension NSAttributedString: @unchecked Sendable {}` in the file that uses it. This produces a harmless compiler warning about conforming an imported type to an imported protocol.

## `nonisolated` Actor Methods — Genuine Parallelism

An actor method called via `withThrowingTaskGroup` **appears concurrent but is serialized**. Each `await self.method()` hops through the actor's single-threaded executor, eliminating all parallelism.

**The fix:** Mark the method `nonisolated` when it accesses no actor-isolated state:

```swift
actor SaliencyAnalyzer {
    nonisolated func analyze(_ cgImage: CGImage) async throws -> SaliencyResult {
        // Only local variables, Vision API calls, module-level constants
        // No self.property access
    }

    func analyzeAll(_ cgImages: [CGImage]) async throws -> [SaliencyResult] {
        try await withThrowingTaskGroup(of: (Int, SaliencyResult).self) { group in
            for (i, img) in cgImages.enumerated() {
                group.addTask {
                    let result = try await self.analyze(img)  // Genuine parallelism
                    return (i, result)
                }
            }
            // collect and reorder...
        }
    }
}
```

**Verification checklist before marking `nonisolated`:**
1. **No `self.` access** to actor-stored properties
2. **Only local variables** and function parameters
3. **Module-level constants** (e.g., `private let logger`) are fine — not actor-isolated
4. **External async APIs** (Vision, URLSession, etc.) are fine — not actor-isolated
5. **Protocol conformance** — the protocol must not require actor isolation

**Anti-pattern:** Placing a pure function inside an actor solely for protocol conformance, then expecting `withThrowingTaskGroup` to provide parallelism. The actor executor serializes everything unless the method is `nonisolated`.

## Summary Rules

1. **Mark ViewModel as `@MainActor`** — all `@Published` properties are main-thread-safe
2. **Use `actor` for background services** — not `@MainActor`
3. **Use `Task { [weak self] }`** for async operations that update the ViewModel
4. **Use `Task.detached`** for heavy computation without immediate MainActor access
5. **Use `withThrowingTaskGroup`** for concurrent batch operations
6. **Never store `@ObservedObject` in View structs** with `@MainActor` ViewModel — use `@EnvironmentObject`
7. **Use `defer { isProcessing = false }`** to ensure processing state is always reset
8. **Extract CoreGraphics types on main thread before `Task.detached`** — Convert `NSImage` → `CGImage` and `NSColor` → `CGColor` on the main thread. Never call AppKit methods from a detached task.
9. **Computed properties on structs crossing actor boundaries are unsafe** — A computed `var cgColor: CGColor { nsColor.cgColor }` evaluates on the destination thread. Store derived values at init time on the source actor.
10. **Avoid clearing shared state before async replacement** — Multiple `Task.detached` tasks racing to update related `@Observable` properties create inconsistent intermediate states. Don't clear old state until new state is ready, or batch updates in a single `@MainActor` block.
11. **Use `withCheckedContinuation` + serial queue** for async rendering methods that need `NSGraphicsContext.current` thread safety — non-blocking, cleaner than `queue.sync` wrapped in `Task.detached`
12. **Use `@unchecked Sendable` for model types with AppKit values** when non-Sendable properties are only accessed on a known thread — document the safety justification
13. **Use generation counters to discard stale async results** — When a serial queue processes cancelled tasks FIFO, an older render can overwrite newer state. Increment a counter before each `update*` call, capture it in the task, and guard `gen == currentGeneration` after `await` before applying results
14. **Use per-item generation counters for batch operations** — When updating multiple items in a loop, use `[ID: Int]` instead of a single counter so each item's render can match its own generation
15. **Use an actor wrapper for shared DispatchQueue boilerplate** — When 3+ methods share the same serial queue, consolidate `withCheckedContinuation` into an actor's `render(_ work: @escaping @Sendable () -> T) async -> T` method
16. **Cancel debounce tasks at higher-priority entry points** — When a method bypasses a debounced path to render immediately (e.g., `regenerateLayout()` calling `updatePreview()`), cancel the pending debounce task first to prevent a stale debounced render from overwriting fresh state
17. **Debounce only continuous controls** — Slider and color picker `didSet` observers fire 30-60x/sec during drag and need 150ms debounced render. Discrete controls (typing, enum picker, image selection) render immediately. Rule of thumb: >10 events/sec = debounce
18. **Synchronous closures can't use `await`** — `RenderScheduler.render { }` takes a synchronous closure. To collect mutable state from concurrent closures, use a `ThreadSafeArray<Element>` backed by `NSLock` + `@unchecked Sendable`. Use `Thread.sleep(forTimeInterval:)` instead of `Task.sleep`
19. **Actor methods in `withThrowingTaskGroup` serialize through actor executor** — `await self.method()` on an actor hops through the actor's single-threaded executor, eliminating parallelism. Mark pure-computation methods `nonisolated` to bypass the actor executor. Verify: no `self.` access, only locals/params/external APIs.
20. **`deinit` runs outside actor isolation** — Even on `@MainActor` classes, `deinit` is nonisolated. Cannot call actor-isolated methods. Inline `Sendable` operations directly (e.g., `tasks.values.forEach { $0.cancel() }`).

## Pitfalls

- **`Task` without `[weak self]`** — retain cycle if task outlives ViewModel
- **Stale `Task` references** — cancel previous `Task` before starting new one
- **`@ObservedObject` + `@MainActor`** — `MainActor.assumeIsolated` crash. Use `@EnvironmentObject`
- **`[weak self]` on struct produces compile error** — `self` in a SwiftUI `struct` view is a value type, not a reference. Either capture `self` by value (no weak needed — structs have value semantics) or move timer/state to a `@MainActor final class` (e.g., `CollageViewModel`).
- **Computed properties on `@unchecked Sendable` structs** — A computed property that accesses a MainActor-only type (e.g., `var cgColor: CGColor { nsColor.cgColor }`) evaluates on the *destination* thread, not the construction thread. Store the derived value in `init` instead.
- **Synchronous dispatch closures can't `await`** — `RenderScheduler.render { }` closures are synchronous. `await` is a compile error. Mutating captured `var` is a Swift 6 error. Use `ThreadSafeArray` with `NSLock` for mutable state collection.
- **Actor method in `withThrowingTaskGroup` serializes all work** — Even though `withThrowingTaskGroup` creates concurrent tasks, `await self.method()` on an actor serializes through the actor executor. Mark the method `nonisolated` if it doesn't access actor state.
- **`deinit` on `@MainActor` class is nonisolated** — Cannot call actor-isolated methods from `deinit`. Inline `Sendable` operations (e.g., `Task.cancel()`) directly.

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

## Swift Compilation Gotchas

- **Same-file extension ordering:** Swift compiles each `.swift` file as a separate compilation unit. Within a single file, an `extension` on a type from another file cannot reference types defined later in the same file. Place the extension **after** any local types it references, or move the extension to the extended type's own file (cross-file references have no ordering constraint).
