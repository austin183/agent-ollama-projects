# Apple HIG — Progress Indicators Guidelines

## Source
https://developer.apple.com/design/human-interface-guidelines/progress-indicators

## Overview

Progress indicators are transient — appearing only while an operation is ongoing and disappearing after completion. Two types:

- **Determinate**: For tasks with a well-defined duration (file conversion, export)
- **Indeterminate**: For unquantifiable tasks (loading, synchronizing complex data)

Both can have different appearances per platform:
- **Progress bar**: Linear track filling from leading to trailing side
- **Circular progress indicator**: Track filling clockwise
- **Activity indicator (spinner)**: Animated spinning image for indeterminate tasks

macOS supports both indeterminate progress bars and circular activity indicators.

## Best Practices

- **Use determinate when possible.** Indeterminate shows a process is occurring but doesn't help estimate duration. Determinate helps people decide whether to wait, restart, or abandon.

- **Be accurate with advancement.** Evening out the pace helps people feel confident about remaining time. Showing 90% in 5 seconds and the last 10% in 5 minutes feels deceptive.

- **Keep indicators moving.** A stationary indicator suggests a stalled process or frozen app. If a process stalls, provide feedback about the problem.

- **Switch from indeterminate to determinate when possible.** When an indeterminate process reaches a point where duration is known, switch to determinate.

- **Don't switch between circular and bar styles.** Different shapes and sizes make transitions disruptive.

- **Display helpful descriptions.** Be accurate and succinct. Avoid vague terms like "Loading" or "Authenticating."

- **Use consistent location.** Helps people reliably find operation status.

- **Let people halt processing when feasible.** Include a Cancel button if interrupting has no negative side effects. Provide Pause in addition to Cancel if interrupting causes data loss.

- **Warn about negative consequences of halting.** When canceling results in lost progress, provide an alert with confirm/resume options.

## macOS-Specific Considerations

- **Prefer activity indicator (spinner) for background operations or constrained space.** Spinners are small and unobtrusive, useful for async background tasks like server retrieval.

- **Avoid labeling spinning progress indicators.** Because a spinner typically appears when people initiate a process, a label is usually unnecessary.

- Use `ProgressView` in SwiftUI or `NSProgressIndicator` in AppKit

## Relevance to CollageMaker

Progress indicators are critical for several operations:

1. **Saliency analysis**: Processing images through Vision framework is indeterminate initially, but could become determinate if tracking multiple images (e.g., "Analyzing image 3 of 8").

2. **Export/Save**: JPEG export is determinate — can track file write progress. Should show percentage or fraction.

3. **Image loading**: When adding images via file browser, use indeterminate spinner if images are large.

4. **Layout generation**: Fast operation, may not need indicator unless image count is high.

Key implementation notes:
- Use SwiftUI `ProgressView` with `.progressViewStyle(.circular)` for indeterminate
- Use `ProgressView` with `value:total` for determinate
- For export, show "Exporting..." with determinate progress
- For saliency, show "Analyzing images..." with indeterminate (switch to determinate if tracking count)
- Never use vague labels; be specific: "Analyzing 5 images" not "Processing"
