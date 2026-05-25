# FocusedValues (Cross-View Communication)

Communicate selection state from a detail view up to menu bar commands without passing bindings through the view hierarchy.

```swift
// 1. Define the key
extension FocusedValues {
    var selectedPanel: Binding<PanelID>? {
        get { self[SelectedPanelKey.self] }
        set { self[SelectedPanelKey.self] = newValue }
    }
    private struct SelectedPanelKey: FocusedValueKey {
        typealias Value = Binding<PanelID>
    }
}

// 2. Publish from the detail view
CanvasView()
    .focusedSceneValue(\.selectedPanel, $viewModel.selectedPanelID)

// 3. Receive in Commands
struct CollageCommands: Commands {
    @FocusedBinding(\.selectedPanel) private var panel: PanelID?

    var body: some Commands {
        CommandMenu("Panel") {
            Button("Reset Panel") {
                viewModel.resetPanel(panel!)
            }
            .disabled(panel == nil)
        }
    }
}
```

**Key points:**
- Scope is the scene/window, not the view hierarchy
- `@FocusedBinding` is always optional — commands must handle `nil` with `.disabled()`
- Multiple windows each receive their own focused values
- Define `FocusedValueKey` with `typealias Value`, extend `FocusedValues` with subscript access
