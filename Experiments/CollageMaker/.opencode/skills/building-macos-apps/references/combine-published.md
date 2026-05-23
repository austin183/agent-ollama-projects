# Combine Framework — @Published and Change Detection

## `@Published` — How It Works

`@Published` is a property wrapper from Combine that automatically sends change notifications through the `objectWillChange` publisher. When a `@Published` property is assigned a new value, SwiftUI observes the change via `objectWillChange` and re-renders dependent views.

## The Array Element Mutation Problem

### The Trap
```swift
// This does NOT trigger @Published notification!
crops[index].sourceRect = newRect

// crops is still the same array reference.
// @Published only fires on assignment to the property itself.
```

### Solutions

**Replace the Array:**
```swift
crops[index].sourceRect = newRect
crops = Array(crops)  // New array reference — fires @Published
```

**Manual `objectWillChange.send()`:**
```swift
crops[index].sourceRect = newRect
objectWillChange.send()  // Explicitly notify observers
```

**Dictionary Storage:**
```swift
@Published var cropMap: [UUID: CropInfo] = [:]
cropMap[panelId] = updatedCrop  // Assignment fires @Published
```

**Individual @Published Properties:**
```swift
@Published var cropOffsetX: Double = 0
@Published var cropOffsetY: Double = 0
@Published var cropZoom: Double = 1
```

## `objectWillChange` — Manual Control

```swift
class ViewModel: ObservableObject {
    var computedValue: Double = 0 {
        willSet { objectWillChange.send() }
    }
    
    // Send once before batch changes
    func updateMultipleThings() {
        objectWillChange.send()  // Once, before all changes
        crops[...] = ...
        panels[...] = ...
        previewImage = ...
    }
}
```

### Debouncing `objectWillChange`

```swift
func scheduleCropUpdate() {
    debounceTimer?.invalidate()
    debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
        Task { @MainActor in
            self?.objectWillChange.send()  // Single notification
            self?.applyCropSliderValues()
        }
    }
}
```

## SwiftUI Binding Patterns

### Binding to Computed Values
```swift
Slider(value: Binding(
    get: { crops[selectedIndex].offsetX },
    set: { crops[selectedIndex].offsetX = $0; crops = Array(crops) }
)) { }
```

## Reacting to @Published Changes: `.onReceive` vs `.onChange`

### The `.onChange` Problem

`.onChange(of:)` tracks the previous value in the **view's state**. When SwiftUI recreates the view struct (e.g., after `updatePreview()` changes `previewImage`), the tracker resets. The new view sees the current value as its initial value, so no "change" is detected on subsequent updates.

```swift
// BROKEN — loses observer after view recreation
.onChange(of: viewModel.cropOffsetX) { oldValue, newValue in
    viewModel.scheduleCropUpdate()  // Only fires once
}
```

### The `.onReceive` Fix

`.onReceive(publisher.dropFirst())` subscribes to the `@Published` Combine publisher, which survives view recreation because the subscription is tied to the ViewModel's lifetime, not the view's.

```swift
// RELIABLE — survives view recreation
.onReceive(viewModel.$cropOffsetX.dropFirst()) { _ in
    viewModel.scheduleCropUpdate()  // Fires every time
}
```

**Key points:**
- `dropFirst()` prevents firing immediately on view attachment
- Works with `@EnvironmentObject` — the Combine subscription is tied to the ViewModel
- Use this pattern whenever you need to react to `@Published` changes from a shared ViewModel

## @Published with Reference Types

```swift
@Published var previewImage: NSImage?

// Fires — new reference
previewImage = newImage

// Does NOT fire — in-place mutation
previewImage?.addRepresentation(newRep)

// Fix: always assign a new instance
previewImage = NSImage(cgImage: cgImage, size: size)
```

## Diagnosing @Published Issues

| Symptom | Likely Cause |
|---|---|
| View doesn't update after data change | In-place mutation without `Array(crops)` or `objectWillChange.send()` |
| View updates once, then stops | `@State` holding a reference type that gets deallocated |
| View updates but shows stale data | `let panel: SomeType` value copy, not derived from ViewModel |
| Slider changes but side effect doesn't fire | `.onChange` loses tracker on view recreation. Use `.onReceive(publisher.dropFirst())` |
| Crash on Button action | `@ObservedObject` stored reference + MainActor isolation |

### Debug: Log `objectWillChange`
```swift
.onAppear {
    viewModel.objectWillChange.sink { [weak viewModel] _ in
        logger.debug("objectWillChange fired — panels: \(viewModel?.panels.count ?? 0)")
    }.store(in: &cancellables)
}
```

## Summary Rules

1. **Never mutate array elements in-place** and expect `@Published` to fire
2. **Prefer individual `@Published` properties** for frequently-changing slider values
3. **Use `objectWillChange.send()` once** before a batch of changes
4. **Always assign new references** for `@Published` reference-type properties
5. **Consider dictionary-based storage** (`[UUID: Value]`) for per-item data

## Pitfalls

- **`@State` with non-Equatable types** — silent failure, no compiler warnings. Reference types (`Timer?`, classes) are lost on view re-render
- **`@ObservedObject` stored property crashes** — `MainActor.assumeIsolated` SIGABRT when Button closures capture stale `self`. Use `@EnvironmentObject`
- **`Timer` in `@State`** — deallocated during struct recreation. Move to `@StateObject` class
- **`@Published` array element mutation** — `arr[i].prop = x` doesn't fire `@Published`. Use `arr = Array(arr)` or `objectWillChange.send()`
- **`let item: SomeType` value copy** — can go stale if ViewModel updates between renders. Derive from ViewModel or use `.id()`
- **Picker binding bypasses action methods** — `$viewModel.layoutStyle` directly mutates `@Published`, skipping `setLayoutStyle(_)` side effects. Keep the binding for UI, add `.onChange(of:)` to call the action method
- **`.onChange(of:)` loses tracker on view recreation** — use `.onReceive(publisher.dropFirst())` instead
- **`.onReceive($property)` infinite recursion** — When a binding (e.g., Slider's `$viewModel.gutter`) mutates a `@Published` property and `.onReceive($gutter)` calls a method that re-assigns the same property, it creates an infinite loop. `.onReceive` should only trigger side effects, not re-assign the observed property.

## Property Wrapper Rules

| Wrapper | Use For | Survives Re-render? |
|---|---|---|
| `@State` | `Equatable` value types only (primitives, structs, enums) | Yes (by value comparison) |
| `@StateObject` | `ObservableObject` classes owned by the view | Yes (class instance persists) |
| `@EnvironmentObject` | Shared `@MainActor` ObservableObject across view hierarchy | Yes (injected by SwiftUI) |
| `@ObservedObject` | ObservedObject NOT owned by the view (avoid for shared state) | No (stored property on struct) |

**Critical rule:** Never store reference types (`Timer?`, `NSObject`, custom classes, closures) in `@State`. The compiler won't warn, but the reference will be lost silently during view struct recreation, causing "works once then stops" behavior.

## @Published Array Element Mutation

`@Published` only fires on **property assignment**, not in-place element mutation:

```swift
// Does NOT trigger @Published — same array reference
crops[index].sourceRect = newRect

// Fix: replace the array
crops = Array(crops)

// Or: manual notification
objectWillChange.send()

// Or: use dictionary — assignment fires naturally
@Published var cropMap: [UUID: CropInfo] = [:]
cropMap[panelId] = updatedCrop
```

For frequently-changing slider values, prefer individual `@Published` properties over array elements.

## View Identity

Use `.id()` on conditionally shown views to stabilize identity across recomputations:

```swift
if let selected = selectedPanel {
    PanelCropEditor(panel: selected)
        .id(selected.id)  // Same UUID = same view instance
}
```

## @MainActor ViewModel

```swift
@MainActor
class AppViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var preview: NSImage?
    @Published var isProcessing: Bool = false

    private let service = HeavyComputationService()  // actor — safe to call from MainActor

    func process() async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            let results = try await service.processAll(items)
            // update @Published state on MainActor
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

## Local State with Reference-Type Members

When a view needs mutable state that includes reference types (timers, network clients, etc.), extract it to a `@MainActor final class`:

```swift
@MainActor
final class EditorState: ObservableObject {
    @Published var valueX: Double = 0
    @Published var valueY: Double = 0
    private var debounceTimer: Timer?  // Safe — class persists across re-renders

    func scheduleUpdate(action: @escaping () -> Void) {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            action()
        }
    }
}

struct EditorPanel: View {
    @StateObject private var state = EditorState()
    @EnvironmentObject var viewModel: AppViewModel
    // Bind sliders to state.valueX, state.valueY
}
```

## EnvironmentObject Injection

Always prefer `@EnvironmentObject` over `@ObservedObject` stored properties for shared view models. `@ObservedObject` as a stored property on a `View` struct can cause `MainActor.assumeIsolated` crashes when Button closures capture stale `self`.

```swift
// In root view or app entry:
ContentView()
    .environmentObject(viewModel)

// In any child view:
struct ChildView: View {
    @EnvironmentObject var viewModel: AppViewModel
    // No need to pass through init parameters
}
```

## Drag-and-Drop

```swift
.onDrop(of: [.jpeg, .png], isTargeted: $isDragging) { providers in
    for provider in providers {
        if provider.hasItemConformingToTypeIdentifier(.jpeg) {
            provider.loadDataRepresentation(forTypeIdentifier: .jpeg) { data, _ in
                if let data, let image = NSImage(data: data) {
                    // add image
                }
            }
        }
    }
    return true
}
```

## PhotosPicker (JPEG support)

- Load as `Data`, not `Image` — `Image` Transferable only exports PNG
- `item.loadTransferable(type: Data.self) { ... NSImage(data:) }`

## NSOpenPanel for Folder Browse

```swift
let panel = NSOpenPanel()
panel.canChooseDirectories = true
panel.canChooseFiles = false
if panel.runModal() == .OK, let url = panel.url { ... }
```

## NSSavePanel for Export

```swift
let panel = NSSavePanel()
panel.allowedContentTypes = [.jpeg]
panel.nameFieldStringValue = "Output.jpg"
let response = NSApplication.shared.runModal(for: panel)
if response == .OK, let url = panel.url { ... }
```
