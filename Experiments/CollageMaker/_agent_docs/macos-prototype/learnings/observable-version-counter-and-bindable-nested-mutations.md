# @Observable Version Counter & @Bindable Nested Struct Mutations — Learnings

**Date:** 2026-06-01
**Session:** 76
**Purpose:** Document learnings from debugging title background color not updating in preview and flaky unit test.

---

## @Observable Version Counter for Async Delegate Mutations

When a computed property on an `@Observable` class delegates to another `@Observable` object's property, and that delegate is mutated asynchronously (e.g., in a `Task`), the parent's observation system doesn't know the computed property has changed.

**Scenario:**
```swift
@Observable class CollageViewModel {
    let previewManager: PreviewManager  // @Observable

    var titleImage: NSImage? {
        get { previewManager.titleImage }  // computed, delegates
        set { previewManager.titleImage = newValue }
    }

    func updateTitleImage() {
        // previewManager updates titleImage asynchronously via Task
        // but views observing viewModel.titleImage never re-render
    }
}

@Observable class PreviewManager {
    var titleImage: NSImage?

    func updateTitleImage(...) {
        titleTask = Task { [weak self] in
            // ... async rendering ...
            self?.titleImage = result  // mutation happens here
            // CollageViewModel.titleImage getter isn't re-invoked
        }
    }
}
```

**Symptom:** The async rendering completes, `previewManager.titleImage` is set, but the SwiftUI view that reads `viewModel.titleImage` never re-renders. The value is correct if you print it, but the view is stale.

**Fix — Version counter pattern:**
```swift
@Observable class CollageViewModel {
    private var titleImageVersion = 0

    var titleImage: NSImage? {
        get {
            let _ = titleImageVersion  // establishes observation dependency
            return previewManager.titleImage
        }
        set { previewManager.titleImage = newValue }
    }

    func updateTitleImage() {
        titleImageVersion += 1  // forces observation re-tracking
        previewManager.updateTitleImage(...)
    }
}
```

The `let _ = titleImageVersion` read in the getter registers `titleImageVersion` as an observation dependency. Incrementing it in `updateTitleImage()` triggers the observation system to re-evaluate any view that reads `viewModel.titleImage`.

**Why this over the delegation chain fix?** The `@Observable` delegation chain fix (from session 58) prescribes making the delegate `@Observable` and having the view read `viewModel.previewManager.titleImage` directly. That works but exposes the delegate's internal structure to the view. The version counter keeps the delegation abstraction intact — the view only knows about `viewModel.titleImage`.

**When to use which approach:**

| Approach | Pros | Cons |
|---|---|---|
| Version counter | Preserves abstraction, view reads single property | Requires manual increment at every mutation site |
| Direct delegate read | Automatic, no manual increment | Exposes delegate structure to view, tighter coupling |

**Existing precedent:** `cropMapVersion` in `CollageViewModel` uses this same pattern for `cropMap` delegation to `CropManager`.

---

## @Bindable Nested Struct Mutations Bypass didSet

When using `@Bindable` bindings to nested struct properties on an `@Observable` class, SwiftUI's observation system may handle the mutation through its own tracking mechanism rather than through the traditional property setter. This means `didSet` observers on the parent property don't fire for all mutation paths.

**Scenario:**
```swift
@Observable class CollageViewModel {
    var titleStyle: TitleStyle = .default {
        didSet {
            // This may NOT fire when binding mutates a nested property
            updatePreview()
        }
    }
}

struct ExportPanel: View {
    @Bindable var viewModel: CollageViewModel

    var body: some View {
        // This binding may bypass titleStyle.didSet
        NSColorPickerView(color: $viewModel.titleStyle.backgroundColor)
    }
}
```

**Symptom:** The UI control updates the value (the color changes in the model), but side effects in `didSet` (like `updatePreview()`) don't fire. The property value is correct but dependent views and async work don't execute.

**Fix — Explicit setter methods:**
```swift
@Observable class CollageViewModel {
    var titleStyle: TitleStyle = .default {
        didSet { ... }  // still useful for direct assignments
    }

    func setTitleBackgroundColor(_ color: NSColor) {
        titleStyle.backgroundColor = color
        updatePreview()  // guaranteed to fire
        debouncedSave()
    }
}

struct ExportPanel: View {
    @Bindable var viewModel: CollageViewModel

    var body: some View {
        NSColorPickerView(
            color: Binding(
                get: { viewModel.titleStyle.backgroundColor },
                set: { viewModel.setTitleBackgroundColor($0) }
            )
        )
    }
}
```

**Why this happens:** `@Bindable` generates observation code that tracks individual property paths. For nested struct properties, it may use `withMutation` to report changes at the nested level without invoking the parent property's setter. This is by design — `@Observable` wants to minimize unnecessary setter overhead. But it means `didSet` is not a reliable place for side effects when `@Bindable` bindings are involved.

**Diagnostic clue:** If a binding "works" (the value changes in the model) but side effects don't fire, check whether the binding targets a nested property of a struct and whether the side effects live in the parent property's `didSet`.

---

## NSColorWell Target/Action Re-assignment in updateNSView

`NSColorWell` may reset its `target` and `action` when added to or reconfigured in the view hierarchy. If `updateNSView` doesn't re-set these, the coordinator reference can be lost after a SwiftUI view update cycle.

**Fix:**
```swift
func updateNSView(_ well: NSColorWell, context: Context) {
    well.color = color
    well.target = context.coordinator    // re-set every update
    well.action = #selector(Coordinator.colorChanged(_:))
}
```

---

## UserDefaults Test Isolation with UUID Suite Names

When tests create ViewModel instances that load from `UserDefaults`, debounced saves from one test can pollute the next test's initial state. Each test needs an isolated `UserDefaults` suite.

**Pattern:**
```swift
private func makeViewModel() -> CollageViewModel {
    let suiteName = "Tests.\(UUID().uuidString)"
    let testDefaults = UserDefaults(suiteName: suiteName)!
    let persistence = UserDefaultsPersistence(defaults: testDefaults)
    return CollageViewModel(saliencyAnalyzer: ..., assembler: ..., persistence: persistence)
}
```

The UUID ensures each ViewModel gets a fresh, empty `UserDefaults` that no other test can access. No cleanup needed — the suite is abandoned after the test completes.

---

**Status:** Closed
**Follow-up:** None
