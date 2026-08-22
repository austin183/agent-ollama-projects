# Apple HIG — Sidebars Guidelines

## Source
https://developer.apple.com/design/human-interface-guidelines/sidebars

## Overview

A sidebar floats above content without being anchored to the edges of the view. It provides a broad, flat view of an app's information hierarchy, giving access to several peer content areas or modes simultaneously.

A sidebar requires large vertical and horizontal space. When space is limited, a more compact control like a tab bar may be better.

## Best Practices

- **Extend content beneath the sidebar.** Sidebars float above content in the Liquid Glass layer. Extend content beneath by letting it scroll horizontally or applying a `backgroundExtensionEffect()` to mirror adjacent content.

- **Let people customize sidebar contents when possible.** A sidebar works best when people can decide which areas are most important and in what order.

- **Group hierarchy with disclosure controls** if the app has a lot of content. Keeps vertical space manageable.

- **Use familiar symbols for sidebar items.** SF Symbols provides customizable symbols. Prefer custom symbols over bitmap images.

- **Let people hide the sidebar.** In macOS, include a show/hide button or add "Show Sidebar" and "Hide Sidebar" commands to the View menu. Never hide by default — ensure discoverability.

- **Show no more than two levels of hierarchy.** For deeper hierarchies, use a split view with a content list between sidebar items and detail view.

- **Use succinct, descriptive labels for hierarchy groups.** Omit unnecessary words.

## macOS-Specific Considerations

- **Row height, text, and glyph size** depend on sidebar size (small, medium, large). People can change size in General settings.

- **Avoid fixed colors for sidebar icons.** Sidebar icons use the current accent color by default. People expect their chosen accent color throughout apps.

- **Consider auto-hiding on window resize.** Reducing window size can automatically collapse the sidebar for more content room.

- **Avoid putting critical information or actions at the bottom.** People often relocate windows in ways that hide the bottom edge.

- Use `NavigationSplitView` with `.sidebar` or `NSSplitViewController` in AppKit

## Relevance to CollageMaker

The CollageMaker sidebar (image list panel) should follow these guidelines:

1. **NavigationSplitView is the right choice** — The app already uses `NavigationSplitView` with sidebar + editor + inspector, which matches the recommended pattern.

2. **Show/hide sidebar** — Add "Toggle Sidebar" to the View menu with keyboard shortcut.

3. **Don't put critical actions at the bottom** — The "Add Images" button and layout controls should be at the top of the sidebar, not the bottom.

4. **Search field placement** — The search/filter field should be at the top of the sidebar for easy access.

5. **SF Symbols for icons** — Use SF Symbols for any sidebar item icons (image thumbnails are fine as they're content, not navigation icons).

6. **Background extension** — Consider using `backgroundExtensionEffect()` for the Liquid Glass floating appearance.

7. **Two-level hierarchy max** — The current flat list of images is appropriate. If grouping by album/folder were added, keep to two levels.

8. **Customizable order** — The `onMove` gesture already allows reordering, which aligns with the customization guidance.

Key implementation notes:
- Use `.sidebar()` modifier in NavigationSplitView
- View menu: "Toggle Sidebar" with `ToggleSidebarCommand`
- Keep add/remove controls at the sidebar top
- Status messages at the bottom are OK for non-critical info
