# Settings

Building a native macOS settings window with SwiftUI.

## Core Patterns

- Declare a dedicated `Settings` scene in the app
- Keep settings content in a separate root view
- Use `@AppStorage` for user preferences that should persist
- Prefer tabs, sections, or split settings layout over deep push navigation
- Use `SettingsLink` or `OpenSettingsAction` for in-app entry points

## Example

```swift
@main
struct SampleApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
    }

    Settings {
      SettingsView()
    }
  }
}

struct SettingsView: View {
  @AppStorage("showSidebarIcons") private var showSidebarIcons = true

  var body: some View {
    TabView {
      Form {
        Toggle("Show Sidebar Icons", isOn: $showSidebarIcons)
      }
      .tabItem { Label("General", systemImage: "gearshape") }
    }
    .frame(width: 460, height: 260)
    .scenePadding()
  }
}
```

## Pitfalls

- Do not reuse an iOS full-screen settings screen for macOS
- Keep settings rows simple and accessible
- If settings require custom panels or responder integration, use AppKit interop
