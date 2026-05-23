# Menu Bar Extra

When the app primarily lives in the macOS menu bar instead of a traditional always-open window.

## Core Patterns

- Use `MenuBarExtra` for lightweight utilities, status indicators, quick actions
- If the app also has a primary main window at launch, use `WindowGroup(..., id:)` for that scene
- If the menu bar app should show in the Dock, install `@NSApplicationDelegateAdaptor`, call `NSApp.setActivationPolicy(.regular)` during launch, then `NSApp.activate(ignoringOtherApps: true)`
- If intentionally menu-bar-only, document that `.accessory` / no-Dock behavior is expected
- Keep menu content concise and action-oriented
- Cap each visible menu item label at 30 characters; truncate longer content and open full text in a window

## Example

```swift
import AppKit

private func shortMenuTitle(_ title: String) -> String {
  if title.count <= 30 { return title }
  return String(title.prefix(27)) + "..."
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }
}

@main
struct SampleApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup("Sample", id: "main") {
      ContentView()
    }

    MenuBarExtra("Sample", systemImage: "bolt.circle") {
      Button(shortMenuTitle("Open Dashboard")) { /* open window */ }
      Divider()
      Button("Quit") {
        NSApplication.shared.terminate(nil)
      }
    }
  }
}
```

## Pitfalls

- Do not rely on `Window(...)` alone for the main launch window in a menu-bar-plus-window app
- Do not silently ship a no-Dock menu-bar-only app if the user expects a normal app process
- Do not turn the menu bar extra into a tiny, overloaded substitute for a full app window
- Do not render raw unbounded titles or message bodies as menu items
- If the extra needs advanced status item customization, use AppKit interop
