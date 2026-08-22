# CollageMaker — UI Patterns & User Control Review

**Date:** 2026-05-11
**Scope:** SwiftUI desktop patterns, user manipulation surface area, post-render controls

---

## Executive Summary

The CollageMaker UI follows a solid three-column `NavigationSplitView` pattern with a sidebar form, canvas editor, and detail panel. The architecture is clean and the gesture-based crop editing works well. However, **the user manipulation surface area is significantly undersized** for a collage tool. After the initial layout is generated, users have limited ways to exert creative control. This review identifies missing controls, anti-patterns in the current UI, and concrete SwiftUI patterns to add.

**Key finding:** The app treats layout as a one-way pipeline (images in -> layout out -> export). It should treat layout as an **iterative, user-driven process** with drag-and-drop reordering, per-panel image assignment, resizable boundaries, and richer background options.

---

## Current UI Pattern Assessment

### What Works Well

| Pattern | Status | Notes |
|---------|--------|-------|
| `NavigationSplitView` three-column | ✅ | Appropriate for desktop; sidebar/editor/detail is the right model |
| Sidebar as `.grouped` Form | ✅ | Standard macOS sidebar appearance |
| Canvas gesture editing (pan/pinch) | ✅ | Well-implemented hit areas with coordinate scaling |
| Detail panel stacking | ✅ | Conditional crop editor + always-visible export panel |
| Drag-and-drop image import | ✅ | Sidebar overlay with visual feedback |
| `NSColorWell` for background | ✅ | Correct AppKit interop for color picking |

### Anti-Patterns Present

| Issue | Location | Problem |
|-------|----------|---------|
| **No image reordering** | `ContentView.swift:46-71` | Images display as numbered list but order is immutable; no drag-to-reorder |
| **No per-panel image assignment** | `ContentView` + `PanelCropEditor` | Panel-to-image mapping is purely positional (panel N gets image N); user can't swap which image goes where |
| **No commands/menus** | `CollageMakerApp.swift` | Zero `.commands` modifiers; no File/Edit/View menus; no keyboard shortcuts |
| **No toolbar** | `ContentView` | No `.toolbar` items; export is buried in the detail panel |
| **No `@AppStorage`** | All settings | Gutter, layout style, quality, background color reset on relaunch |
| **Read-only panel editor** | `PanelCropEditor.swift` | Only shows metadata and a reset button; no sliders or interactive controls |
| **Color-only background** | `ExportPanel.swift` | No option for gradient or image background |
| **Unused `ImagePickerView`** | `Views/ImagePickerView.swift` | Dead code; thumbnail grid view never mounted |
| **`@ObservableObject` instead of `@Observable`** | `CollageViewModel.swift` | Older pattern; macOS 14+ apps should prefer `@Observable` |
| **`onChange` on `@Published`** | `ContentView.swift:86-88` | Uses `.onChange(of:)` instead of `.onReceive($publisher.dropFirst())` |

---

## Missing User Controls (Priority Ranked)

### P0: Image-to-Panel Assignment

**Problem:** The current model assigns images to panels by position. If the user has 5 images, panel 0 gets image 0, panel 1 gets image 1, etc. There is no way to say "I want image 3 in the hero slot."

**Impact:** Users must add images in a very specific order to get the desired layout, or remove and re-add them. This is frustrating and non-intuitive.

**Recommended patterns:**

1. **Drag-and-drop reordering in sidebar** — Use `onDrag`/`onDrop` on each list row to let users reorder their image list. Since panels map positionally, reordering images effectively reassigns them to panels.

2. **Per-panel image picker in detail panel** — When a panel is selected, `PanelCropEditor` should show a picker or thumbnail grid of all loaded images, letting the user choose which image fills that panel. This is the most direct and powerful approach.

```swift
// In PanelCropEditor or a new PanelAssignView:
Picker("Image", selection: $viewModel.panelImageAssignments[panel.id]) {
    ForEach(viewModel.images.indices, id: \.self) { idx in
        HStack {
            Image(nsImage: viewModel.images[idx].nsImage)
                .resizable()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(viewModel.images[idx].filename)
                .lineLimit(1)
        }
        .tag(idx)
    }
}
```

3. **Drag image from sidebar onto canvas panel** — Richer but more complex. Add `onDrag` to sidebar rows and `onDrop` to canvas hit areas. Dropping image A onto panel B reassigns that panel.

### P1: Image Reordering

**Problem:** The sidebar shows images as a numbered list but the order is fixed to drop order. No drag handles, no move buttons, no sortable interface.

**Recommended pattern:** Add drag-to-reorder to the sidebar `ForEach`. SwiftUI's `onDrag`/`onDrop` on list items is the standard macOS pattern:

```swift
ForEach(Array(viewModel.images.enumerated()), id: \.element.id) { index, item in
    HStack { /* existing row content */ }
        .onDrag {
            NSItemProvider(object: NSPasteboard.Item(string: "\(index)") as NSItemProviderWriting)
        }
        .onDrop(of: [.text], isTargeted: nil) { providers in
            // Handle reorder from dragged index to this index
            return true
        }
}
```

Alternatively, add up/down arrow buttons for keyboard-accessible reordering.

### P1: Background Image Support

**Problem:** `ExportPanel` only offers `NSColorWell` for solid color background. Many collages benefit from gradient fills, blurred photo backgrounds, or pattern fills.

**Recommended patterns:**

1. **Segmented control for background type** — Add a `Picker` or `SegmentedControl` with options: Solid Color, Gradient, Image. Conditionally show the relevant controls.

2. **Gradient background** — Two `NSColorWell`s for gradient endpoints + an angle slider. Update `CollageAssembler` to draw a `CGGradient` instead of a solid color.

3. **Image background** — A "Choose Background Image" button that opens `NSOpenPanel`. The selected image is drawn at canvas size with a blur or dim overlay, then panels are composited on top.

```swift
// In ExportPanel or a new BackgroundPanel:
enum BackgroundStyle: String, CaseIterable, Identifiable {
    case solid, gradient, image
    var id: String { rawValue }
}

Picker("Background", selection: $viewModel.backgroundStyle) {
    ForEach(BackgroundStyle.allCases) { style in
        Text(style.rawValue.capitalized).tag(style)
    }
}
.pickerStyle(.segmented)

switch viewModel.backgroundStyle {
case .solid:
    NSColorPickerView(color: $viewModel.backgroundColor)
case .gradient:
    // Two color wells + angle slider
case .image:
    // Button to pick background image + opacity slider
}
```

### P2: Panel Boundary Editing

**Problem:** Panel frames are computed by `LayoutGenerator` and are immutable from the user's perspective. The gutter slider affects all panels globally, but there's no way to adjust individual panel sizes or positions.

**Recommended patterns:**

1. **Resize handles on selected panel** — When a panel is selected on the canvas, draw draggable handles on the panel edges (similar to selection rectangles in Preview or Photos). Dragging a handle adjusts the panel frame and pushes adjacent panels.

2. **Slider-based panel sizing in detail panel** — Add width/height sliders to `PanelCropEditor` for fine control. This is simpler than visual handles but less intuitive.

3. **Layout presets with visual thumbnails** — Instead of a text picker, show small layout thumbnails that users can click. This gives a better sense of what each layout looks like before applying it.

Note: Freeform panel resizing with adjacent panel adjustment is complex. Consider starting with per-panel size sliders before attempting visual drag handles.

### P2: Keyboard Shortcuts & Commands

**Problem:** The app has zero `.commands` modifiers. No File menu, no Edit menu, no keyboard shortcuts. A desktop app should expose core actions through menus.

**Recommended additions:**

```swift
// In ContentView or a dedicated Commands file:
.commands {
    CommandGroup(replacing: .newItem) {
        Button("Add Images...") { viewModel.browseImages() }
            .keyboardShortcut("o", modifiers: .command)
    }
    CommandGroup(replacing: .saveItem) {
        Button("Export JPEG...") {
            Task { await viewModel.exportCollage() }
        }
        .keyboardShortcut("s", modifiers: .command)
    }
    CommandGroup(replacing: .newItem) {
        Button("Clear All") { viewModel.clearAll() }
    }
    CommandMenu("Layout") {
        Button("Uniform") { viewModel.setLayoutStyle(.uniform) }
        Button("Hero") { viewModel.setLayoutStyle(.hero) }
        Button("Mosaic") { viewModel.setLayoutStyle(.mosaic) }
    }
}
```

### P3: Toolbar

**Problem:** No `.toolbar` items. Export is buried in the detail panel. Common actions should be one click away.

**Recommended:**

```swift
.toolbar {
    ToolbarItemGroup(placement: .primaryAction) {
        Button {
            Task { await viewModel.exportCollage() }
        } label: {
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

### P3: Persistent Preferences

**Problem:** No `@AppStorage` usage. Every session starts with default gutter, layout style, quality, and background color.

**Recommended:** Add `@AppStorage` keys for layout preferences:

```swift
@AppStorage("layoutStyle") var layoutStyle: String = "hero"
@AppStorage("gutter") var gutter: CGFloat = 4
@AppStorage("exportQuality") var exportQuality: Double = 0.92
@AppStorage("title") var title: String = ""
```

Note: `NSColor` doesn't encode to `UserDefaults` directly. Use a `@AppStorage` String key with a color serializer, or store in a custom `UserDefaults` extension.

---

## SwiftUI Pattern Violations

### `@ObservableObject` vs `@Observable`

`CollageViewModel` uses the older `@ObservableObject`/`@Published` pattern. On macOS 14+, the `@Observable` macro is preferred:

- Smaller binary (no `Combine` dependency for observation)
- `@MainActor` is implicit
- Will-set/did-set style observation with `@ObservationIgnored` for selective exclusion
- No need for `objectWillChange.send()` manual calls

### `.onChange` on `@Published` properties

`ContentView.swift:86-88` and `:98-100` use `.onChange(of: viewModel.layoutStyle)` to react to `@Published` changes. The SwiftUI patterns guide recommends `.onReceive(viewModel.$layoutStyle.dropFirst())` instead, as `@Published` only fires on property assignment and `.onChange` can fire on view body re-evaluation.

### `@EnvironmentObject` for everything

All views receive `CollageViewModel` via `@EnvironmentObject`. This works but makes dependencies implicit. Consider passing focused bindings or explicit references to subviews that only need a slice of state (e.g., `PanelCropEditor` only needs `cropMap` and `resetCrop(_:)`).

### Missing `@SceneStorage`

No per-window state is preserved. If a user opens a second window (not currently supported, but possible with `WindowGroup`), each window would share the same `CollageViewModel` state, which is incorrect.

---

## Recommended View Structure After Improvements

```
NavigationSplitView {
    Sidebar {                           // column 1 — image management
        Section "Images" {
            Reorderable image list      // drag-to-reorder + drag-to-canvas
            Add / Clear buttons
        }
        Section "Layout" {
            Layout style picker         // visual thumbnails preferred
            Gutter slider
        }
    }
    .modifier(DragDropOverlay)          // image import

    Canvas {                            // column 2 — visual editor
        Preview image
        Panel hit areas with:
            - Tap to select
            - Drag to pan crop
            - Pinch to zoom crop
            - Resize handles (future)
        Selection indicator
    }
    .toolbar { Export + Add buttons }

    Detail {                            // column 3 — panel controls + export
        if panel selected {
            PanelEditor {
                Image assignment picker  // NEW: which image in this panel
                Crop controls            // pan/zoom sliders as alternative to gestures
                Reset crop button
            }
        }

        BackgroundEditor {              // NEW: replaces simple color well
            Style selector (solid/gradient/image)
            Conditional controls
        }

        ExportPanel {
            Title field
            Quality slider
            Export button
        }
    }
}
.commands { File, Edit, Layout menus }
```

---

## Implementation Priority

| Priority | Feature | Effort | User Impact |
|----------|---------|--------|-------------|
| P0 | Per-panel image assignment | Medium | High — fundamental control missing |
| P0 | Commands/menus + keyboard shortcuts | Low | High — desktop expectation |
| P1 | Image reordering (drag in sidebar) | Medium | High — affects layout outcome |
| P1 | Background image/gradient support | Medium | Medium — creative control |
| P2 | Panel boundary editing (sliders) | High | Medium — fine-tuning |
| P2 | Toolbar with export/add | Low | Medium — discoverability |
| P3 | Persistent preferences (`@AppStorage`) | Low | Low — convenience |
| P3 | `@Observable` migration | Medium | Low — technical debt |
| P3 | Layout style visual thumbnails | Medium | Low — UX polish |

---

## Summary

The CollageMaker UI has a solid structural foundation but treats the collage as a one-shot generation rather than an iterative creative process. The three most impactful additions would be:

1. **Per-panel image assignment** — Let users choose which image goes in which panel
2. **Image reordering** — Drag-to-reorder in the sidebar
3. **Commands and keyboard shortcuts** — Standard macOS menu exposure for core actions

These three changes address the core concern that users lack power and control after initial rendering, with minimal architectural disruption.
