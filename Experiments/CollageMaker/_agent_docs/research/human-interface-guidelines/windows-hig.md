# Apple HIG — Windows Guidelines

## Source
https://developer.apple.com/design/human-interface-guidelines/windows

## Overview

In macOS, windows define visual boundaries of app content, separate it from other areas, and enable multitasking. Two types:

- **Primary window**: Presents main navigation, content, and associated actions
- **Auxiliary window**: Presents a specific task or area. Dedicated to one experience, no navigation to other areas, typically includes a close button.

## Best Practices

- **Adapt fluidly to different sizes.** Support multitasking and multiwindow workflows.

- **Choose the right moment to open new windows.** Opening content in a separate window helps with multitasking but excessive windows create clutter. Avoid opening new windows as default behavior.

- **Consider providing the option to view content in a new window.** Let people choose via context menu or File menu command.

- **Avoid creating custom window UI.** System-provided windows look and behave in ways people understand. Custom window frames or controls can make an app feel broken.

- **Use the term "window" in user-facing content.** The system refers to app windows as windows. Using different terms (e.g., "scene") confuses people.

## macOS Window Anatomy

A macOS window consists of:
- **Frame**: Appears above body area; includes window controls (close, minimize, zoom) and optionally a toolbar
- **Body area**: Main content area
- **Bottom bar** (rare): Part of the frame below body content (e.g., Finder's status bar)

### Window States

1. **Main**: The frontmost window of an app. Only one per app.
2. **Key (active)**: Accepts user input. Only one onscreen at a time. Uses color in title bar controls.
3. **Inactive**: Not in foreground. Uses gray in controls, no vibrancy effect.

### macOS-Specific Guidance

- **Use system-defined appearances for custom windows.** People rely on visual differences to identify foreground window. Custom implementations must update appearances on state changes.

- **Avoid critical information or actions in bottom bar.** People often relocate windows hiding the bottom edge. If needed, use only for small amounts of information related to window contents. For more information, use an inspector.

- **Set minimum and maximum window sizes.** Prevent UI element overlap or unusable layouts at extreme sizes.

- Use `WindowGroup` in SwiftUI or `NSWindow` in AppKit

## Relevance to CollageMaker

Window management considerations:

1. **Primary window layout**: The main `NavigationSplitView` (sidebar + editor + inspector) is the primary window. Should adapt fluidly to resizing.

2. **Minimum window size**: Set appropriate minimum size to prevent the canvas, sidebar, and inspector from becoming unusable. Use `.frame(minWidth:minHeight:)` on the content view.

3. **Auxiliary windows**: Settings window is already an auxiliary window. Could add auxiliary windows for:
   - Font picker (if not using system panel)
   - Color picker with advanced options
   - Image import browser

4. **No custom window UI**: Don't create custom window frames or controls. Use system-provided window chrome.

5. **Bottom bar avoidance**: Status information (image count, canvas size) should not go in a bottom bar. The sidebar status area is the right place.

6. **Multi-window support**: Could let people open a second collage in a new window via File > New Window.

Key implementation notes:
- Use `.defaultSize()` for initial window dimensions
- Use `.frame(minWidth:minHeight:)` for minimum size constraints
- Consider `Commands` for View menu window controls
- Settings should use `.settings()` scene, not custom window
