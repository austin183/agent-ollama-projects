# HIG: Context Menus

## SwiftUI Context Menu

```swift
// Panel context menu on canvas
PanelView(panel: panel)
    .contextMenu {
        Button("Replace Image", systemImage: "photo.badge.plus") {
            viewModel.replaceImage(for: panel.id)
        }
        Button("Reset Crop", systemImage: "arrow.counterclockwise") {
            viewModel.resetCrop(for: panel.id)
        }
        Divider()
        Button("Remove Image", systemImage: "trash", role: .destructive) {
            viewModel.removeImage(from: panel.id)
        }
    }
```

## Context Menu Rules

- **Prioritize relevancy** — only commands most likely needed in current context
- **Keep menus small** — 3-5 items max
- **Support consistently** — if context menus exist in one place, provide everywhere applicable
- **Always also expose in main UI** — menu bar, toolbar, or inspector must also have the commands
- **Hide unavailable items, don't dim** — only show actions relevant to current selection
- **One level of submenus max**
- **Don't show keyboard shortcuts in context menus** — they belong in main menus
- **No more than ~3 separator groups**

## Destructive Items

List destructive items (Delete, Remove) at the end, use `.role(.destructive)`:

```swift
.contextMenu {
    Button("Replace Image") { }
    Button("Reset Crop") { }
    Divider()
    Button("Remove Image", role: .destructive) { }
}
```

## Suggested Context Menus

| Location | Items |
|---|---|
| Canvas panel | Replace Image, Reset Crop, Remove Image |
| Sidebar thumbnail | Remove, Replace |
| Canvas background | Change Color, Set Background Image |

## Titles

A context menu seldom displays a title. Include only if it clarifies the menu's effect (e.g., selected item count).
