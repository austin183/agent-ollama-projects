# HIG: Sidebars

## NavigationSplitView Structure

```swift
NavigationSplitView {
    SidebarView()
        .toolbar { /* sidebar controls */ }
} content: {
    EditorView()
} detail: {
    InspectorView()
}
```

## Sidebar Rules

- **Float above content** — sidebars use Liquid Glass layer, not anchored to edges
- **Show/hide available** — View menu must have "Toggle Sidebar" command
- **Never hide by default** — ensure discoverability
- **No more than two levels of hierarchy** — use disclosure controls for grouping
- **Succinct, descriptive labels** — omit unnecessary words
- **SF Symbols for icons** — prefer over bitmap images
- **Use accent color** — don't use fixed colors for sidebar icons
- **Avoid critical information at bottom** — users often relocate windows hiding the bottom edge

## Show/Hide Sidebar

```swift
// In Commands:
CommandGroup(after: .sidebar) {
    Button("Toggle Sidebar") {
        isSidebarVisible.toggle()
    }
    .keyboardShortcut("s", modifiers: [.command, .option])
}
```

## Content Placement

| Position | Content |
|---|---|
| **Top** | Add images button, layout controls, search/filter |
| **Middle** | Image list, scrollable content |
| **Bottom** | Status text (non-critical info like image count) |

## Background Extension

Use `backgroundExtensionEffect()` for Liquid Glass floating appearance:

```swift
NavigationSplitView {
    SidebarView()
        .backgroundExtensionEffect()
} content: {
    EditorView()
}
```

## Auto-Hide on Resize

Consider collapsing sidebar automatically when window is resized small for more content room.
