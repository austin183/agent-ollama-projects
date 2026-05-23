# Apple HIG — Keyboard Shortcuts and Navigation Guidelines

## Source
https://developer.apple.com/design/human-interface-guidelines/keyboards

## Overview

Keyboard shortcuts are combinations of primary keys and modifier keys (Control, Option, Shift, Command) that map to specific commands. Apple defines standard shortcuts to work consistently across the system.

## Best Practices

- **Support Full Keyboard Access when possible.** Lets people navigate and activate windows, menus, controls, and system features using only the keyboard.

- **Respect standard keyboard shortcuts.** Don't repurpose standard shortcuts for custom actions. Only redefine if the standard action doesn't make sense in your experience.

## Standard Keyboard Shortcuts (macOS-relevant subset)

| Shortcut | Action |
|---|---|
| Command-Z | Undo |
| Shift-Command-Z | Redo |
| Command-A | Select all |
| Command-C | Copy |
| Command-X | Cut |
| Command-V | Paste |
| Command-S | Save |
| Shift-Command-S | Save As / Duplicate |
| Command-N | New document |
| Command-O | Open |
| Command-W | Close window |
| Command-Q | Quit app |
| Command-, | Settings |
| Command-F | Find |
| Command-P | Print |
| Command-M | Minimize window |
| Control-Command-F | Full screen |
| Command-? | Help |
| Command-Period | Cancel operation |
| Command-I | Inspector (Option-Command-I) |
| Option-Command-T | Show/hide toolbar |
| Command-` | Next window in app |
| Tab | Next control |
| Shift-Tab | Previous control |
| Escape | Cancel |

## Custom Keyboard Shortcuts

- **Define only for most frequently used app-specific commands.** Too many shortcuts makes an app seem difficult to learn.

- **Use modifier keys as expected:**
  - **Command**: Main modifier key, prefer for primary shortcuts
  - **Shift**: Secondary modifier complementing a related shortcut
  - **Option**: Sparingly, for less-common commands or power features
  - **Control**: Avoid — the system uses Control for many systemwide features

- **List modifiers in correct order**: Control, Option, Shift, Command

- **Avoid adding Shift to shortcuts using upper characters.** People already hold Shift for upper characters.

- **Avoid creating shortcuts by adding modifier to existing shortcut for unrelated command.**

## Modifier Key Symbols

| Key | Symbol |
|---|---|
| Command | ⌘ |
| Shift | ⇧ |
| Option | ⌥ |
| Control | ⌃ |

## Relevance to CollageMaker

Keyboard shortcuts to implement:

1. **Standard shortcuts** (already work by convention):
   - Command-Z / Shift-Command-Z: Undo/Redo (with NSUndoManager)
   - Command-, : Open Settings
   - Command-W: Close window
   - Command-Q: Quit
   - Command-`: Cycle windows (if multi-window)

2. **Custom shortcuts for frequent actions**:
   - Command-1, Command-2, Command-3: Switch layout (Uniform, Hero, Mosaic)
   - Command-E: Export collage
   - Command-Option-L: Open image library (add images)
   - Command-Option-B: Toggle background panel

3. **View menu shortcuts**:
   - Option-Command-T: Toggle toolbar
   - Command-Option-S: Toggle sidebar
   - Option-Command-I: Toggle inspector

4. **Canvas editing shortcuts**:
   - Delete/Backspace: Remove selected panel's image
   - Command-Option-R: Reset selected panel crop
   - Arrow keys: Nudge selected panel crop (when panel selected)

Key implementation notes:
- Use `.keyboardShortcut()` modifier in SwiftUI
- Use `#CommandShortcut` for type-safe shortcuts
- Define in `Commands` group for menu bar integration
- Example: `Button("Export") { }.keyboardShortcut("e", modifiers: .command)`
- Show shortcuts in menu bar items automatically
- Don't override standard shortcuts (Command-C, Command-V, etc.)
