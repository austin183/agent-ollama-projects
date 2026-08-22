# HIG Review — Phased Implementation Plan

**Date:** 2026-05-19
**Review:** `hig-review.md` (614 lines, 13 findings)
**Decisions:** All priorities (P0–P3), keep Cmd+S, Settings includes default title/font/background/export folder

---

## Phase 1 — Undo & Redo Foundation

**Goal:** Users can undo/redo all destructive and reversible actions via Edit menu + Cmd+Z.

**Files changed:** 1 (`CollageViewModel.swift`)

### Changes

**Add to `CollageViewModel`:**
- `private let undoManager = NSUndoManager()`
- `var isExporting: Bool = false`
- `var exportSuccessMessage: String?`
- `extension URL { var folderExists: Bool }`

**Undo registration (register BEFORE mutation, capture old value):**

```swift
// In layoutStyle didSet:
undoManager.registerUndo(withTarget: self) { target in
    target.layoutStyle = oldValue
}
undoManager.setActionName("Change Layout")

// In titleAttrString didSet:
undoManager.registerUndo(withTarget: self) { target in
    target.titleAttrString = oldValue
}
undoManager.setActionName("Edit Title")

// In titleStyle didSet:
undoManager.registerUndo(withTarget: self) { target in
    target.titleStyle = oldValue
}
undoManager.setActionName("Change Title Style")

// Same pattern for: backgroundColor, gutter, exportQuality,
// backgroundStyle, gradientStartColor, gradientEndColor, gradientAngle, backgroundOpacity
```

**Method changes:**

```swift
func removeImage(at index: Int) {
    guard index < images.count else { return }
    let removed = images[index]
    undoManager.registerUndo(withTarget: self) { target in
        target.images.insert(removed, at: index)
        target.regenerateLayout()
    }
    undoManager.setActionName("Remove Image")
    images.remove(at: index)
    regenerateLayout()
    Task { [weak self] in await self?.analyzeSaliency() }
}

func moveImages(from: IndexSet, to: Int) {
    let oldImages = images.map { $0.id }
    // Capture old order before move
    // Register undo to restore old order
    undoManager.setActionName("Reorder Images")
    // ... existing move logic ...
}

func swapPanelImages(sourceId: UUID, targetId: UUID) {
    let oldOrder = customImageOrder
    undoManager.registerUndo(withTarget: self) { target in
        target.customImageOrder = oldOrder
        target.regenerateLayout()
    }
    undoManager.setActionName("Swap Images")
    // ... existing swap logic ...
}

func resetCrop(panelId: UUID) {
    guard let oldCrop = cropMap[panelId] else { return }
    undoManager.registerUndo(withTarget: self) { target in
        target.cropMap[panelId] = oldCrop
        target.cropManager.cropMap = target.cropMap
        target.updatePreview()
    }
    undoManager.setActionName("Reset Crop")
    // ... existing reset logic ...
}

func clearAll() {
    guard !images.isEmpty else { return }
    let oldImages = images, oldPanels = panels, oldCropMap = cropMap, oldCustomOrder = customImageOrder
    undoManager.registerUndo(withTarget: self) { target in
        target.images = oldImages
        target.panels = oldPanels
        target.cropMap = oldCropMap
        target.customImageOrder = oldCustomOrder
        target.regenerateLayout()
    }
    undoManager.setActionName("Clear All")
    // ... existing clear logic ...
}
```

**Export changes:**

```swift
func exportCollage() async -> URL? {
    // ... existing setup ...
    isProcessing = true
    isExporting = true
    exportSuccessMessage = nil
    defer { isProcessing = false; isExporting = false }

    let savePanel = NSSavePanel()
    savePanel.allowedContentTypes = [.jpeg]
    savePanel.nameFieldStringValue = "collage.jpg"

    // Use default export folder if set
    if let folderPath = UserDefaults.standard.string(forKey: "defaultExportFolder"),
       let url = URL(string: folderPath), url.folderExists {
        savePanel.directoryURL = url
        savePanel.isEntireDirectoryVisible = true
    }

    let response = NSApplication.shared.runModal(for: savePanel)
    guard response == .OK, let url = savePanel.url else { return nil }

    // Save default export folder after successful save
    UserDefaults.standard.set(url.deletingLastPathComponent().path, forKey: "defaultExportFolder")

    // ... existing assembly ...

    do {
        try await exportTask?.value
        exportSuccessMessage = "Saved to \(url.lastPathComponent)"
        return url
    } catch { /* ... */ }
}
```

### Test between phases

1. Build succeeds
2. Cmd+Z undoes: remove image, reorder, swap panels, reset crop, clear all, change layout, change title, change background
3. Cmd+Shift+Z redoes all above actions in reverse
4. Edit menu shows descriptive action names ("Undo Remove Image", "Undo Change Layout", etc.)
5. Export saves to last-used folder on subsequent launches

---

## Phase 2 — Settings Window & Commands

**Goal:** Native macOS Settings scene accessible via Cmd+, + keyboard shortcuts refined.

**Files changed:** 3 (`SettingsView.swift` new, `CollageMakerApp.swift`, `CollageCommands.swift`)

### SettingsView.swift (NEW)

Four-tab `TabView` with `scenePadding()`, `frame(minWidth: 420, minHeight: 280)`:

**General tab** — `@AppStorage`:
- Default Layout: `layoutStyle` (popup: Uniform/Hero/Mosaic)
- Default Gutter: `gutter` slider 0–20pt
- Default Quality: `exportQuality` slider 50%–100%

**Appearance tab** — `@State + UserDefaults` for NSColor:
- Background Style: `backgroundStyle` segmented (Solid/Gradient)
- Solid mode: color picker for `backgroundColor`
- Gradient mode: color pickers for `gradientStartColor`, `gradientEndColor` + angle slider `gradientAngle`
- Uses `UserDefaultsColorView` (NSColorWell wrapper with archiving)

**Text tab** — `@AppStorage`:
- Default Title: `defaultTitle` text field (NEW key)
- Font Family: `defaultFontFamily` text field (NEW key, empty = system)
- Font Size: `defaultFontSize` slider 12–120pt (NEW key)

**Export tab** — `@AppStorage`:
- Default Folder: `defaultExportFolder` string + "Choose Folder" button (NEW key)
- Quality: `exportQuality` slider (reuses General, shown for convenience)

### NSColorWell wrapper for Settings

```swift
struct UserDefaultsColorView: View {
    @Binding var color: NSColor
    let key: String
    let defaultValue: NSColor
    @Binding var loaded: Bool

    func makeNSView(context: Context) -> NSColorWell {
        // Standard NSColorWell with coordinator pattern
    }
    func updateNSView(_ well: NSColorWell, context: Context) {
        // Sync binding -> NSColorWell
    }
    // Coordinator loads on appear, saves on change
}
```

### CollageCommands.swift changes

```swift
struct CollageCommands: Commands {
    let viewModel: CollageViewModel
    @Binding var showingClearAlert: Bool

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Images…") { viewModel.browseImages() }
                .keyboardShortcut("o", modifiers: .command)  // explicit modifier
            Button("Clear All") { showingClearAlert = true }
        }

        CommandGroup(replacing: .saveItem) {
            Button("Export JPEG…") { Task { await viewModel.exportCollage() } }
                .keyboardShortcut("s", modifiers: .command)  // explicit modifier
        }

        CommandMenu("Layout") {
            Button("Uniform") { viewModel.layoutStyle = .uniform }
                .keyboardShortcut("1", modifiers: .command)
            Button("Hero") { viewModel.layoutStyle = .hero }
                .keyboardShortcut("2", modifiers: .command)
            Button("Mosaic") { viewModel.layoutStyle = .mosaic }
                .keyboardShortcut("3", modifiers: .command)
        }
    }
}
```

### CollageMakerApp.swift changes

```swift
@main
struct CollageMakerApp: App {
    @State private var viewModel = CollageViewModel()
    @State private var showingClearAlert = false

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .environment(\.showingClearAlert, $showingClearAlert)
        }
        .defaultSize(width: 1200, height: 750)
        .commands {
            SidebarCommands()
            CollageCommands(viewModel: viewModel, showingClearAlert: $showingClearAlert)
        }

        Settings {
            SettingsView()
        }
    }
}

// Environment key for clear alert binding
private struct ShowingClearAlertKey: EnvironmentKey {
    static var defaultValue: Binding<Bool> = .constant(false)
}
extension EnvironmentValues {
    var showingClearAlert: Binding<Bool> {
        get { self[ShowingClearAlertKey.self] }
        set { self[ShowingClearAlertKey.self] = newValue }
    }
}
```

### Test between phases

1. Build succeeds
2. Cmd+, opens Settings window
3. Cmd+O opens file picker (explicit modifier works)
4. Cmd+S opens export save dialog
5. Cmd+1/2/3 switches between Uniform/Hero/Mosaic layouts
6. Settings General tab: layout, gutter, quality change correctly
7. Settings Appearance tab: color pickers load saved colors, save on change
8. Settings Text tab: default title, font family, font size persist
9. Settings Export tab: folder picker saves path, quality slider works
10. Cmd+Z still works for undo (Phase 1 changes intact)

---

## Phase 3 — Context Menus & Alerts

**Goal:** Standard macOS right-click menus on panels/sidebar + confirmation for destructive actions.

**Files changed:** 3 (`CollageCommands.swift`, `ContentView.swift`, `CollageEditorView.swift`)

### CollageCommands.swift

`clearAll()` button now triggers `showingClearAlert = true` (already covered in Phase 2).

### ContentView.swift — Sidebar context menu + Clear All alert

**Sidebar image rows — add `.contextMenu`:**

```swift
ForEach(filteredImages, id: \.item.id) { index, item in
    HStack { ... }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Remove", role: .destructive) {
                viewModel.removeImage(at: index)
            }
        }
}
```

**Clear All alert — add to ContentView body:**

```swift
@Environment(\.showingClearAlert) private var showingClearAlert

// In body:
.alert("Clear All Images?", isPresented: showingClearAlert) {
    Button("Clear All", role: .destructive) {
        viewModel.clearAll()
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("This will remove all images from the collage. Use Undo to reverse.")
}
```

### CollageEditorView.swift — Panel context menus

**ForEach panels — add context menu + imageIndex:**

```swift
ForEach(viewModel.panels) { panel in
    if let scaledFrame = scaledPanelFrames[panel.id] {
        let imageIndex = viewModel.getEffectiveImageIndex(for: panel.id)
        PanelHitArea(panel: panel, frame: scaledFrame, viewModel: viewModel, imageIndex: imageIndex)
            .contextMenu {
                Button("Reset Crop") {
                    viewModel.resetCrop(panelId: panel.id)
                }
                Divider()
                if let idx = imageIndex {
                    Button("Remove Image", role: .destructive) {
                        viewModel.removeImage(at: idx)
                    }
                }
            }
    }
}
```

**Update `PanelHitArea` struct** — add `let imageIndex: Int?` parameter (not used in body, just passed through for context menu).

### Test between phases

1. Build succeeds
2. Right-click on canvas panel → "Reset Crop" / "Remove Image"
3. Right-click on sidebar image row → "Remove"
4. Menu bar "Clear All" → confirmation alert appears
5. Alert "Clear All" button → removes all images
6. Alert "Cancel" button → dismisses without action
7. Escape dismisses the alert
8. Undo still works (Phase 1 changes intact)

---

## Phase 4 — Accessibility, Progress & Polish

**Goal:** VoiceOver support, refined progress labels, export feedback, reduce motion, sidebar glass effect.

**Files changed:** 6 (`ContentView.swift`, `CollageEditorView.swift`, `ExportPanel.swift`, `PanelCropEditor.swift`, `CollageCommands.swift`)

### ContentView.swift — Accessibility + progress + polish

**Progress label — more specific:**

```swift
Text(viewModel.isExporting
    ? "Exporting collage..."
    : "Analyzing \(viewModel.images.count) image(s)...")
```

**Warning triangle → info circle:**

```swift
Label(
    "Only \(viewModel.panels.count) of \(viewModel.images.count) images are in the layout",
    systemImage: "info.circle"
)
.foregroundStyle(.secondary)  // not yellow
```

**Sidebar background extension:**

```swift
.formStyle(.grouped)
.backgroundExtensionEffect(.sidebar)
```

**Accessibility — sidebar:**

```swift
// Search field
TextField("Search images", text: $searchQuery)
    .accessibilityLabel("Search images")

// Add Images button
Button { ... } label: { Label("Add Images", systemImage: "plus.circle.fill") }
    .accessibilityLabel("Add Images")
    .accessibilityHint("Opens file picker")

// Layout picker
Picker("Style", selection: $viewModel.layoutStyle) { ... }
    .accessibilityLabel("Layout style")
    .accessibilityValue(viewModel.layoutStyle.title)

// Gutter slider
Slider(value: $viewModel.gutter, in: 0...20, step: 1)
    .accessibilityLabel("Gutter width")
    .accessibilityValue("\(Int(viewModel.gutter)) points")

// Status text
if viewModel.isProcessing {
    ProgressView().frame(width: 16, height: 16).accessibilityHidden(true)
    Text(...).accessibilityLabel("Processing status")
} else {
    Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .accessibilityLabel("Ready")
    Text("Ready").accessibilityHidden(true)
}

// Toolbar buttons
Button { ... } label: { Label("Export", systemImage: "arrowshape.down.circle.fill") }
    .accessibilityLabel("Export collage as JPEG")
    .accessibilityHint("Opens save dialog")

Button { ... } label: { Image(systemName: "plus.circle.fill") }
    .accessibilityLabel("Add Images")
```

### CollageEditorView.swift — Accessibility + reduce motion + crop undo batching

**Reduce motion:**

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
```

**Panel accessibility:**

```swift
.accessibilityLabel("Image panel")
.accessibilityAddTraits(viewModel.selectedPanelId == panel.id ? [.isSelected] : [])
```

**Crop gesture undo batching** (wrap pan/pinch gestures):

```swift
// Scroll pan callbacks:
ScrollPanView(
    onPanBegan: { id in
        viewModel.undoManager.beginUndoGrouping()
        viewModel.beginScrollPan(panelId: id)
        return true
    },
    onPanChanged: { delta in viewModel.scrollPanDelta(delta) },
    onPanEnded: {
        viewModel.undoManager.setActionName("Adjust Crop")
        viewModel.undoManager.endUndoGrouping()
        viewModel.endScrollPan()
    }
)

// MagnificationGesture:
.onChanged { value in
    if pinchPanelId == nil, let id = viewModel.selectedPanelId {
        pinchPanelId = id
        viewModel.beginPinch(panelId: id)
        viewModel.undoManager.beginUndoGrouping()
    }
    // ...
}
.onEnded { _ in
    if let id = pinchPanelId {
        viewModel.applyPinch(panelId: id)
        viewModel.undoManager.setActionName("Adjust Crop")
        viewModel.undoManager.endUndoGrouping()
    }
    pinchPanelId = nil
}
```

**Title drag undo batching** — capture `oldTitleStyle` at drag start, register single undo at drag end:

```swift
@State private var oldTitleStyle: TitleStyle?

// In DragGesture onChanged when dragTitleLocked first becomes true:
oldTitleStyle = viewModel.titleStyle

// In DragGesture onEnded:
if let oldStyle = oldTitleStyle {
    viewModel.undoManager.registerUndo(withTarget: viewModel) { target in
        target.titleStyle = oldStyle
    }
    viewModel.undoManager.setActionName("Move Title")
}
oldTitleStyle = nil
```

### ExportPanel.swift — Accessibility + progress + success

**Export button with progress:**

```swift
Button(action: {
    Task { [weak viewModel] in await viewModel?.exportCollage() }
}) {
    HStack {
        if viewModel.isExporting {
            ProgressView().accessibilityHidden(true)
        } else {
            Image(systemName: "arrowshape.down.circle.fill")
        }
        Text(viewModel.isExporting ? "Exporting collage..." : "Export JPEG")
    }
    .frame(maxWidth: .infinity)
}
.accessibilityLabel("Export collage as JPEG")
.accessibilityHint("Opens save dialog")
```

**Success feedback (auto-dismiss 3s):**

```swift
if let success = viewModel.exportSuccessMessage {
    HStack {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        Text(success).foregroundStyle(.secondary)
    }
    .font(.caption)
    .padding(.vertical, 4)
    .transition(.opacity)
}
```

**Accessibility — all sliders:**

```swift
Slider(value: $viewModel.exportQuality, in: 0.5...1.0)
    .accessibilityLabel("Export quality")
    .accessibilityValue("\(Int(viewModel.exportQuality * 100)) percent")

Slider(value: $viewModel.titleStyle.fontSize, in: 12...120)
    .accessibilityLabel("Title font size")
    .accessibilityValue("\(Int(viewModel.titleStyle.fontSize)) points")

Slider(value: $viewModel.gradientAngle, in: 0...360)
    .accessibilityLabel("Gradient angle")
    .accessibilityValue("\(Int(viewModel.gradientAngle)) degrees")

Slider(value: $viewModel.backgroundOpacity, in: 0...1)
    .accessibilityLabel("Background image opacity")
    .accessibilityValue("\(Int(viewModel.backgroundOpacity * 100)) percent")
```

**Accessibility — pickers, color wells, buttons, toggles:**

```swift
Picker("Background Style", selection: $viewModel.backgroundStyle) { ... }
    .accessibilityLabel("Background style")

Picker("Align", selection: $viewModel.titleStyle.alignment) { ... }
    .accessibilityLabel("Title alignment")

NSColorPickerView(color: $viewModel.backgroundColor)
    .accessibilityLabel("Background color")

NSColorPickerView(color: $viewModel.titleStyle.fontColor)
    .accessibilityLabel("Title text color")

Toggle(isOn: $viewModel.titleStyle.showBackground) { Label("Title BG", systemImage: "rectangle.fill") }
    .accessibilityLabel("Show title background")

Button("Choose Background") { ... }
    .accessibilityLabel("Choose background image")
    .accessibilityHint("Opens file picker")
```

**Text editor:**

```swift
AttributedStringEditor(...)
    .accessibilityLabel("Title text editor")

FontPickerPopover(...)
    .accessibilityLabel("Title font family")
```

### PanelCropEditor.swift — Accessibility

```swift
Text("Panel Editor")
    .font(.headline)
    .accessibilityAddTraits(.isHeader)

CropPreviewView(...)
    .accessibilityLabel("Crop preview")
    .accessibilityHint("Shows the portion of the image visible in the panel")

Button("Reset Crop") { ... }
    .accessibilityLabel("Reset crop")
    .accessibilityHint("Restores the default crop for this image")

Text("Drag to pan · Scroll + Option to zoom")
    .accessibilityHidden(true)

// Position/Size info
HStack { Text("Position:"); Text(...) }
    .accessibilityLabel("Panel position")

HStack { Text("Size:"); Text(...) }
    .accessibilityLabel("Panel size")
```

### CollageCommands.swift — Accessibility on buttons

```swift
Button("Add Images…") { viewModel.browseImages() }
    .keyboardShortcut("o", modifiers: .command)
    .accessibilityLabel("Add images to collage")
    .accessibilityHint("Opens file picker")

Button("Export JPEG…") { Task { await viewModel.exportCollage() } }
    .keyboardShortcut("s", modifiers: .command)
    .accessibilityLabel("Export collage as JPEG")
    .accessibilityHint("Opens save dialog")
```

### Test between phases

1. Build succeeds
2. VoiceOver reads:
   - Button labels ("Export collage as JPEG", "Add Images")
   - Slider values ("Export quality: 92 percent")
   - Picker selections ("Layout style: Hero")
   - Selected panel ("Image panel, selected")
   - Crop preview ("Crop preview, shows the portion of the image visible in the panel")
3. Progress label shows "Analyzing 5 images..." during saliency
4. Export button shows "Exporting collage..." + spinner during export
5. After export: green checkmark + "Saved to collage.jpg" appears, auto-dismisses after 3s
6. Warning triangle replaced with info circle (gray, not yellow)
7. Sidebar has Liquid Glass floating appearance at top/bottom
8. Reduce Motion: export success uses opacity transition (no jarring animation)
9. Crop pan/pinch creates single undo entry ("Undo Adjust Crop")
10. Title drag creates single undo entry ("Undo Move Title")
11. All existing functionality from Phases 1–3 still works

---

## Summary

| Phase | Concern | Files | Items |
|-------|---------|-------|-------|
| **1** | Undo & Redo | 1 | NSUndoManager, undo registration on all mutating actions, crop batching hooks, default export folder |
| **2** | Settings & Commands | 3 | Settings scene (4 tabs), explicit key modifiers, Cmd+1/2/3 layouts, Cmd+, settings |
| **3** | Context Menus & Alerts | 3 | Panel context menu, sidebar context menu, Clear All confirmation alert |
| **4** | Accessibility & Polish | 6 | Labels/hints/values/traits on all views, progress labels, export feedback, reduce motion, sidebar glass, crop undo batching |

**Total:** 7 files modified, 1 file created, 13 review items addressed.
