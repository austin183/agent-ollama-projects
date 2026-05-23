# AppKit Interop

Bridging SwiftUI to AppKit for macOS behaviors SwiftUI doesn't model cleanly. Keep the bridge small and explicit. SwiftUI owns value state; AppKit handles the imperative edge.

## Choose the Smallest Bridge

| Bridge type | When to use |
|---|---|
| Pure SwiftUI | Behavior exists in scenes, toolbars, commands, inspectors, standard controls |
| `NSViewRepresentable` | Specific AppKit view with lightweight lifecycle |
| `NSViewControllerRepresentable` | Controller lifecycle, delegation, presentation coordination |
| Custom `NSView` event capture | Raw `scrollWheel(with:)` for canvas pan, custom key handling |
| Direct AppKit hooks | `NSWindow`, responder chain, menu validation, panels, app-level behavior |

## NSViewRepresentable

Use for wrapping AppKit controls (`NSTextView`, `NSScrollView`, custom controls).

```swift
struct LegacyTextView: NSViewRepresentable {
  @Binding var text: String

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    let textView = NSTextView()
    textView.delegate = context.coordinator
    scrollView.documentView = textView
    return scrollView
  }

  func updateNSView(_ nsView: NSScrollView, context: Context) {
    guard let textView = nsView.documentView as? NSTextView else { return }
    if textView.string != text {
      textView.string = text
    }
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    @Binding var text: String
    init(text: Binding<String>) { _text = text }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      text = textView.string
    }
  }
}
```

**Pitfalls:**
- Avoid infinite update loops — only push state when values actually changed
- Keep delegates and target-action wiring in the coordinator
- If the wrapper grows into a full screen, re-evaluate the boundary

## NSViewControllerRepresentable

Use when you need controller lifecycle, delegate coordination, or AppKit presentation logic (e.g., hosting a document controller, coordinating multiple views).

## Windows and Panels

Prefer SwiftUI `Window`, `WindowGroup`, and `openWindow` first. Use AppKit only for features SwiftUI doesn't expose.

```swift
@MainActor
func chooseFile() -> URL? {
  let panel = NSOpenPanel()
  panel.canChooseFiles = true
  panel.canChooseDirectories = false
  panel.allowsMultipleSelection = false
  return panel.runModal() == .OK ? panel.url : nil
}
```

- Keep file open/save panels behind a small service, not scattered through views
- Do not let random views own long-lived `NSWindow` references

## Responder Chain and Menus

Start with SwiftUI `commands`, `FocusedValue`, and focused scene state. Use AppKit responder-chain hooks only when:
- Validating whether a menu item should be enabled
- Routing actions through the current first responder
- Integrating with existing AppKit document or text behaviors

**Pitfalls:**
- Do not recreate AppKit-style global command handling when SwiftUI focused values work
- Avoid scattering command logic between SwiftUI closures and AppKit selectors

## Drag, Drop, and Pasteboard

Start with SwiftUI drag/drop APIs. Drop to AppKit when you need:
- `NSPasteboard` and custom pasteboard types
- File URL dragging with rich previews
- AppKit-specific drop validation
- Legacy AppKit views with custom drag types

- Keep data conversion at the boundary, not leaking AppKit types through features
- Do not move a whole list or canvas into AppKit for one drop target

## Guardrails

- Do not duplicate source of truth between SwiftUI and AppKit
- Do not let `Coordinator` become an unstructured dumping ground
- Do not store long-lived `NSView` or `NSWindow` instances globally
- Prefer a tiny tested bridge over rewriting the feature in raw AppKit
- If a pattern can remain in SwiftUI, keep it there

## Pitfalls

- **PhotosPicker JPEG** — load as `Data`, not `Image` (Transferable only does PNG)
- **NSImage cgImage** — may return nil for empty/synthetic images; always guard
- **Security-scoped URLs** — call `startAccessingSecurityScopedResource()` / `stopAccessing...`
- **SF Symbol names don't follow intuitive patterns** — `text.align.left` does NOT exist. Correct names: `text.alignleft`, `text.aligncenter`, `text.alignright` (no dot between "align" and direction). Invalid names render as empty placeholders with no click response. Use `playwright-apple-docs` to search `developer.apple.com/design/human-interface-guidelines/icons` when unsure — the page is a JS SPA; `webfetch` returns only noscript placeholders.
