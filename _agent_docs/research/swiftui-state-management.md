# SwiftUI State Management — Patterns and Pitfalls

## Property Wrappers Overview

| Wrapper | Purpose | Lifetime | Equatable Required |
|---|---|---|---|
| `@State` | Local value-type state | Survives view recreation | Yes |
| `@StateObject` | Local `ObservableObject` | Survives view recreation | No (reference type) |
| `@ObservedObject` | External `ObservableObject` | Tied to parent's injection | No (reference type) |
| `@EnvironmentObject` | Inherited from hierarchy | Managed by SwiftUI | No (reference type) |

## `@State` — Value Types Only

`@State` is designed for **`Equatable` value types** (Int, Double, Bool, String, structs).

### How It Works
- SwiftUI stores the actual value **outside** the View struct
- When the View struct is recreated during body recomputation, `@State` restores the stored value
- SwiftUI uses `Equatable` to determine if the value changed and whether to trigger a re-render

### The Timer Trap
```swift
// WRONG — Timer? is a reference type, not Equatable
@State private var debounceTimer: Timer?

// What happens:
// 1. Slider onChange schedules a timer
// 2. Timer fires, calls updatePreview()
// 3. updatePreview() changes @Published state → view re-renders
// 4. SwiftUI recreates PanelCropEditor struct
// 5. @State's Equatable check on Timer? fails to track the reference
// 6. Timer reference is lost/deallocated
// 7. All subsequent timer schedules fire into deallocated memory
```

### Fix: Use `@StateObject` for Reference Types
```swift
// Create a class to hold mutable reference-type state
@MainActor
final class CropEditorState: ObservableObject {
    @Published var offsetX: Double = 0
    @Published var offsetY: Double = 0
    @Published var zoom: Double = 1
    var debounceTimer: Timer?  // Regular property — survives re-renders
}

// In the View
@StateObject private var state = CropEditorState()
```

### Fix: Move Timer to ViewModel
Better yet, move the debounce timer to the `@MainActor class CollageViewModel: ObservableObject` where it naturally persists:
```swift
@MainActor
class CollageViewModel: ObservableObject {
    private var cropDebounceTimer: Timer?
    
    @Published var cropOffsetX: Double = 0
    @Published var cropOffsetY: Double = 0
    @Published var cropZoom: Double = 1
    
    func scheduleCropUpdate() {
        cropDebounceTimer?.invalidate()
        cropDebounceTimer = Timer.scheduledTimer(
            withTimeInterval: 0.3,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyCropSliderValues()
            }
        }
    }
}
```

## `@ObservedObject` vs `@EnvironmentObject`

### The `@ObservedObject` Crash Pattern
When `@ObservedObject` is a **stored property** on a View struct:
```swift
struct PanelCropEditor: View {
    @ObservedObject var viewModel: CollageViewModel  // Stored reference
    let panel: ImagePanel
    
    var body: some View {
        Button("Reset Crop") {
            viewModel.resetCrop(for: panel.id)  // Captures self
        }
    }
}
```

**What goes wrong:**
1. SwiftUI calls `body` to render the view
2. The Button closure captures `self` (the View struct instance)
3. When state changes, SwiftUI recreates the View struct
4. The old closure still references the old struct instance
5. `MainActor.assumeIsolated` fails because the captured `self` no longer matches the current MainActor executor context
6. **Result: `EXC_CRASH (SIGABRT)`**

### The `@EnvironmentObject` Fix
```swift
struct PanelCropEditor: View {
    @EnvironmentObject var viewModel: CollageViewModel  // Injected, not stored
    let panel: ImagePanel
    
    var body: some View {
        Button("Reset Crop") {
            viewModel.resetCrop(for: panel.id)
        }
    }
}

// In the parent view
var body: some View {
    NavigationSplitView {
        // ...
    }
    .environmentObject(viewModel)  // Provide to entire hierarchy
}
```

**Why it works:**
- `@EnvironmentObject` doesn't store a direct reference in the View struct
- SwiftUI resolves the reference from the environment at render time
- The closure captures the environment lookup, not a stale struct instance
- Always points to the current, valid ViewModel instance

### When to Use Each

| Scenario | Use |
|---|---|
| ViewModel created by this view | `@StateObject` |
| ViewModel passed from parent (explicit) | `@ObservedObject` (in init) |
| ViewModel shared across hierarchy | `@EnvironmentObject` |
| `@MainActor` ObservableObject | Prefer `@EnvironmentObject` |

## `@State` with Value Types That Go Stale

### The `let panel` Problem
```swift
struct PanelCropEditor: View {
    let panel: ImagePanel  // Value copy — can go stale!
    
    var body: some View {
        // If panel is mutated externally, this view has the old copy
    }
}
```

When the parent view recomputes its body, it passes the **current** `panel` value. But if the panel's data is derived from ViewModel state and the ViewModel updates between renders, the view may have a stale copy.

### Fix: Derive from ViewModel or Use `@State`
```swift
// Option A: Read from ViewModel (always current)
@EnvironmentObject var viewModel: CollageViewModel
// Look up panel by ID from viewModel.panels

// Option B: @State with sync mechanism
@State private var panel: ImagePanel
.onAppear { panel = initialPanel }
// Sync when needed
```

## View Identity and `.id()`

SwiftUI determines whether to reuse or recreate a view based on its **identity**. For views in a `ForEach` or conditionally shown views:

```swift
// Without .id() — SwiftUI may treat this as a "new" view each time
if let selected = selectedPanel {
    PanelCropEditor(panel: selected)
}

// With .id() — stabilizes identity across recomputations
if let selected = selectedPanel {
    PanelCropEditor(panel: selected)
        .id(selected.id)  // Same UUID = same view instance
}
```

## Summary: CollageMaker State Rules

1. **Never store `Timer?` in `@State`** — use a class or ViewModel
2. **Prefer `@EnvironmentObject`** for `@MainActor` ObservableObjects shared across views
3. **Use `@State`** only for `Equatable` value types (Double, Int, Bool, String)
4. **Use `.id()`** on views that depend on selected/conditional data to stabilize identity
5. **Derive panel data from ViewModel** rather than capturing value copies that can go stale
