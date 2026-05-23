# Apple HIG — Context Menus Guidelines

## Source
https://developer.apple.com/design/human-interface-guidelines/context-menus

## Overview

A context menu provides convenient access to frequently used items but is hidden by default. People reveal it by selecting content and performing an action:
- **macOS**: Control+click, or secondary click on Magic Trackpad
- **iOS/iPadOS**: System-defined touch or pinch and hold gesture
- **visionOS**: System-defined touch or pinch and hold gesture

## Best Practices

- **Prioritize relevancy.** A context menu isn't for advanced or rarely used items. It helps people quickly access the commands they're most likely to need in their current context.

- **Aim for a small number of menu items.** A context menu that's too long can be difficult to scan and scroll.

- **Support context menus consistently throughout your app.** If you provide context menus in some places but not others, people won't know where they can use the feature.

- **Always make context menu items available in the main interface too.** In macOS, the app's menu bar menus should list all commands, including those in context menus.

- **Keep submenus to one level.** More than one level of submenu complicates the experience.

- **Hide unavailable menu items, don't dim them.** A context menu displays only actions relevant to the currently selected content. Exception: Cut, Copy, and Paste may appear unavailable in macOS.

- **Place frequently used items where people encounter them first.** When a context menu opens, people often read from the part closest to where their pointer revealed it.

- **Show keyboard shortcuts in main menus, not in context menus.** Context menus already provide a shortcut to commands.

- **Follow separator best practices.** Use separators to group items, but no more than about three groups.

- **In iOS/iPadOS/visionOS, warn about destructive items.** List destructive items (Delete, Remove) at the end and identify them as destructive using the `destructive` role.

## Content

- A context menu seldom displays a title
- Include a title only if it clarifies the menu's effect (e.g., showing number of selected items)
- Each item needs a short label clearly describing what it does
- Represent menu item actions with familiar SF Symbols icons

## macOS-Specific Considerations

- On Mac, a context menu is sometimes called a contextual menu
- Use `NSMenu.popUpContextMenu(_:with:for:)` for AppKit, or `.contextMenu(menuItems:)` in SwiftUI

## Relevance to CollageMaker

Context menus are a natural fit for several interactions in the collage maker:

1. **Canvas panel context menu**: Right-click on a panel to offer "Replace Image", "Reset Crop", "Duplicate Panel", "Remove Image"
2. **Sidebar image context menu**: Right-click on a sidebar thumbnail for "Remove", "Replace", "Use as Background"
3. **Background context menu**: Right-click on canvas background for "Change Color", "Apply Gradient", "Set Background Image"

Key implementation notes:
- Use SwiftUI's `.contextMenu(menuItems:)` modifier
- Keep menus small (3-5 items max)
- Always also expose context menu actions in the main UI (toolbar, inspector)
- Use SF Symbols for consistency
- Destructive actions (Remove, Delete) should use `.role(.destructive)`
