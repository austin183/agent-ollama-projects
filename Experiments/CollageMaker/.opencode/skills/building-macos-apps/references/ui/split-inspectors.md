# Split Views and Inspectors

When the app benefits from a stable sidebar-detail layout, optional supplementary content, or an inspector panel.

## Core Patterns

- Prefer explicit selection state over push-only navigation
- Start with `NavigationSplitView` when the layout matches the system mental model
- Use a manual split only when you need unusual sizing or always-visible custom columns
- Use `inspector(isPresented:)` for lightweight detail controls that complement main content

## Example: Sidebar + Detail

```swift
struct LibraryRootView: View {
  @State private var selection: Item.ID?
  @State private var showInspector = false

  var body: some View {
    NavigationSplitView {
      SidebarList(selection: $selection)
    } detail: {
      DetailView(selection: selection)
        .inspector(isPresented: $showInspector) {
          InspectorView(selection: selection)
        }
    }
  }
}
```

## Inline Search in Sidebar Form

`.searchable(text:prompt:)` places a search field at the top of the split view, **outside** the sidebar's `Form`. To embed search inside the sidebar:

```swift
Form {
    HStack {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("Search images", text: $searchQuery).font(.caption)
        if !searchQuery.isEmpty {
            Button { searchQuery = "" } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
    .padding(6)
    .background(Color.secondary.opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: 6))

    Section("Images") { /* ... */ }
}
```

## Pitfalls

- Avoid swapping the whole root layout with top-level conditionals when selection changes
- Avoid hiding too much detail behind modal sheets when an inspector or secondary column fits better
- If the layout requires AppKit split view delegation, use AppKit interop
- **3-column `NavigationSplitView` has no way to collapse only the detail column** — `columnVisibility` offers `.all`, `.contentOnly`, `.detailOnly`, `.firstTwoOnly` but none give "sidebar + content without detail". If you need independent right-panel toggle, use a 2-column `(sidebar:detail:)` initializer with an `HStack` inside the detail column containing the main view + conditional panel, with the main view using `.frame(maxWidth: .infinity)` to reclaim space when the panel is hidden
