# SwiftUI UI Patterns — Scale Analysis (40+ Images)

## Date
2026-05-12

## Context

CollageMaker uses a `NavigationSplitView` with three panes: sidebar (image list + layout controls), center canvas editor, and detail panel (panel crop editor + export settings). This document analyzes how the current patterns break down at scale and recommends improvements.

---

## Current Patterns — What Works

- **`NavigationSplitView` three-pane layout**: Correct choice for a macOS editor. Sidebar-detail is the canonical desktop pattern.
- **`Form` with `.formStyle(.grouped)`** for the sidebar: Provides native scrolling, section headers, and macOS-appropriate density.
- **`GeometryReader` + `ZStack`** for the canvas editor: Necessary for overlaying hit areas on the preview image.
- **`@Observable` view model**: Clean separation, no retain-cycle pitfalls. Services are protocol-injected for testability.
- **Toolbar actions** for export and add-images: Standard macOS placement, discoverable.
- **Drag-and-drop on sidebar**: Good primary acquisition path.

---

## Problems at 40 Images

### 1. Sidebar Image List — No Visual Scanning

**Current:** Text-only rows (`"1. photo.jpg"`) in a `ForEach` inside a `Form`.

**At 40 images:** The user cannot visually distinguish images. Filenames are often uninformative (`IMG_4821.jpg`). Scrolling through 40 text rows to find a specific image is slow and error-prone.

**Recommendation — Thumbnail grid or icon rows:**

Add a small thumbnail (32x32) to each sidebar row. The `Form` already scrolls, so the vertical growth is acceptable. Pattern:

```swift
ForEach(Array(viewModel.images.enumerated()), id: \.element.id) { index, item in
    HStack {
        Image(nsImage: item.nsImage)
            .resizable()
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .scaledToFill()

        VStack(alignment: .leading, spacing: 1) {
            Text(item.filename)
                .lineLimit(1)
                .font(.caption)
            Text("#\(index + 1)")
                .lineLimit(1)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }

        Spacer()

        if viewModel.heroIndex == index {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
        }

        Button { viewModel.removeImage(at: index) } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
    .contentShape(Rectangle())
    .onTapGesture {
        if viewModel.layoutStyle == .hero {
            viewModel.heroIndex = viewModel.heroIndex == index ? nil : index
        }
    }
}
```

**Why thumbnails in rows, not a grid:** A `LazyVGrid` would lose the `Form`'s native section headers, grouped styling, and integration with the drag-and-drop overlay. Keeping thumbnails inside the `Form` rows preserves the sidebar's structural relationship with the Layout and Status sections below it.

### 2. Hero Image Picker — Unusable at Scale

**Current:** `.pickerStyle(.menu)` listing `"Image 1"`, `"Image 2"`, … `"Image 40"`.

**At 40 images:** The user must enumerate through 40 unlabeled options. There is no way to know which image is which.

**Recommendation — Thumbnail-based hero selector:**

Replace the menu-style picker with a horizontally scrolling thumbnail strip that appears when hero layout is active:

```swift
if viewModel.layoutStyle == .hero && !viewModel.images.isEmpty {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
            Button {
                viewModel.heroIndex = nil
            } label: {
                Text("None")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(viewModel.heroIndex == nil ? Color.accentColor : Color.clear)
                    .clipShape(Capsule())
            }

            ForEach(Array(viewModel.images.enumerated()), id: \.element.id) { index, item in
                Button {
                    viewModel.heroIndex = viewModel.heroIndex == index ? nil : index
                } label: {
                    Image(nsImage: item.nsImage)
                        .resizable()
                        .frame(width: 40, height: 40)
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(
                                    viewModel.heroIndex == index ? Color.accentColor : Color.clear,
                                    lineWidth: 2
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 4)
    }
}
```

This gives visual identification, tap-to-select, and doesn't consume excessive vertical sidebar space.

### 3. Panel Image Reassignment Picker — Cluttered

**Current:** `.pickerStyle(.inline)` with 24x24 thumbnails for every image.

**At 40 images:** The inline picker becomes a tall scrollable list embedded in the detail panel. It competes for space with the export controls below it.

**Recommendation — Searchable popover or sheet:**

Keep the inline picker for small counts (<10). For larger counts, replace with a button that opens a popover containing a searchable thumbnail grid:

```swift
// In PanelCropEditor:
@State private var showImagePicker = false

Button {
    showImagePicker = true
} label: {
    HStack {
        Image(nsImage: viewModel.images[effectiveIndex.wrappedValue].nsImage)
            .resizable()
            .frame(width: 32, height: 32)
            .scaledToFill()
            .clipShape(RoundedRectangle(cornerRadius: 4))
        Text(viewModel.images[effectiveIndex.wrappedValue].filename)
            .lineLimit(1)
        Spacer()
        Image(systemName: "arrow.triangle.2.circlepath")
            .foregroundStyle(.secondary)
    }
}
.popover(isPresented: $showImagePicker) {
    ImagePickerGrid(
        images: viewModel.images,
        selection: effectiveIndex
    )
    .frame(width: 320, height: 400)
}
```

The `ImagePickerGrid` would use a `LazyVGrid` with a `Searchable` modifier for filename filtering.

### 4. Mosaic Layout Caps at 12 Panels

**Current:** `LayoutGenerator.generateMosaic` has `let maxSplits = min(numImages, 12)`.

**At 40 images:** Only 12 of 40 images appear in the collage. The remaining 28 are silently discarded. The user has no indication that images were dropped.

**Recommendation — Two options:**

- **Option A (Raise the cap):** Increase `maxSplits` to a reasonable value (e.g., 20-24). The mosaic algorithm produces smaller panels, but at 1920x1080 canvas, panels smaller than ~100px become meaningless for photo collages.
- **Option B (Warn the user):** Add a status message in the sidebar when `panels.count < images.count`:

```swift
if viewModel.panels.count < viewModel.images.count {
    Section("Notice") {
        Label(
            "Only \(viewModel.panels.count) of \(viewModel.images.count) images are in the layout",
            systemImage: "exclamationmark.triangle"
        )
        .foregroundStyle(.yellow)
        .font(.caption)
    }
}
```

Option B is the minimum viable fix. Option A requires rethinking whether mosaic is appropriate for 40 images — it probably isn't. Uniform grid is the better layout for large counts.

### 5. No Image Reordering

**Current:** Images are assigned to panels by array index. There is no way to reorder images.

**At 40 images:** The user adds images in arbitrary filesystem order. With no reordering, getting the right image in the hero slot or in a desired position requires removing and re-adding images.

**Recommendation — Drag-to-reorder in sidebar:**

Add `.onDrag` and `.onDrop` to sidebar rows for native reorder support:

```swift
ForEach(Array(viewModel.images.enumerated()), id: \.element.id) { index, item in
    HStack { /* ... row content ... */ }
    .onDrag {
        NSItemProvider(object: NSPasteboardItem(identifier: index as NSObject)!)
    }
    .onDrop(of: [.uuid], isTargeted: nil) { providers in
        // Compute drag destination index from drop location
        // Call viewModel.moveImage(from: index, to: destination)
        return true
    }
}
```

Alternatively, a simpler approach: add up/down arrow buttons to each row for keyboard-driven reordering.

### 6. `updatePreview()` Called Too Frequently

**Current:** Every gesture delta during pan calls `applyPanLive()` → `updatePreview()`, which spawns a `Task.detached` that assembles a full bitmap. With 40 images, each assembly processes 40 panel draws.

**At 40 images:** The preview may lag during drag. The current `previewTask?.cancel()` helps, but cancelled tasks still do work before checking cancellation.

**Recommendation — Debounced live preview:**

Add a debounce timer for live preview during gestures. Only commit the full render on gesture end, showing a lightweight indicator during drag:

```swift
private var previewDebounce: DispatchWorkItem?

func applyPanLive() {
    cropManager.applyPan(panelId: nil, panels: panels, images: images, finish: false)
    cropMap = cropManager.cropMap

    previewDebounce?.cancel()
    previewDebounce = DispatchWorkItem { [weak self] in
        self?.updatePreview()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: previewDebounce!)
}
```

This reduces render calls from ~60/sec during drag to ~6/sec, with a final render on gesture end.

### 7. Hit Testing Is O(n) Per Tap

**Current:** `panelAt(location:)` iterates all panels sequentially, computing scaled frames each time.

**At 40 images with uniform layout (all 40 panels):** 40 rectangle containment checks per tap. Not catastrophic, but unnecessary.

**Recommendation — Cached scaled frames:**

Compute scaled panel frames once per geometry change, not per tap:

```swift
@State private var scaledPanelFrames: [UUID: CGRect] = [:]

// Inside GeometryReader:
.onAppear {
    scaledPanelFrames = computeScaledFrames(panels: viewModel.panels, in: geometry.size)
}
.onChange(of: geometry.size) { _, newSize in
    scaledPanelFrames = computeScaledFrames(panels: viewModel.panels, in: newSize)
}

private func panelAt(location: CGPoint) -> UUID? {
    for (id, frame) in scaledPanelFrames where frame.contains(location) {
        return id
    }
    return nil
}
```

### 8. Adding Images After Initial Set

**Current:** The toolbar has a `+` button that calls `viewModel.browseImages()`. The sidebar only shows a drop overlay and tap-to-browse when empty.

**At 40 images:** The toolbar `+` button is the only discoverable path. But the sidebar also accepts drops when images exist (the `.onDrop` modifier is always active). This is fine but not obvious.

**Recommendation — Make the add action more discoverable:**

- Keep the toolbar `+` button (it's already there, good)
- Add a persistent "Add Images…" row at the bottom of the Images section in the sidebar, even when images exist:

```swift
Section("Images") {
    ForEach(/* ... */) { /* ... */ }

    Button {
        viewModel.browseImages()
    } label: {
        Label("Add Images", systemImage: "plus.circle.fill")
    }
    .buttonStyle(.plain)
}
```

This gives two always-visible entry points: toolbar and sidebar.

### 9. Detail Panel Controls Flowing Off-Screen

**Current:** The detail pane stacks `PanelCropEditor` and `ExportPanel` vertically with `.frame(maxHeight: .infinity, alignment: .top)`. The `ExportPanel` has title, quality slider, background style with conditional controls (color well, gradient with two color wells + angle slider, or image picker + opacity slider), and an export button.

**At small window sizes or with panel editor visible:** The gradient background controls alone (two color wells, labels, angle slider) can push the export button below the visible area. The detail pane has no explicit scrolling.

**Recommendation — Wrap detail content in `ScrollView`:**

```swift
private var detail: some View {
    ScrollView {
        VStack(spacing: 24) {
            if let selectedId = viewModel.selectedPanelId,
               let panel = viewModel.panels.first(where: { $0.id == selectedId }) {
                PanelCropEditor(panel: panel, viewModel: viewModel)
                    .id(panel.id)
            }

            ExportPanel(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
```

This ensures all controls remain accessible regardless of window size or how many controls are visible.

### 10. No Search or Filtering for Images

**At 40 images:** Finding a specific image by name requires scrolling.

**Recommendation — `searchable` modifier on the sidebar:**

Add a search field that filters the visible image rows:

```swift
@State private var searchQuery = ""

private var filteredImages: [(index: Int, item: ImageItem)] {
    if searchQuery.isEmpty {
        return viewModel.images.enumerated().map { ($0.offset, $0.element) }
    } else {
        return viewModel.images.enumerated()
            .filter { $0.element.filename.localizedCaseInsensitiveContains(searchQuery) }
            .map { ($0.offset, $0.element) }
    }
}

// Then in the sidebar:
.searchable(text: $searchQuery, prompt: "Search images")
```

Note: The index shown in the row should be the original index (for hero selection), not the filtered position.

---

## Summary of Recommendations by Priority

| Priority | Issue | Fix |
|----------|-------|-----|
| **P0** | Detail panel controls flow off-screen | Wrap in `ScrollView` |
| **P0** | Mosaic silently drops images beyond 12 | Warn user when `panels.count < images.count` |
| **P1** | No visual identification in sidebar | Add 32x32 thumbnails to sidebar rows |
| **P1** | Hero picker unusable at scale | Replace menu with horizontal thumbnail strip |
| **P1** | No way to add images after initial set (discoverability) | Persistent "Add Images" row in sidebar |
| **P2** | Panel reassignment picker cluttered | Popover with searchable grid for large counts |
| **P2** | Preview renders too frequently during drag | Debounce `applyPanLive()` preview updates |
| **P2** | No search for images | Add `.searchable` to sidebar |
| **P3** | No image reordering | Add drag-to-reorder or up/down buttons |
| **P3** | Hit testing O(n) per tap | Cache scaled panel frames |

---

## Anti-Patterns to Avoid When Implementing

- **Don't switch the sidebar to `LazyVGrid`:** It loses `Form`'s section headers, grouped styling, and macOS-native scrollbar behavior. Thumbnails inside `Form` rows is the better compromise.
- **Don't add a fourth `NavigationSplitView` column:** Three panes is the macOS convention. A popover or sheet is the right container for expanded pickers.
- **Don't load full-resolution thumbnails:** Generate small preview thumbnails (64x64 max) for sidebar display to avoid memory pressure with 40+ images.
- **Don't block the main thread for saliency on 40 images:** The current `Task { await analyzeSaliency() }` pattern is correct. Just ensure the `isProcessing` indicator is visible during analysis.
- **Don't renumber sidebar items after filtering:** When search is active, show the original position number so hero index selection remains consistent.
