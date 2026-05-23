# Commands and Menus

Mapping desktop actions into menu items, keyboard shortcuts, and focused scene behavior.

## Core Patterns

- Add `commands` at the scene level
- Use `CommandMenu` for app-specific actions
- Use `CommandGroup` to insert, replace, or remove menu sections
- Use `FocusedValue` or scene state to make commands context-sensitive
- Pair important commands with keyboard shortcuts and visible toolbar/content affordances

## Example

```swift
@main
struct SampleApp: App {
  var body: some Scene {
    WindowGroup {
      EditorRootView()
    }
    .commands {
      CommandMenu("Document") {
        Button("New Note") { /* create */ }
          .keyboardShortcut("n")

        Button("Toggle Inspector") { /* toggle */ }
          .keyboardShortcut("i", modifiers: [.command, .option])
      }
    }
  }
}
```

## Toolbar Organization

Use `.toolbar {}` on detail views to add window toolbar items. The system applies glass effects automatically on macOS 26+.

### Grouping Strategy

| Element | Purpose |
|---------|---------|
| `ToolbarItem` | Single item in its own glass pill |
| `ToolbarItemGroup` | Related items sharing one glass pill |
| `ToolbarSpacer(.flexible)` | Expands to push items apart |
| `ToolbarSpacer(.fixed)` | Small gap between adjacent groups |

### Toolbar Example

```swift
.toolbar {
    ToolbarSpacer(.flexible)

    ToolbarItem {
        ShareLink(item: document)
    }

    ToolbarSpacer(.fixed)

    ToolbarItemGroup {
        Button("Undo", systemImage: "arrow.uturn.left") { /* undo */ }
        Button("Redo", systemImage: "arrow.uturn.right") { /* redo */ }
    }

    ToolbarSpacer(.fixed)

    ToolbarItem {
        Button("Info", systemImage: "info") {
            isInspectorPresented.toggle()
        }
    }
}
```

### Custom Glass Buttons (macOS 26+)

```swift
Button {
    withAnimation { isExpanded.toggle() }
} label: {
    ToggleLabel(isExpanded: isExpanded)
}
.buttonStyle(.glass)
#if os(macOS)
.tint(.clear)  // macOS may need explicit tint clearing
#endif
```

## FocusedValues for Commands

Communicate selection from views up to menu commands:

```swift
// Define the key
extension FocusedValues {
    var selectedPanel: Binding<PanelID>? {
        get { self[SelectedPanelKey.self] }
        set { self[SelectedPanelKey.self] = newValue }
    }
    private struct SelectedPanelKey: FocusedValueKey {
        typealias Value = Binding<PanelID>
    }
}

// Publish from the view
.focusedSceneValue(\.selectedPanel, $viewModel.selectedPanelID)

// Receive in Commands
@FocusedBinding(\.selectedPanel) private var panel: PanelID?
```

**Key points:**
- `@FocusedBinding` is always optional — handle `nil` with `.disabled()`
- Scope is the scene/window, not the view hierarchy
- Multiple windows each receive their own focused values

## Pitfalls

- Do not register the same shortcut in multiple places
- Do not make commands the only discoverable path for a critical action
- If you need responder-chain validation or custom menu item state, use AppKit interop
- `SidebarCommands()` is required when using a sidebar — without it, the system won't provide "Toggle Sidebar" (Cmd+Option+0)
