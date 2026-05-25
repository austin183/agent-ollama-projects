# HIG: Progress Indicators

## Determinate vs. Indeterminate

| Type | Use When | SwiftUI |
|---|---|---|
| **Determinate** | Known duration (export, file write) | `ProgressView(value: progress, total: 1.0)` |
| **Indeterminate** | Unknown duration (loading, syncing) | `ProgressView("Analyzing images...")` |

## Determinate Progress

```swift
// Linear progress bar with label
ProgressView(value: viewModel.exportProgress, total: 1.0) {
    Text("Exporting collage...")
}
```

## Indeterminate Progress

```swift
// Circular spinner — no label needed for user-initiated actions
ProgressView()
    .progressViewStyle(.circular)

// With label for clarity
ProgressView("Analyzing 5 images...")
    .progressViewStyle(.circular)
```

## Rules

- **Use determinate when possible** — helps users decide whether to wait
- **Be accurate** — don't show 90% in 5 seconds and stall at the last 10%
- **Keep indicators moving** — a stationary indicator suggests a frozen app
- **Switch from indeterminate to determinate** when duration becomes known
- **Don't switch between circular and bar styles** — different shapes cause disruptive transitions
- **Be specific with labels** — "Analyzing 5 images" not "Processing"
- **Consistent location** — display in the same place each time
- **Include Cancel** when interrupting has no negative side effects
- **Include Pause + Cancel** when interrupting causes data loss
- **Warn** when canceling results in lost progress

## macOS-Specific

- **Prefer activity indicator (spinner)** for background operations or constrained space
- **Avoid labeling spinning progress indicators** — spinner appears when user initiates, label usually unnecessary
- Use `ProgressView` in SwiftUI or `NSProgressIndicator` in AppKit
