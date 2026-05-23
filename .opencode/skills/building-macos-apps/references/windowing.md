# Windowing

Choosing the top-level scene model for a native macOS app.

## Scene Types

| Scene type | When to use |
|---|---|
| `WindowGroup(..., id:)` | Primary app window that should appear at launch; any scene with multiple independent instances |
| `Window` | Singleton utility windows, focused secondary surfaces, auxiliary/on-demand windows |
| `Settings` | Preferences — never bury settings inside the main content flow |
| `DocumentGroup` | Document-driven apps |
| `MenuBarExtra` | Menu bar primary apps |

## Example: Main App + Utility Window

```swift
@main
struct SampleApp: App {
  var body: some Scene {
    WindowGroup("Library", id: "library") {
      LibraryRootView()
    }

    Window("Inspector", id: "inspector") {
      InspectorRootView()
    }

    Settings {
      SettingsView()
    }
  }
}
```

## Opening Windows

- Use `openWindow(id:)` when a command, toolbar item, or button should open another scene
- Keep per-window state in the scene or `@SceneStorage`, not in a single global pile

## Pitfalls

- Avoid modeling every feature as a pushed destination inside one window
- Do not use only `Window(...)` for the main launch window in a menu-bar-plus-window app
- Avoid singleton state for window-specific selections or drafts
- If you need lower-level titlebar, tabbing, or window lifecycle control, use AppKit interop

## See Also

- `references/window-management.md` — macOS 15+ SwiftUI window modifiers: toolbar presentation, drag regions, placement, borderless windows
