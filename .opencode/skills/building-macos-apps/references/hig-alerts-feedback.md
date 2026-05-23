# HIG: Alerts and Feedback

## When to Alert vs. Inline Feedback

| Situation | Method |
|---|---|
| Uncommon destructive action (clear all) | Alert with confirmation |
| Unexpected error (export fails) | Alert with specific message |
| Common undoable action (remove image, change layout) | **No alert** — rely on undo |
| Expected success (export completes) | Brief inline status message |
| Background processing (saliency analysis) | Indeterminate progress indicator |
| Startup issues (no images) | Empty state, not alert |

## Alert Patterns

```swift
// Destructive confirmation — uncommon action
.alert("Clear All Images?", isPresented: $showingClearAlert) {
    Button("Clear All", role: .destructive) { viewModel.clearAll() }
    Button("Cancel", role: .cancel) { }
} message: {
    Text("This will remove all images from the collage.")
}

// Error — specific, actionable
.alert("Couldn't Save Collage", isPresented: $showingExportError) {
    Button("Retry") { viewModel.retryExport() }
    Button("OK", role: .cancel) { }
} message: {
    Text("Disk full. Free up space and try again.")
}
```

## Alert Rules

- **Use sparingly** — alerts interrupt the current task
- **Title**: Specific, describe what happened. Never "Error" or "Error 329347 occurred"
- **Button titles**: Specific verbs ("Clear All", "Retry"), not "OK" for actions
- **Cancel**: Always use "Cancel" for cancel button, place on leading side (left)
- **Destructive**: Use `.role(.destructive)` for destructive buttons; always pair with Cancel
- **Never make Cancel the default button**
- **Support Escape** to dismiss alerts
- **Avoid for undoable actions** — removing single image, resetting crop, changing layout
- **Avoid at app startup** — show empty state or cached data instead

## Inline Feedback

```swift
// Brief success message — auto-dismissing
.overlay {
    if viewModel.showExportSuccess {
        Text("Collage saved to \(viewModel.lastExportPath.lastPathComponent)")
            .padding(8)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .transition(.opacity)
    }
}
```

- Integrate status feedback near the items it describes
- Sidebar status area for passive feedback (image count, processing status)
- Keep success messages brief and auto-dismissing
- Never block user workflow with informational alerts

## Caution Symbols

Use `exclamationmark.triangle` sparingly — only when extra attention is needed for unexpected data loss. Don't use for tasks whose purpose is to overwrite or remove data.
