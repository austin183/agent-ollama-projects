# Apple HIG — Drag and Drop Guidelines

## Source
https://developer.apple.com/design/human-interface-guidelines/drag-and-drop

## Overview

Drag and drop lets people select content in one location (source) and drop it in another (destination). These can be in the same container, different containers, or different apps.

### Move vs. Copy

- **Same container**: Drop typically moves content
- **Different container**: Drop typically copies content
- **Between apps**: Always copies

### Platform Interactions

- **macOS**: Pointing device, Full Keyboard Access, VoiceOver
- **iOS/iPadOS**: Touchscreen gestures, pointing device, Full Keyboard Access
- **visionOS**: Pinch and hold while dragging in any direction (including z-axis)
- **Universal Control**: Drag between Mac and iPad

## Best Practices

- **Support drag and drop throughout your app.** People are familiar with drag and drop and often try it everywhere.

- **Offer alternative ways to accomplish drag-and-drop actions.** Include menu commands for copy/move. Use accessibility APIs for assistive technology support.

- **Determine move vs. copy based on user expectations.** Same container = move, different container = copy. Don't change defaults unless user expectation clearly differs.

- **Support multi-item drag and drop when it makes sense.** People appreciate dragging groups instead of individual items.

- **Prefer letting people undo drag-and-drop operations.** People sometimes drop in wrong destinations. If undo isn't possible, ask for confirmation before completing.

- **Consider offering multiple versions of dragged content.** Ordered from highest to lowest fidelity, so destination can choose what it accepts.

- **Consider supporting spring loading.** Activate controls by dragging content over them (e.g., dragging over toolbar segments).

## Providing Feedback

### Drag Image
- Display as soon as people drag about 3 points
- Create translucent representation to distinguish from original
- Display until content is dropped
- Modify to predict results (e.g., show default size in destination)
- Use drag flocking for multiple items
- Avoid constantly, radically changing drag image

### Destination Feedback
- Show whether destination accepts dragged content (highlight, insertion point)
- Show no feedback or "not allowed" indicator (circle.slash) when it can't
- Only highlight while content is above destination
- When multiple destinations exist, identify one at a time

### Invalid Drop Feedback
- Item moves back to source if visible
- Item scales up and fades out if source not visible

## Accepting Drops

- **Scroll destination contents when necessary.** Auto-scroll as people drag over scrolling containers.
- **Pick richest version of dropped content** your app can accept.
- **Extract only relevant portion** of dropped content if necessary.
- **Check for Option key at drop time** (with physical keyboard) to force copy within same container.
- **Provide feedback during time-consuming transfers** with progress indicator and placeholder.
- **Provide feedback when dropped content initiates a task.**
- **Apply appropriate styling to dropped text** (maintain source styles if destination supports them).
- **Maintain selection state after drop** in destination.

## macOS-Specific Considerations

- **Let people drag background selections.** Drag selected content from inactive window without activating it.
- **Let people drag individual items from inactive window** without affecting existing selection.
- **Display badge during multi-item drag** showing number of items.
- **Change pointer appearance** to indicate drop result: copy pointer, drag link, disappearing item, operation not allowed.
- **Let people select and drag with single motion** unless selecting multiple items.

## Relevance to CollageMaker

Drag and drop is already a core interaction pattern in CollageMaker:

1. **Sidebar to canvas drop**: Dragging images from sidebar onto canvas panels should assign the image to that panel. This is a cross-container drop, so it should copy (not remove from sidebar).

2. **Canvas panel to panel drop**: Dragging from one panel to another should swap images. Same container = move behavior.

3. **Finder to sidebar drop**: Already implemented via `.onDrop`. Dropping images from Finder adds them to the collage.

4. **Visual feedback during drag**:
   - Highlight target panel when dragging image over it
   - Show translucent drag image of the thumbnail
   - Show "not allowed" indicator when dragging over invalid targets
   - Badge for multi-image drops from Finder

5. **Alternative to drag-and-drop**: Context menu "Replace Image" and sidebar "Remove" button provide alternatives for people who can't use drag and drop.

6. **Undo support**: All drag-and-drop operations should be undoable via Command-Z.

Key implementation notes:
- Use `.onDrop()` and `.onDrag` modifiers in SwiftUI
- Use `NSItemProvider` for drag data
- Use `.queryDragOperations()` to declare expected operations (.move, .copy)
- Provide visual feedback with `.overlay()` on drop targets
- Use `circle.slash` SF Symbol for invalid drop targets
- Support Option key to force copy during same-container drag
- Register undo before completing drop operations
