# HIG: Keyboard Shortcuts

## Standard Shortcuts (don't repurpose)

| Shortcut | Action |
|---|---|
| Command-Z | Undo |
| Shift-Command-Z | Redo |
| Command-A | Select all |
| Command-C / X / V | Copy / Cut / Paste |
| Command-S | Save |
| Command-N | New document |
| Command-O | Open |
| Command-W | Close window |
| Command-Q | Quit app |
| Command-, | Settings |
| Command-F | Find |
| Command-P | Print |
| Command-M | Minimize |
| Control-Command-F | Full screen |
| Command-Period | Cancel |
| Option-Command-I | Inspector |
| Option-Command-T | Show/hide toolbar |
| Tab / Shift-Tab | Next / Previous control |
| Escape | Cancel |

## Custom Shortcuts

Define only for most frequently used app-specific commands.

```swift
// In Commands group:
CommandGroup(replacing: .newItem) {
    Button("Uniform Layout") { viewModel.layout = .uniform }
        .keyboardShortcut("1", modifiers: .command)
    Button("Hero Layout") { viewModel.layout = .hero }
        .keyboardShortcut("2", modifiers: .command)
    Button("Mosaic Layout") { viewModel.layout = .mosaic }
        .keyboardShortcut("3", modifiers: .command)
}

Button("Export…") { isShowingExport = true }
    .keyboardShortcut("e", modifiers: .command)

Button("Add Images…") { viewModel.addImages() }
    .keyboardShortcut("l", modifiers: [.command, .option])
```

### Suggested Custom Shortcuts

| Shortcut | Action |
|---|---|
| Command-1 / 2 / 3 | Switch layout |
| Command-E | Export collage |
| Command-Option-L | Add images |
| Command-Option-B | Toggle background panel |
| Delete / Backspace | Remove selected panel's image |
| Command-Option-R | Reset selected panel crop |

## Modifier Key Rules

- **Command**: Primary modifier, prefer for main shortcuts
- **Shift**: Secondary modifier complementing a related shortcut
- **Option**: Sparingly, for less-common commands or power features
- **Control**: Avoid — system uses Control for systemwide features
- **List modifiers in order**: Control, Option, Shift, Command
- **Avoid adding Shift to shortcuts using upper characters** — Shift is already held

## Implementation

```swift
// SwiftUI modifier on Button:
.keyboardShortcut("e", modifiers: .command)

// Type-safe alternative:
.keyboardShortcut(#CommandShortcut("e"))

// In Commands group:
CommandMenu("View") {
    Button("Toggle Sidebar") { isSidebarVisible.toggle() }
        .keyboardShortcut("s", modifiers: [.command, .option])
}
```

Shortcuts defined in `Commands` automatically appear in the menu bar.
