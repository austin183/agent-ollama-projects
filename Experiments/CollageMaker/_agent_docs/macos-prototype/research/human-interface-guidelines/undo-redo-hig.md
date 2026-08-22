# Apple HIG — Undo and Redo Guidelines

## Source
https://developer.apple.com/design/human-interface-guidelines/undo-and-redo

## Overview

People expect undo and redo to let them reverse recent actions. They're likely to try undoing — often multiple times — until something changes. People might not remember which action an undo is targeting, which can lead to unintended changes and frustration.

## Best Practices

- **Help people predict results.** Describe the result of undo/redo wherever possible. On iPhone, the shake-to-undo alert describes the operation. In menu items, use labels like "Undo Typing" or "Redo Bold" instead of generic "Undo."

- **Show results of undo/redo.** If the undone action affects content no longer visible, highlight the result (e.g., scroll to show restored content). This prevents people from thinking the action had no effect and repeating it.

- **Let people undo multiple times.** Avoid unnecessary limits. People expect to undo every action since a logical step like opening a document or saving work.

- **Consider batch undo.** For discrete but related actions (e.g., incremental adjustments to a single property), allow undoing a batch at once rather than each individual adjustment.

- **Provide undo/redo buttons only when necessary.** People expect system-supported ways: Edit menu items, keyboard shortcuts (Command+Z, Shift+Command+Z), or shake on iPhone. If buttons are needed, use standard system symbols in a toolbar.

## macOS-Specific Considerations

- **Place undo/redo in Edit menu at top.** Mac users expect to find undo and redo at the top of the Edit menu.

- **Support standard keyboard shortcuts**: Command+Z for undo, Shift+Command+Z for redo.

- Use `UndoManager` from Foundation for implementation

## Not Supported

- tvOS
- watchOS

## Relevance to CollageMaker

Undo support is essential for an editing app like CollageMaker:

1. **Image reordering in sidebar**: Each move operation should be undoable
2. **Crop adjustments**: Pan and zoom changes to panel crops should be undoable
3. **Image removal**: Removing an image should be undoable
4. **Layout changes**: Switching layout style should be undoable
5. **Title text changes**: Editing title text should be undoable
6. **Background changes**: Changing background color/style should be undoable

Key implementation notes:
- Use `NSUndoManager` for undo tracking
- Register undo for each user action before making the change
- Use descriptive action names: "Undo Remove Image" not just "Undo"
- Consider batching related crop adjustments (drag pan should batch, not register each mouse event)
- Command+Z and Shift+Command+Z work automatically with NSUndoManager in macOS
- Don't add undo buttons to the UI — rely on Edit menu and keyboard shortcuts
- For `@Observable` objects, call `undoManager.registerUndo(withTarget:)` before state changes
