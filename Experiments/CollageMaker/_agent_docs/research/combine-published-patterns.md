# Combine Framework — @Published and Change Detection

## `@Published` — How It Works

`@Published` is a property wrapper from Combine that automatically sends change notifications through the `objectWillChange` publisher.

### Basic Mechanism
```swift
@MainActor
class CollageViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var crops: [CropInfo] = []
    @Published var panels: [ImagePanel] = []
}
```

When a `@Published` property is **assigned a new value**, SwiftUI observes the change via `objectWillChange` and re-renders views that depend on it.

## The Array Element Mutation Problem

### The Trap
```swift
// This does NOT trigger @Published notification!
crops[index].sourceRect = newRect

// Why: crops is still the same array reference.
// @Published only fires on assignment to the property itself.
// Mutating an element in-place is invisible to @Published.
```

### Solutions

#### Solution 1: Replace the Array
```swift
crops[index].sourceRect = newRect
crops = Array(crops)  // Creates a new array reference — fires @Published
```

**Caveat:** If `CropInfo` doesn't conform to `Equatable`, SwiftUI may still re-render even when nothing meaningfully changed. Make value types `Equatable` when possible.

#### Solution 2: Manual `objectWillChange.send()`
```swift
crops[index].sourceRect = newRect
objectWillChange.send()  // Explicitly notify observers
```

**Warning:** `objectWillChange.send()` must be called **before** the assignment if you want SwiftUI to see the old and new states correctly. However, calling it after the mutation still triggers a re-render, just without the diff.

#### Solution 3: Use a Dictionary with `@Published`
```swift
@Published var cropMap: [UUID: CropInfo] = [:]

// Dictionary assignment fires @Published
cropMap[panelId] = updatedCrop
```

**Advantage:** Each assignment to a dictionary key is a new dictionary reference, so `@Published` fires naturally.

#### Solution 4: Individual @Published Properties
For a small, fixed set of values:
```swift
@Published var cropOffsetX: Double = 0
@Published var cropOffsetY: Double = 0
@Published var cropZoom: Double = 1
```

Each slider binds directly to one property. Assignment fires `@Published` naturally.

## `objectWillChange` — The Underlying Publisher

`ObservableObject` synthesizes an `objectWillChange` publisher. Any `@Published` assignment automatically sends to this publisher.

### Manual Control
```swift
class CollageViewModel: ObservableObject {
    // Not @Published — we control notifications manually
    var computedValue: Double = 0 {
        willSet { objectWillChange.send() }
    }
    
    // Or send manually for complex operations
    func updateMultipleThings() {
        objectWillChange.send()  // Send once, before all changes
        crops[...] = ...
        panels[...] = ...
        previewImage = ...
    }
}
```

### Debouncing `objectWillChange`
When multiple properties change rapidly (e.g., slider movement), you may want to coalesce notifications:
```swift
// Don't send objectWillChange for every slider tick
// Instead, send once after the debounce timer fires
func scheduleCropUpdate() {
    debounceTimer?.invalidate()
    debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
        Task { @MainActor in
            self?.objectWillChange.send()  // Single notification
            self?.applyCropSliderValues()
            self?.updatePreview()
        }
    }
}
```

## SwiftUI Binding and @Published

### Direct Binding
```swift
// Slider binds directly to a @Published Double
Slider(value: $viewModel.cropOffsetX, in: -50...50) {
    viewModel.scheduleCropUpdate()
}
```

**How it works:**
1. Slider changes `viewModel.cropOffsetX`
2. `@Published` fires → `objectWillChange.send()`
3. SwiftUI re-renders views observing `viewModel`
4. The `.onChange` or slider label updates

### Binding to Computed Values
```swift
// If the value comes from an array element, create a custom binding
Slider(value: Binding(
    get: { crops[selectedIndex].offsetX },
    set: { crops[selectedIndex].offsetX = $0; crops = Array(crops) }
)) {
    // ...
}
```

## `@Published` with Reference Types Inside Collections

### The NSImage Problem
```swift
@Published var previewImage: NSImage?

// This fires @Published because it's a new reference
previewImage = newImage

// But if you mutate the NSImage in-place:
previewImage?.addRepresentation(newRep)  // Does NOT fire @Published
```

**Fix:** Always assign a new instance:
```swift
let newImage = NSImage(cgImage: cgImage, size: size)
previewImage = newImage
```

## Diagnosing @Published Issues

### Common Symptoms and Causes

| Symptom | Likely Cause |
|---|---|
| View doesn't update after data change | In-place mutation without `Array(crops)` or `objectWillChange.send()` |
| View updates once, then stops | `@State` holding a reference type that gets deallocated |
| View updates but shows stale data | `let panel: ImagePanel` value copy, not derived from ViewModel |
| Slider value changes but side effect doesn't fire | `.onChange` not firing due to SwiftUI deduplication |
| Crash on Button action | `@ObservedObject` stored reference + MainActor isolation |

### Debug Technique: Log `objectWillChange`
```swift
// In ContentView or a wrapper, subscribe to objectWillChange
.onAppear {
    viewModel.objectWillChange.sink { [weak viewModel] _ in
        logger.debug("objectWillChange fired — panels: \(viewModel?.panels.count ?? 0), crops: \(viewModel?.crops.count ?? 0)")
    }.store(in: &cancellables)
}
```

## Summary: CollageMaker Combine Rules

1. **Never mutate array elements in-place** and expect `@Published` to fire — use `crops = Array(crops)` or `objectWillChange.send()`
2. **Prefer individual `@Published` properties** for frequently-changing slider values
3. **Use `objectWillChange.send()` once** before a batch of changes, not after each one
4. **Always assign new references** for `@Published` reference-type properties (NSImage, Data, etc.)
5. **Consider dictionary-based storage** (`[UUID: CropInfo]`) for per-panel data — assignment fires naturally
