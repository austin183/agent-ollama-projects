# Swift Concurrency and @MainActor — Patterns for macOS Apps

## `@MainActor` — Isolation and Rules

### What `@MainActor` Does
Marks a type, method, or property as isolated to the main thread. The Swift compiler enforces access rules:
- `@MainActor` properties can only be read/written from the main actor
- Non-`@MainActor` code must `await` to access `@MainActor` properties
- `@MainActor` methods can freely access each other without `await`

### Marking a ViewModel
```swift
@MainActor
class CollageViewModel: ObservableObject {
    @Published var images: [ImageItem] = []
    @Published var panels: [ImagePanel] = []
    @Published var previewImage: NSImage?
    
    func generateLayout() {
        // Can access all @Published properties directly
        panels = LayoutGenerator.generate(numImages: images.count, ...)
    }
    
    func analyzeSaliency() async {
        // Can call non-actor methods, then await results
        let analyzer = SaliencyAnalyzer()  // actor — different isolation
        let results = try? await analyzer.analyzeAll(images.map { $0.nsImage })
        // Back on MainActor — can update @Published properties
        if let results {
            saliencyResults = zip(images.map { $0.id }, results).dictionaryOfUniqueKeys
        }
    }
}
```

### Accessing @MainActor from Non-Main Code
```swift
actor SaliencyAnalyzer {
    func process() async {
        // Cannot access @MainActor properties directly
        // Must use a non-actor intermediary or pass data as parameters
        
        // WRONG — compiler error:
        // viewModel.images  // Cross-actor access
        
        // RIGHT — receive data as parameters:
        // func analyzeAll(_ images: [NSImage]) async throws -> [SaliencyResult]
    }
}
```

## `Task` vs `Task.detached`

### `Task { }` — Inherits Actor Context
```swift
@MainActor
func loadImages() {
    Task {  // Runs on MainActor
        let result = await heavyComputation()
        previewImage = result  // MainActor access — OK
    }
    
    Task { [weak self] in  // [weak self] prevents retain cycle
        await self?.heavyWork()
        // Still on MainActor — can update @Published
    }
}
```

### `Task.detached` — No Actor Inheritance
```swift
@MainActor
func loadImages() {
    Task.detached {  // Runs off MainActor
        let data = try await loadData()  // Background
        // Cannot access @MainActor properties here!
        return data
    } value: { [weak self] data in  // Back on MainActor
        self?.someImage = NSImage(data: data)
    }
}
```

### When to Use Each
| Scenario | Use |
|---|---|
| Need to update UI/ViewModel after async work | `Task { }` |
| Heavy computation that shouldn't block main actor | `Task.detached { }` with `value:` |
| Calling an `actor` method | `Task { }` (actor hop is automatic) |
| Fire-and-forget background work | `Task.detached { }` |

## `withThrowingTaskGroup` — Concurrent Batch Processing

### Pattern: Analyze Multiple Images Concurrently
```swift
actor SaliencyAnalyzer {
    func analyzeAll(_ images: [NSImage]) async throws -> [SaliencyResult] {
        var results: [SaliencyResult] = []
        
        try await withThrowingTaskGroup(of: SaliencyResult.self) { group in
            // Add all tasks
            for image in images {
                group.addTask {
                    try await self.analyze(image)
                }
            }
            
            // Collect results (order may differ from input)
            for try await result in group {
                results.append(result)
            }
        }
        
        return results
    }
    
    func analyze(_ image: NSImage) async throws -> SaliencyResult {
        // ... Vision framework analysis
    }
}
```

### Preserving Order
`withThrowingTaskGroup` doesn't guarantee result order. To preserve input order:
```swift
func analyzeAllOrdered(_ images: [NSImage]) async throws -> [SaliencyResult] {
    let results = try await withThrowingTaskGroup(of: (Int, SaliencyResult).self) { group in
        for (index, image) in images.enumerated() {
            group.addTask {
                (index, try await self.analyze(image))
            }
        }
        
        var ordered: [(Int, SaliencyResult)] = []
        for try await tuple in group {
            ordered.append(tuple)
        }
        ordered.sort { $0.0 < $1.0 }
        return ordered.map { $0.1 }
    }
}
```

### Limiting Concurrency
For resource-intensive operations, limit concurrent tasks:
```swift
func analyzeAllLimited(_ images: [NSImage], maxConcurrent: Int = 4) async throws -> [SaliencyResult] {
    let semaphore = DispatchSemaphore(value: maxConcurrent)
    var results: [SaliencyResult] = []
    let lock = NSLock()
    
    try await withThrowingTaskGroup(of: SaliencyResult.self) { group in
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

## `[weak self]` Capture in Tasks

### The Retain Cycle Problem
```swift
// DANGEROUS — strong capture of self
Task {
    await self.heavyWork()  // self stays alive until task completes
}

// SAFE — weak capture
Task { [weak self] in
    guard let self else { return }
    await self.heavyWork()
}
```

### When `[weak self]` Is Critical
- Long-running tasks (file I/O, network, heavy computation)
- Tasks that may outlive the ViewModel (e.g., export in background)
- Timer callbacks that capture ViewModel

### When `[weak self]` Is Optional
- Short-lived tasks that complete before the ViewModel is deallocated
- Tasks within `@MainActor` methods where the actor keeps self alive

## `MainActor.assumeIsolated` — And Why It Crashes

### What It Is
`MainActor.assumeIsolated` is an internal Swift runtime call that asserts the current thread is the main actor. It's used by SwiftUI when executing closure-based actions (Button, onChange, etc.).

### The Crash Scenario
```swift
struct PanelCropEditor: View {
    @ObservedObject var viewModel: CollageViewModel  // Stored property
    
    var body: some View {
        Button("Action") {
            // This closure captures `self` (the View struct)
            viewModel.doSomething()
        }
    }
}
```

1. SwiftUI creates `PanelCropEditor` instance A
2. Button closure captures instance A
3. State change triggers view body recomputation
4. SwiftUI creates `PanelCropEditor` instance B
5. User taps Button — closure still references instance A
6. `MainActor.assumeIsolated` checks if instance A is valid on MainActor
7. **SIGABRT** — instance A is stale

### The Fix
Use `@EnvironmentObject` so the View struct doesn't store the reference:
```swift
@EnvironmentObject var viewModel: CollageViewModel
```

## Async Operations in @MainActor ViewModels

### Pattern: Processing Indicator
```swift
@MainActor
class CollageViewModel: ObservableObject {
    @Published var isProcessing: Bool = false
    
    func analyzeSaliency() async {
        isProcessing = true
        defer { isProcessing = false }  // Always reset, even on error
        
        do {
            let analyzer = SaliencyAnalyzer()
            let results = try await analyzer.analyzeAll(images.map { $0.nsImage })
            // Update state on MainActor
            processResults(results)
        } catch {
            // Handle error on MainActor
            handleError(error)
        }
    }
}
```

### Pattern: Cancellable Operations
```swift
@MainActor
class CollageViewModel: ObservableObject {
    private var currentTask: Task<Void, Error>?
    
    func analyzeSaliency() async {
        // Cancel previous operation
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
        // Reset state
    }
}
```

## Summary: CollageMaker Concurrency Rules

1. **Mark ViewModel as `@MainActor`** — all `@Published` properties are main-thread-safe
2. **Use `actor` for background services** — `SaliencyAnalyzer` is an actor, not `@MainActor`
3. **Use `Task { [weak self] }`** for async operations that update the ViewModel
4. **Use `Task.detached`** for heavy computation that doesn't need immediate MainActor access
5. **Use `withThrowingTaskGroup`** for concurrent batch operations (saliency analysis)
6. **Never store `@ObservedObject` in View structs** when the ViewModel is `@MainActor` — use `@EnvironmentObject`
7. **Use `defer { isProcessing = false }`** to ensure processing state is always reset
