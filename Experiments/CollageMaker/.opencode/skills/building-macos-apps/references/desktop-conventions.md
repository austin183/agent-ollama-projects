# Desktop Conventions

General rules, patterns, and anti-patterns for native macOS SwiftUI applications.

## General Rules

- Design for pointer, keyboard, menus, and multiple windows
- Keep scenes explicit: separate settings, utility windows, menu bar extras as their own scenes
- Prefer system desktop affordances: `commands`, toolbars, sidebars, inspectors, contextual menus, `searchable`
- Use system-adaptive colors and materials by default (`Color.primary`, `.regularMaterial`, etc.)
- Do not hardcode white/light backgrounds unless explicitly requested
- Do not paint `NavigationSplitView` sidebars with opaque custom fills
- Use `@SceneStorage` for per-window ephemeral state, `@AppStorage` for durable preferences
- `@SceneStorage` custom types must conform to `RawRepresentable` where `RawValue == String`
- Keep selection state explicit and stable
- Prefer `NavigationSplitView` over iOS-style stacked flows for desktop layouts

## File Structure

```
App/<AppName>App.swift       # @main entry and AppDelegate only
Views/ContentView.swift       # Root layout and high-level composition
Views/SidebarView.swift       # Feature views named by type
Views/DetailView.swift
Models/*.swift                # Value models, identifiers, selection enums
Stores/*.swift                # Persistence and state stores
Services/*.swift              # Network, process, platform clients
Support/*.swift               # Formatters, resolvers, extensions
```

Use a single Swift file only for tiny throwaway examples (~50 lines, one screen, no persistence).

## @SceneStorage with Custom Types

Persist per-window state (sidebar expansion, selection, tool choice) across app launches:

```swift
@SceneStorage("sidebarExpansion") var expansionState = ExpansionState()

struct ExpansionState: RawRepresentable {
    var yearSections: Set<String> = []

    init() {}
    init(rawValue: String) {
        let decoder = JSONDecoder()
        if let data = rawValue.data(using: .utf8),
           let decoded = try? decoder.decode(StoredState.self, from: data) {
            yearSections = decoded.yearSections
        }
    }

    var rawValue: String {
        let encoder = JSONEncoder()
        let data = try! encoder.encode(StoredState(yearSections: yearSections))
        return String(data: data, encoding: .utf8)!
    }

    private struct StoredState: Codable {
        var yearSections: Set<String>
    }

    subscript(_ key: String) -> Bool {
        get { yearSections.contains(key) }
        set {
            if newValue { yearSections.insert(key) }
            else { yearSections.remove(key) }
        }
    }
}
```

**Key points:**
- `RawValue` must be `String`
- Use JSON encoding for complex state (sets, dictionaries, nested structs)
- `@SceneStorage` is per-window; `@AppStorage` is global (UserDefaults)
- Default value is used when no stored value exists

## Font Family Picker

`NSFontManager.shared.availableFontFamilies` returns font family names (e.g., "Helvetica Neue"), not individual font names. These work directly with `NSFont(name:size:)`. Use a `Picker` inside a `Menu` to avoid the native `.pickerStyle(.menu)` height limit, which truncates long font lists.

```swift
private var fontFamilies: [String] {
    ["(System Default)"] + NSFontManager.shared.availableFontFamilies.sorted()
}

Menu {
    Picker("Font", selection: $selectedFamily) {
        ForEach(fontFamilies, id: \.self) { family in
            Text(family).tag(family)
        }
    }
} label: {
    HStack {
        Text(selectedFamily).lineLimit(1)
        Spacer()
        Image(systemName: "chevron.up.chevron.down")
    }
}
```

**Key points:**
- Empty string (`""`) fallback to `NSFont.boldSystemFont(ofSize:)` covers the "System Default" case
- `NSFont(name: selectedFamily, size: fontSize)` returns `nil` for empty string — always guard
- The `Menu` wrapper allows the `Picker` to scroll through all families without truncation

## TextEditor Styling

`TextEditor` is the macOS 12+ multiline text input. `TextArea` requires macOS 26+ and is unavailable on lower deployment targets.

**Styling differences from TextField:**
- `TextEditor` does NOT support `.textFieldStyle()`
- `.border(NSColor, width:)` has type inference issues — `NSColor` technically conforms to `ShapeStyle` but the compiler may not infer it in context
- Use `.background()` + `.overlay(RoundedRectangle.stroke())` for borders:

```swift
TextEditor(text: $text)
    .padding(4)
    .background(Color.secondary.opacity(0.1))
    .overlay(
        RoundedRectangle(cornerRadius: 6)
            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
    )
```

## Sidebar Row Pattern

```swift
List(selection: $selection) {
  ForEach(items) { item in
    HStack(spacing: 10) {
      Image(systemName: item.systemImage)
        .foregroundStyle(.secondary)
        .frame(width: 16)
      VStack(alignment: .leading, spacing: 2) {
        Text(item.title).lineLimit(1)
        if let detail = item.detail {
          Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
      }
    }
    .tag(item.id)
  }
}
.listStyle(.sidebar)
```

Keep each row to one icon max, one or two text lines max. Move richer metadata to detail/inspector panes.

## Workflow for New Scene or View

1. Define scene type and ownership model before writing child views
2. Decide which actions live in content, toolbars, commands, inspectors, or settings
3. Sketch selection model and layout
4. Create file/folder structure
5. Build with small, focused subviews and explicit inputs
6. Add keyboard shortcuts and menu/toolbar exposure
7. Validate: multiwindow assumptions, settings entry points, selection stability

## Refactoring Existing Views

When cleaning up an oversized or disorganized view file:

1. Identify the current scene boundary and whether the file is doing too much
2. Reorder the file into a predictable top-to-bottom structure
3. Extract desktop-specific sections into dedicated subview types
4. Stabilize root layout around selection, scenes, and commands rather than top-level branching
5. Move action logic, command routing, and toolbar behavior into named helpers
6. Tighten any AppKit bridge so the imperative edge is small and explicit
7. Keep behavior intact unless the request explicitly asks for structural and behavioral changes

### File Ordering

Within a single view file, follow this order unless a stronger local convention exists:

1. Environment imports
2. `private`/`public` `let` constants
3. `@State` / other stored properties
4. Computed `var` (non-view)
5. `init`
6. `body`
7. Computed view builders / view helpers
8. Helper / async functions

### Prefer Dedicated Subview Types

- Extract sidebar rows, detail panels, inspectors, toolbar content into focused subviews
- Keep computed `some View` helpers small and rare
- Pass explicit data, bindings, and actions into subviews instead of the whole scene model

### Extract Commands, Toolbars, and Actions from Body

- Do not bury non-trivial button logic inline
- Do not mix command routing, menu state, and layout in the same block
- Keep `body` readable as UI, not as a desktop view controller

### Keep AppKit Escape Hatches Narrow

- If a representable or `NSWindow` bridge exists, isolate it behind a small wrapper
- Do not let AppKit references spread through unrelated SwiftUI views
- If the bridge starts owning the feature, re-evaluate the architecture

### Refactor Checklist

- [ ] Split oversized view files before adding more UI
- [ ] Move pure models, identifiers, and selection enums out of view files
- [ ] Move `Process`, `URLSession`, platform client code out of views into `Services/`
- [ ] Keep `AppDelegate` and `@main` entrypoint minimal
- [ ] Build after each major split so compile errors stay local

## Anti-Patterns

- One huge `ContentView` pretending the whole app is a single screen
- Single Swift file with app, views, models, stores, services, and extensions
- Touch-first interaction models ported from iOS without desktop affordances
- Hiding core actions behind gestures with no menu, toolbar, or keyboard path
- Using only `Window(...)` for main launch window in menu-bar-plus-window apps
- Rendering full unbounded text in menu bar extra items (cap at 30 chars)
- Treating settings as a navigation destination in the main window
- Hardcoding `.background(.white)` in new scaffolds
- Wrapping sidebar items in large rounded cards (fights native source-list density)
- Using push navigation for layouts wanting stable sidebar selection and detail panes
- Root view mixing window scaffolding, settings, toolbar code, command handling, and detail layout
- iOS-style push navigation forced into a Mac sidebar-detail problem
- Several booleans for mutually exclusive inspectors, sheets, or utility windows
- AppKit objects passed through many SwiftUI layers without clear ownership
- Large computed view fragments standing in for real subviews
- Binding `Picker` directly to `@Published` when side effects are needed — the binding bypasses action methods. Use `.onChange` or local `@State` to trigger side effects
