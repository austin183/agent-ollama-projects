# CollageMaker — UI Patterns Upgrade Plan

**Date:** 2026-05-11
**Source:** UI Patterns Review (`_agent_docs/reviews/ui-patterns-review.md`) + `swiftui-patterns` skill
**Status:** Ready to execute

---

## Scope

Full upgrade: @Observable migration, per-panel image assignment, commands/menus, toolbar, background support, @AppStorage preferences, dead code cleanup.

---

## Step 1: Models — Add Missing Types

**New file: `Models/BackgroundStyle.swift`**

```swift
enum BackgroundStyle: String, CaseIterable, Identifiable, Codable {
    case solid, gradient, image
    var id: String { rawValue }
}
```

---

## Step 2: @Observable Migration — CollageViewModel

**Modify: `ViewModel/CollageViewModel.swift`**

- `import Combine` → `import Observation`
- `@MainActor final class CollageViewModel: ObservableObject` → `@MainActor @Observable final class CollageViewModel`
- All `@Published var` → `var`
- Add `willSet { regenerateLayout() }` to `layoutStyle`, `heroIndex`, `gutter` so changes auto-trigger layout
- Add `willSet { updatePreview() }` to `backgroundColor`
- Remove `objectWillChange.send()` from `updatePreview()` — @Observable fires automatically
- Add new properties:
  - `var panelAssignments: [UUID: Int] = [:]` — panel UUID → image index
  - `var backgroundStyle: BackgroundStyle = .solid`
  - `var gradientStartColor: NSColor = .black`
  - `var gradientEndColor: NSColor = .darkGray`
  - `var gradientAngle: Double = 135`
  - `var backgroundImage: NSImage?`
  - `var backgroundOpacity: Double = 1.0`
- Add `func assignImage(_ imageIndex: Int, to panelId: UUID)` method
- Move `browseImages()` from `ContentView` into ViewModel so commands/toolbar can call it
- Add `func getEffectiveImageIndex(for panelId: UUID) -> Int?` that checks `panelAssignments` first, falls back to positional

---

## Step 3: @Observable Migration — App Entry + View Parameter Passing

Per skill: root uses `@State` with `@Observable` type, children receive explicit references.

**Modify: `CollageMakerApp.swift`**
- `@StateObject private var viewModel` → `@State private var viewModel`
- Remove `.environmentObject(viewModel)` from ContentView
- Pass explicitly: `ContentView(viewModel: viewModel)`
- Add `.commands { SidebarCommands() CollageCommands(viewModel: viewModel) }`

**Modify: `ContentView.swift`**
- `@EnvironmentObject var viewModel` → `let viewModel: CollageViewModel` stored property
- Add `init(viewModel:)` initializer
- Pass `viewModel` to `CollageEditorView(viewModel:)`, `PanelCropEditor(panel:viewModel:)`, `ExportPanel(viewModel:)`
- Remove `.onChange(of: viewModel.layoutStyle)` — willSet handles it
- Remove `.onChange(of: viewModel.heroIndex)` — willSet handles it
- Remove `.onReceive(viewModel.$gutter.dropFirst())` — willSet handles it
- Move `browseImages()` call to `viewModel.browseImages()`
- Move `handleDrop` logic into a shared helper or keep in sidebar (it's view-local)

**Modify: `CollageEditorView.swift`**
- `@EnvironmentObject var viewModel` → `let viewModel: CollageViewModel` + `init(viewModel:)`

**Modify: `PanelCropEditor.swift`**
- `@EnvironmentObject var viewModel` → `let viewModel: CollageViewModel` + `init(panel:viewModel:)`

**Modify: `ExportPanel.swift`**
- `@EnvironmentObject var viewModel` → `let viewModel: CollageViewModel` + `init(viewModel:)`
- Replace `.onReceive(viewModel.$backgroundColor.dropFirst())` with view-side `onChange(of:)` or rely on willSet in ViewModel

---

## Step 4: Per-Panel Image Assignment

**Modify: `PanelCropEditor.swift`** — Add image picker section:

```swift
Picker("Image", selection: $assignedIndex) {
    ForEach(viewModel.images.indices, id: \.self) { idx in
        HStack {
            Image(nsImage: viewModel.images[idx].nsImage)
                .resizable()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(viewModel.images[idx].filename).lineLimit(1)
        }
        .tag(idx)
    }
}
.pickerStyle(.wheel)
```

Computed binding that reads `viewModel.panelAssignments[panel.id] ?? panel.imageIndex` and writes via `viewModel.assignImage(_:to:)`.

**Modify: `CollageAssembler`** — Use `getEffectiveImageIndex` to resolve panel → image mapping instead of `panel.imageIndex` directly.

---

## Step 5: Toolbar

**Modify: `ContentView`** — Add to the `editor` column:

```swift
.toolbar {
    ToolbarItemGroup(placement: .primaryAction) {
        Button { Task { await viewModel.exportCollage() } } label: {
            Label("Export", systemImage: "arrowshape.down.circle.fill")
        }
        .disabled(viewModel.isProcessing || viewModel.images.isEmpty)

        Button { viewModel.browseImages() } label: {
            Image(systemName: "plus.circle.fill")
        }
        .help("Add Images")
    }
}
```

---

## Step 6: Commands + Menus

**New file: `Views/CollageCommands.swift`**

```swift
struct CollageCommands: Commands {
    let viewModel: CollageViewModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Images...") { viewModel.browseImages() }
                .keyboardShortcut("o")
            Button("Clear All") { viewModel.clearAll() }
        }
        CommandGroup(replacing: .saveItem) {
            Button("Export JPEG...") {
                Task { await viewModel.exportCollage() }
            }
            .keyboardShortcut("s")
        }
        CommandMenu("Layout") {
            ForEach(LayoutStyle.allCases) { style in
                Button(style.title) { viewModel.setLayoutStyle(style) }
            }
        }
    }
}
```

Added to `CollageMakerApp` via `.commands { SidebarCommands() CollageCommands(viewModel: viewModel) }`.

---

## Step 7: Background Support

**Modify: `Services/CollageAssembler.swift`** — Update `createBitmapContext` to accept `BackgroundStyle` + related params:
- `.solid`: existing behavior (fill with `backgroundColor`)
- `.gradient`: draw `CGGradient` using `gradientStartColor`, `gradientEndColor`, `gradientAngle`
- `.image`: draw `backgroundImage` at canvas size with `backgroundOpacity` alpha overlay

**Modify: `ExportPanel.swift`** — Replace simple color well with background editor:
- `Picker` / `SegmentedControl` for `BackgroundStyle` (solid/gradient/image)
- `.solid`: existing `NSColorWell`
- `.gradient`: two `NSColorWell`s + angle slider
- `.image`: "Choose Background" button + opacity slider

**Modify: `CollageViewModel`** — Update `updatePreview()` and `exportCollage()` to pass background params to assembler.

---

## Step 8: @AppStorage / UserDefaults Preferences

**Modify: `CollageViewModel`** — Use `UserDefaults` for persistent preferences in property getters/setters:

```swift
var layoutStyle: LayoutStyle {
    get { LayoutStyle(rawValue: UserDefaults.standard.string(forKey: "layoutStyle") ?? "hero") ?? .hero }
    set {
        UserDefaults.standard.set(newValue.rawValue, forKey: "layoutStyle")
        regenerateLayout()
    }
}

var gutter: CGFloat {
    get { CGFloat(UserDefaults.standard.double(forKey: "gutter")) }
    set {
        UserDefaults.standard.set(Double(newValue), forKey: "gutter")
        regenerateLayout()
    }
}

var exportQuality: Double {
    get { UserDefaults.standard.double(forKey: "exportQuality") }
    set { UserDefaults.standard.set(newValue, forKey: "exportQuality") }
}
```

For `NSColor`, use `NSColor`'s `usingColorSpace(_:)` + `NSBitmapImageRep` to serialize to `Data`, stored via `UserDefaults`.

---

## Step 9: Dead Code Cleanup

**Delete: `Views/ImagePickerView.swift`** — Dead code, never mounted.

---

## File Change Summary

| File | Action | Changes |
|------|--------|---------|
| `Models/BackgroundStyle.swift` | **New** | Background style enum |
| `ViewModel/CollageViewModel.swift` | Modify | @Observable, assignments, background, willSet, UserDefaults, browseImages() |
| `CollageMakerApp.swift` | Modify | @State, explicit param, .commands |
| `ContentView.swift` | Modify | Explicit param, .toolbar, pass viewModel down, remove onChange handlers |
| `Views/CollageEditorView.swift` | Modify | Explicit param |
| `Views/PanelCropEditor.swift` | Modify | Explicit param, image picker |
| `Views/ExportPanel.swift` | Modify | Explicit param, background editor, onChange fix |
| `Views/CollageCommands.swift` | **New** | Menu commands |
| `Services/CollageAssembler.swift` | Modify | Gradient/image background drawing |
| `Views/ImagePickerView.swift` | **Delete** | Dead code |

---

## Risks and Decisions

1. **`browseImages()` location**: Moving from `ContentView` to `CollageViewModel` makes it accessible from toolbar and commands. NSOpenPanel is AppKit, fine in ViewModel.

2. **`panelAssignments` persistence**: Session-specific only — not persisted to UserDefaults. Only layout preferences persist.

3. **`@Observable` + `willSet`**: Need to verify `willSet` fires correctly with `@Observable` macro. If not, use setter methods instead.

4. **Background image memory**: Storing one `NSImage` is fine. If this becomes a concern, store as `URL` + lazy load.

5. **`@Observable` view-side reactions**: No `$publisher` pattern. Use `willSet` in ViewModel for auto-updates, or `onChange(of:)` in views when view-side reaction is needed.

6. **Assembler API surface**: Adding background params to `assemble`/`assemblePreview`/`assembleWithCGImages`/`assemblePreviewWithCGImages` — all four methods need the new parameters.
