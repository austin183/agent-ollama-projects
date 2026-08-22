# NavigationSplitView Column Collapse Limitations

**Date:** 2026-05-25
**Context:** Round 15.2 CR — right sidebar collapse fix

## Problem

We needed a right panel that could collapse and expand independently, matching the left sidebar behavior. The original layout used a 3-column `NavigationSplitView` with a conditional `if showDetail { detail }` inside the detail column. This hid the content but never collapsed the column itself — the empty drawer stayed open.

## What Didn't Work

### `columnVisibility` binding

The `NavigationSplitViewVisibility` enum offers:
- `.all` — sidebar + content + detail
- `.contentOnly` — content only (hides sidebar AND detail)
- `.detailOnly` — detail only
- `.firstTwoOnly` — sidebar + content

None of these give "sidebar + content" without the detail column while keeping the sidebar visible. `.firstTwoOnly` hides the detail but also collapses the sidebar into the content column. There's no "hide detail only, keep sidebar" option.

### `isCollapsed` binding

The 3-column initializer has no `isCollapsed` parameter. The 2-column initializer has `isDetailCollapsed` but that controls whether the sidebar collapses into the detail, not whether the detail itself is hidden.

### Nested `NavigationSplitView`

An inner `NavigationSplitView` inside the content column only has a 2-column `(sidebar:detail:)` initializer — no `isDetailCollapsed` binding available on that initializer either.

## What Worked

### 2-column `(sidebar:detail:)` with `HStack`

Switched to the 2-column initializer and put the editor + right panel inside an `HStack` in the detail column:

```swift
NavigationSplitView {
    sidebar          // left sidebar
} detail: {
    HStack(spacing: 0) {
        EditorView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        if !isCollapsed {
            RightPanel()
        }
    }
    .toolbar { /* toolbar buttons for the content area */ }
}
```

Key points:
- The editor's `.frame(maxWidth: .infinity)` causes it to expand and fill the space when the panel is hidden
- `HStack(spacing: 0)` prevents any gap between editor and panel
- The toolbar lives on the `HStack` wrapper so it applies to the combined area
- This is a 2-column split, so the sidebar collapse behavior is independent

## Takeaway

When you need custom control over which columns are visible in a `NavigationSplitView` layout, don't fight the 3-column API. Use a 2-column initializer and manage sub-layout within the detail column using standard SwiftUI containers (`HStack`, `Group`, etc.). The `columnVisibility` enum is designed for system-standard navigation patterns, not custom column visibility combinations.
