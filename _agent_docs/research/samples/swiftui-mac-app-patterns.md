# SwiftUI macOS App Patterns — Apple Sample Code Research

**Source:** Apple sample code "Building a great Mac app with SwiftUI"
**Doc page:** https://developer.apple.com/documentation/SwiftUI/building-a-great-mac-app-with-swiftui
**Associated WWDC sessions:** [10062: SwiftUI on the Mac: Build the Fundamentals](https://developer.apple.com/wwdc21/10062/), [10289: SwiftUI on the Mac: The Finishing Touches](https://developer.apple.com/wwdc21/10289/)
**Availability:** macOS 12.0+, Xcode 13.0+

---

## Summary

This Apple sample code project demonstrates how to build a full-featured macOS app ("GardenApp") using SwiftUI. It covers the complete set of macOS-specific UI patterns: sidebar/detail NavigationView, menu bar commands with custom command groups, toolbar items, Settings window, Table and gallery views, drag-and-drop, file import/export, keyboard shortcuts, and focused value communication between views and menu commands. The sample is organized in two sessions: Session 1 builds the fundamentals (sidebar, table, basic commands), and Session 2 adds finishing touches (toolbar, Settings, drag-and-drop, import/export, gallery view).

---

## Key macOS SwiftUI Patterns

### 1. App Structure and Scene Declaration

The `@main` struct declares scenes at the top level, not views:

```swift
@main
struct GardenApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .commands {
            SidebarCommands()
            PlantCommands()
            ImportExportCommands(store: store)
            ImportFromDevicesCommands()
        }
        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
```

**Key patterns:**
- `body` returns `some Scene`, not `some View`
- `WindowGroup` wraps the main content view
- `.commands` modifier attaches to `WindowGroup` to add menu bar commands
- `Settings {}` declares a native macOS Settings window (replaces `.preferences` from earlier macOS versions)
- `@StateObject` for the app-level data store, injected via `.environmentObject`

### 2. Sidebar + Detail NavigationView

Uses the classic macOS two-pane `NavigationView`:

```swift
struct ContentView: View {
    @EnvironmentObject var store: Store
    @SceneStorage("selection") private var selectedGardenID: Garden.ID?
    @AppStorage("defaultGarden") private var defaultGardenID: Garden.ID?

    var body: some View {
        NavigationView {
            Sidebar(selection: selection)
            GardenDetail(garden: selectedGarden)
        }
    }

    private var selection: Binding<Garden.ID?> {
        Binding(get: { selectedGardenID ?? defaultGardenID }, set: { selectedGardenID = $0 })
    }

    private var selectedGarden: Binding<Garden> {
        $store[selection.wrappedValue]
    }
}
```

**Key patterns:**
- `@SceneStorage` persists selection and UI state across app launches, per-window
- `@AppStorage` persists user preferences globally (e.g., default garden)
- Computed `Binding` wraps `selectedGardenID ?? defaultGardenID` for fallback behavior
- `Binding<Garden>` derived from store subscript provides two-way binding to detail view

### 3. Sidebar Implementation

```swift
struct Sidebar: View {
    @EnvironmentObject var store: Store
    @SceneStorage("expansionState") var expansionState = ExpansionState()
    @Binding var selection: Garden.ID?

    var body: some View {
        List(selection: $selection) {
            DisclosureGroup(isExpanded: $expansionState[store.currentYear]) {
                ForEach(store.gardens(in: store.currentYear)) { garden in
                    SidebarLabel(garden: garden)
                        .badge(garden.numberOfPlantsNeedingWater)
                }
            } label: {
                Label("Current", systemImage: "chart.bar.doc.horizontal")
            }

            Section("History") {
                GardenHistoryOutline(range: store.previousYears, expansionState: $expansionState)
            }
        }
        .frame(minWidth: 250)
    }
}
```

**Key patterns:**
- `List(selection: $selection)` drives selection binding
- `DisclosureGroup` for collapsible sections
- `.badge()` modifier for notification-style count badges
- `Section` for grouping
- `.frame(minWidth:)` controls sidebar minimum width
- `@SceneStorage` with `RawRepresentable` type (`ExpansionState`) persists disclosure state

### 4. Menu Bar Commands

Commands are defined as separate `Commands` conformance types, composed in `.commands`:

```swift
struct PlantCommands: Commands {
    @FocusedBinding(\.garden) private var garden: Garden?
    @FocusedBinding(\.selection) private var selection: Set<Plant.ID>?

    var body: some Commands {
        CommandGroup(before: .newItem) {
            AddPlantButton(garden: $garden)
        }

        CommandMenu("Plants") {
            WaterPlantsButton(garden: $garden, plants: $selection)
        }
    }
}
```

**Key patterns:**
- `Commands` protocol for modular command definitions
- `CommandGroup(before: .newItem)` inserts before the system "New" command
- `CommandGroup(replacing: .importExport)` replaces the system Import/Export menu
- `CommandMenu("Name")` creates a custom menu in the menu bar
- `@FocusedBinding` reads values published via `focusedSceneValue` from the detail view
- Commands receive `optional` bindings — they must handle `nil` (no selection)

### 5. Focused Values (Cross-View Communication)

Custom `FocusedValues` keys communicate state from the detail view up to menu commands:

```swift
extension FocusedValues {
    var garden: Binding<Garden>? {
        get { self[FocusedGardenKey.self] }
        set { self[FocusedGardenKey.self] = newValue }
    }

    var selection: Binding<Set<Plant.ID>>? {
        get { self[FocusedGardenSelectionKey.self] }
        set { self[FocusedGardenSelectionKey.self] = newValue }
    }

    private struct FocusedGardenKey: FocusedValueKey {
        typealias Value = Binding<Garden>
    }

    private struct FocusedGardenSelectionKey: FocusedValueKey {
        typealias Value = Binding<Set<Plant.ID>>
    }
}
```

Published from the detail view:
```swift
.focusedSceneValue(\.garden, $garden)
.focusedSceneValue(\.selection, $selection)
```

**Key patterns:**
- Define `FocusedValueKey` struct with `typealias Value`
- Extend `FocusedValues` with subscript access
- Use `.focusedSceneValue(keyPath, value)` to publish from any view
- Use `@FocusedBinding(\.key)` in Commands to receive the value
- Scope is the scene/window, not the view hierarchy

### 6. Toolbar Items

```swift
.toolbar {
    DisplayModePicker(mode: $mode)
    Button(action: addPlant) {
        Label("Add Plant", systemImage: "plus")
    }
}
```

**Key patterns:**
- `.toolbar {}` closure adds items to the window toolbar
- Standard SwiftUI views (`Picker`, `Button`, etc.) work inside `.toolbar`
- Combined with `.navigationTitle` and `.navigationSubtitle` for the full title bar

### 7. Keyboard Shortcuts

```swift
Button { /* action */ } label: {
    Label("Add Plant", systemImage: "plus")
}
.keyboardShortcut("N", modifiers: [.command, .shift])
.disabled(garden == nil)
```

**Key patterns:**
- `.keyboardShortcut(_:modifiers:)` modifier on `Button`
- Works both in toolbar and in menu commands
- `.disabled()` conditionally enables/disables the shortcut

### 8. Settings Window

```swift
Settings {
    SettingsView()
        .environmentObject(store)
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            ViewingSettings()
                .tabItem {
                    Label("Viewing", systemImage: "eyeglasses")
                }
        }
        .frame(width: 400, height: 200, alignment: .top)
    }
}
```

**Key patterns:**
- `Settings {}` scene in `@main` struct
- `TabView` with `.tabItem` for multiple preference panes
- `.frame(width:height:alignment:)` controls window size
- `@AppStorage` for persisting preference values

### 9. Table View with Selection and Sorting

```swift
Table(selection: $selection, sortOrder: $sortOrder) {
    TableColumn("Variety", value: \.variety)
    TableColumn("Days to Maturity", value: \.daysToMaturity) { plant in
        Text(plant.daysToMaturity.formatted())
    }
    TableColumn("Favorite", value: \.favorite, comparator: BoolComparator()) { plant in
        Toggle("Favorite", isOn: $garden[plant.id].favorite)
            .labelsHidden()
    }
    .width(50)
} rows: {
    ForEach(plants) { plant in
        TableRow(plant)
            .itemProvider { plant.itemProvider }
    }
    .onInsert(of: [Plant.draggableType]) { index, providers in
        // handle drop
    }
}
```

**Key patterns:**
- `Table(selection:sortOrder:columns:rows:)` for selection + sorting
- `TableColumn` with custom closure for cell rendering
- `Toggle` inline in table cells with `.labelsHidden()`
- `.width()` on column for fixed-width columns
- Custom `SortComparator` for non-standard types (e.g., `Bool`)
- `.itemProvider {}` enables drag from table rows
- `.onInsert(of:)` handles drop insertion

### 10. Search

```swift
.searchable(text: $searchText)
```

Applied to the detail view, provides native macOS search field in the toolbar area.

### 11. Drag and Drop

**Exporting (drag from table):**
```swift
TableRow(plant)
    .itemProvider { plant.itemProvider }
```

**Importing (drop into table):**
```swift
.onInsert(of: [Plant.draggableType]) { index, providers in
    Plant.fromItemProviders(providers) { plants in
        garden.plants.insert(contentsOf: plants, at: index)
    }
}
```

**Image import via drag onto selection:**
```swift
.importsItemProviders(selection.isEmpty ? [] : Plant.importImageTypes) { providers in
    Plant.importImageFromProviders(providers) { url in
        for plantID in selection {
            garden[plantID].imageURL = url
        }
    }
}
```

**Key patterns:**
- Custom UTType declared in Info.plist (`UTExportedTypeDeclarations`)
- `NSItemProvider` for drag data representation
- `.itemProvider {}` closure for export
- `.onInsert(of:)` for drop handling
- `.importsItemProviders(_:types:) {}` for importing external content (images from Finder, Photos, etc.)
- Conditional enablement: pass empty array when no selection to disable import

### 12. File Export

```swift
Button("Export…") {
    isShowingExportDialog = true
}
.fileExporter(
    isPresented: $isShowingExportDialog, document: store,
    contentType: Store.readableContentTypes.first!) { result in
}
```

**Key patterns:**
- `.fileExporter` modifier presents native save dialog
- Store conforms to `ReferenceFileDocument` for export
- `CommandGroup(replacing: .importExport)` places in File menu

### 13. Gallery View with Safe Area Insets

```swift
.safeAreaInset(edge: .bottom, spacing: 0) {
    ItemSizeSlider(size: $itemSize)
}
```

**Key patterns:**
- `.safeAreaInset(edge:)` for bottom toolbar-like controls
- `LazyVGrid` with adaptive `GridItem` for responsive gallery
- `.controlSize(.small)` for compact slider

---

## Code Patterns and Modifiers Summary

| Modifier/Pattern | Purpose | Where Used |
|---|---|---|
| `.commands {}` | Menu bar commands | `WindowGroup` in `@main` |
| `SidebarCommands()` | System sidebar toggle commands | `.commands {}` |
| `CommandGroup(before:)` | Insert before system command | Custom `Commands` |
| `CommandGroup(replacing:)` | Replace system command group | Custom `Commands` |
| `CommandMenu("Name")` | Custom menu bar menu | Custom `Commands` |
| `.toolbar {}` | Window toolbar items | Detail view |
| `.navigationTitle(_:)` | Window title | Detail view |
| `.navigationSubtitle(_:)` | Window subtitle | Detail view |
| `.searchable(text:)` | Search field | Detail view |
| `.keyboardShortcut(_:modifiers:)` | Keyboard shortcut | Buttons |
| `.focusedSceneValue(_:_:)` | Publish to focused values | Detail view |
| `@FocusedBinding(\._)` | Read focused values | Commands |
| `.badge(_:)` | Notification badge | Sidebar items |
| `.frame(minWidth:)` | Sidebar width | Sidebar |
| `Settings {}` | Settings window | `@main` |
| `@SceneStorage(_:)` | Per-window persisted state | ContentView, Sidebar |
| `@AppStorage(_:)` | Global persisted preference | ContentView, Settings |
| `.fileExporter` | File save dialog | Import/Export commands |
| `.itemProvider {}` | Drag export | Table rows |
| `.onInsert(of:)` | Drop import | Table rows |
| `.importsItemProviders` | External content import | Detail view |
| `.safeAreaInset(edge:)` | Bottom/top insets | Gallery view |
| `.disabled(_:)` | Conditional enablement | Buttons |
| `.labelsHidden()` | Hide toggle labels | Table cells |

---

## Applicability to CollageMaker

### What to Adopt Directly

1. **`.commands {}` on `WindowGroup`** — CollageMaker currently lacks menu bar commands. Add a `.commands` block to the `WindowGroup` in `CollageMakerApp` with at minimum `SidebarCommands()` and custom command groups for collage operations.

2. **`CommandGroup(before:)` and `CommandMenu("Name")`** — Create a "Collage" menu with actions like New Layout, Add Image, Export, etc.

3. **`.toolbar {}` pattern** — The sample shows toolbar items for display mode switching and add buttons. CollageMaker should add toolbar items for layout switching, undo/redo, and image operations.

4. **`@SceneStorage` for selection/state** — Use `@SceneStorage` to persist sidebar selection, tool selection, and panel expansion state across launches.

5. **`@FocusedBinding` + `FocusedValues`** — For communicating selected images or templates from the canvas view up to menu commands, enabling keyboard shortcuts that act on selections.

6. **`Settings {}` scene** — Add a Settings window for CollageMaker preferences (default export format, default dimensions, etc.).

7. **`.keyboardShortcut` on buttons** — Add shortcuts for common operations (Cmd+N for new collage, Cmd+S for save, etc.).

8. **Drag and drop** — `.importsItemProviders` for dragging images from Finder onto the canvas. `.itemProvider` + `.onInsert` for reordering within the collage.

9. **`.fileExporter`** — For exporting the final collage as an image file.

10. **`.searchable`** — If CollageMaker has a template or image library, add search.

### Mapping to CollageMaker's Missing Patterns

| CollageMaker Gap | Sample Pattern Solution |
|---|---|
| No `.commands` modifier | Add `.commands { SidebarCommands() CollageCommands() }` to `WindowGroup` |
| No `.toolbar` items | Add `.toolbar { LayoutPicker() AddImageButton() }` to canvas view |
| No keyboard shortcuts | Add `.keyboardShortcut` to command buttons |
| No Settings window | Add `Settings { SettingsView() }` scene |
| No menu-driven actions | Create `CommandMenu("Collage")` with layout/export actions |
| Selection not communicated to menus | Define custom `FocusedValues` keys + `@FocusedBinding` |
| No drag-and-drop from Finder | Add `.importsItemProviders` with image UTTypes |
| No file export dialog | Use `.fileExporter` with a document conforming to `ReferenceFileDocument` |

### Gotchas and macOS-Specific Considerations

1. **`@SceneStorage` vs `@AppStorage`**: `@SceneStorage` is per-window (each `WindowGroup` instance gets its own storage). `@AppStorage` is global (shared across all windows via UserDefaults). Use `@SceneStorage` for window-specific state (selection, sidebar expansion) and `@AppStorage` for user preferences (default export format).

2. **`NavigationView` column titles**: On macOS, `NavigationView` with two views automatically creates the sidebar/detail split. The `.navigationTitle` on the detail view sets the window title.

3. **`SidebarCommands()` is required**: Without `SidebarCommands()`, the system won't provide the "Toggle Sidebar" command (Cmd+Option+0). Always include it when using a sidebar.

4. **`FocusedValues` scope**: Focused values are scoped to the focused scene. If you have multiple windows, each window's commands will receive that window's focused values.

5. **Commands receive optional bindings**: `@FocusedBinding` properties are always optional. Command buttons must handle the `nil` case with `.disabled()`.

6. **`Settings` vs `.preferences`**: Use `Settings {}` scene (macOS 13+). The older `.preferences {}` modifier is deprecated.

7. **UTType declarations for drag-and-drop**: Custom drag types require `UTExportedTypeDeclarations` in Info.plist. For importing system types (images), use `UTType.image` or `NSImage.imageTypes`.

8. **`.fileExporter` requires `ReferenceFileDocument`**: The document parameter must conform to `ReferenceFileDocument` (for export) or `FileDocument` (for open/save). The sample shows `ReferenceFileDocument` for one-way export.

9. **`@StateObject` in `@main`**: The app-level store should be `@StateObject` in the `@main` struct, injected via `.environmentObject` to the root view.

10. **`RawRepresentable` for `@SceneStorage` custom types**: To persist custom types with `@SceneStorage`, the type must conform to `RawRepresentable` where `RawValue` is `String`. The sample's `ExpansionState` demonstrates this pattern.
