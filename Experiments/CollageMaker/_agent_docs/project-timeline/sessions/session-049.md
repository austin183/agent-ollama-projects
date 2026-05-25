# Session 49 — 2026-05-25

### Round 15.2 CR: Right Sidebar Collapse Fix

**Goal:** Make the right sidebar collapse and expand properly, matching the left sidebar behavior. Previously, clicking the collapse icon only hid the contents while the drawer stayed open.

**Source:** Round 15.2 change request — clicking the sidebar.right toggle icon made the right panel contents disappear but the drawer remained open with empty space.

**Investigation:**

The original layout used a 3-column `NavigationSplitView` with sidebar, content (editor), and detail (right panel). The right panel visibility was controlled by a local `@State var showDetail` that conditionally rendered the content inside the detail column:

```swift
detail: {
    if showDetail {
        detail
    }
}
```

This only hid the content but never collapsed the column itself. The SDK's `NavigationSplitView` initializer requires all three columns and has no `isCollapsed` binding or visibility option for "sidebar + content only" — the `columnVisibility` enum only offers `.all`, `.contentOnly`, `.detailOnly`, and `.firstTwoOnly`, none of which map to "sidebar + content" without the detail.

**Changes Implemented:**

#### `ContentView.swift` — Switched to 2-column `NavigationSplitView`

Replaced the 3-column `NavigationSplitView` with a 2-column `(sidebar:detail:)` initializer. The editor and right panel now live together in an `HStack` inside the detail column:

```swift
NavigationSplitView {
    sidebar
} detail: {
    HStack(spacing: 0) {
        CollageEditorView(viewModel: viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        if !isDetailCollapsed {
            detail
        }
    }
    .toolbar { ... }
}
```

- `@State var showDetail` → `@State var isDetailCollapsed = false`
- Toggle button calls `isDetailCollapsed.toggle()`
- Sidebar image tap sets `isDetailCollapsed = false` to reopen the panel
- Removed unused `editor` computed property

When collapsed, the `HStack` only contains the editor with `.frame(maxWidth: .infinity)`, so the editor expands to fill the space previously occupied by the right panel.

**Build and Test Status:**
- **Build:** Succeeded — zero errors, zero warnings
- **Tests:** All unit tests passing

**Session Status:** Complete — right sidebar now collapses and expands properly, matching left sidebar behavior.
