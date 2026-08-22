# Scale Analysis Fixes — Implementation Plan

## Date
2026-05-12

## Source Document
`_agent_docs/learnings/swiftui-gesture-direction-responsiveness-learnings.md`

## Decisions
- Thumbnail generation: synchronous on background queue, append all at once on main (option A)
- Mosaic cap: raise from 12 to 20
- Image reorder: `onMove(perform:)` on sidebar `ForEach` (native, no custom drag types)
- Canvas pan: replace single-finger `DragGesture` with two-finger scroll via `NSViewRepresentable`
- Batching: 4 batches to control context

---

## Batch 1 — Quick Wins (P0-P1)

### #1: Detail Panel ScrollView
**Priority:** P0
**Files:** `ContentView.swift:230-241`

Wrap the `detail` VStack in `ScrollView { }`. Remove `maxHeight: .infinity` from inner VStack (conflicts with ScrollView).

```swift
// Before:
private var detail: some View {
    VStack(spacing: 24) {
        // ...
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
}

// After:
private var detail: some View {
    ScrollView {
        VStack(spacing: 24) {
            // ...
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
```

### #2: Mosaic Cap 12→20 + Warning
**Priority:** P0
**Files:** `LayoutGenerator.swift:125`, `ContentView.swift` (sidebar Status section)

- Change `min(numImages, 12)` → `min(numImages, 20)` at line 125
- Add warning `Section` in sidebar when `viewModel.panels.count < viewModel.images.count`:

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

### #5: Persistent "Add Images" Row
**Priority:** P1
**Files:** `ContentView.swift:71` (end of Images Section)

Add a `Button` at the bottom of the Images `Section`, always visible when images exist:

```swift
Button {
    viewModel.browseImages()
} label: {
    Label("Add Images", systemImage: "plus.circle.fill")
}
.buttonStyle(.plain)
```

---

## Batch 2 — Sidebar Overhaul (P1)

### #3: Thumbnails in Sidebar Rows
**Priority:** P1
**Files:** `ContentView.swift:45-70`, `ImageItem.swift`, `CollageViewModel.swift:187-213`

**ImageItem changes:**
- Add `thumbnail: NSImage` property (64x64, generated from `cgImage`)

**Thumbnail generation:**
- In `CollageViewModel.addImages(from:)`: generate thumbnails on a background queue using CoreGraphics (`NSImage(size: CGSize(width: 64, height: 64))` + `NSBitmapImageRep` + `CGContext` with `.high` interpolation)
- Build full `ImageItem` on background queue, append all at once on main actor
- For 40 images at 64x64, expected <200ms total

**Sidebar row layout:**
```swift
ForEach(Array(viewModel.images.enumerated()), id: \.element.id) { index, item in
    HStack {
        Image(nsImage: item.thumbnail)
            .resizable()
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .scaledToFill()

        VStack(alignment: .leading, spacing: 1) {
            Text(item.filename)
                .lineLimit(1)
                .font(.caption)
            Text("#\(index + 1)")
                .limit(1)
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

### #4: Hero Thumbnail Strip
**Priority:** P1
**Files:** `ContentView.swift:86-94`

Replace `.pickerStyle(.menu)` with horizontal `ScrollView` + `HStack` of thumbnail buttons:

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
                    Image(nsImage: item.thumbnail)
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

### #8: Sidebar Search
**Priority:** P1
**Files:** `ContentView.swift`

Add `@State private var searchQuery = ""` to `ContentView`. Add `.searchable(text: $searchQuery, prompt: "Search images")` to the `Form`. Filter `ForEach` items by filename but preserve original indices for hero selection:

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

// In sidebar:
ForEach(filteredImages, id: \.item.id) { index, item in
    // ... row content using `index` (original index) ...
}
```

Note: The index shown in the row is the original index (for hero selection), not the filtered position.

### #9: Image Reordering
**Priority:** P1
**Files:** `ContentView.swift` sidebar `ForEach`, `CollageViewModel.swift`

Use `.onMove(perform:)` on the `ForEach` inside the `Form`. The `Form` renders as an `NSTableView` underneath which supports `onMove` natively.

**ContentView:**
```swift
ForEach(filteredImages, id: \.item.id) { index, item in
    // ... row ...
}
.onMove { from, to in
    viewModel.moveImages(from: from, to: to)
}
```

**CollageViewModel:**
```swift
func moveImages(from: IndexSet, to: Int) {
    images.move(fromOffsets: from, toOffset: to)
    // Update panelAssignments: remap indices that shifted
    remapPanelAssignments()
    regenerateLayout()
}

private func remapPanelAssignments() {
    // After array reorder, panelAssignments indices may point to wrong images.
    // Strategy: clear manual assignments and let layout reassign by index,
    // OR track the permutation and remap each assignment.
    // Simplest: clear assignments, regenerate layout.
    panelAssignments.removeAll()
}
```

Note: Clearing `panelAssignments` on reorder is acceptable — the user explicitly reordered, so the new index-based assignment is the intended state. If we want to preserve manual overrides, we'd need to track the permutation, but that's overkill for initial implementation.

---

## Batch 3 — Performance & Pickers (P2)

### #7: Debounce Preview During Drag
**Priority:** P2
**Files:** `CollageViewModel.swift:350-354`

Add `DispatchWorkItem` debounce (0.15s) in `applyPanLive()`:

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

On gesture end, `applyPan()` (non-debounced) fires the final render.

### #10: Cache Scaled Panel Frames
**Priority:** P2
**Files:** `CollageEditorView.swift:126-136`

```swift
@State private var scaledPanelFrames: [UUID: CGRect] = [:]

// Inside GeometryReader:
.onChange(of: (geometry.size, viewModel.panels.count)) { _, _ in
    scaledPanelFrames = viewModel.panels.reduce(into: [:]) { dict, panel in
        dict[panel.id] = canvasToPreviewFrame(panel.frame, in: geometry.size)
    }
}

private func panelAt(location: CGPoint) -> UUID? {
    for (id, frame) in scaledPanelFrames where frame.contains(location) {
        return id
    }
    return nil
}
```

Note: We also need to invalidate on `viewModel.panels` change (layout regeneration). The `panels.count` change triggers recompute, but panel frames change even with same count (e.g., gutter change). A more robust approach: use `.onChange(of: viewModel.panels.map { $0.id })` or a computed `layoutVersion` on the ViewModel.

### #6: Panel Reassignment Popover
**Priority:** P2
**Files:** `PanelCropEditor.swift:31-44`, new `ImagePickerGrid.swift`

Threshold: `< 10` images keep inline picker, `>= 10` switch to popover button.

**PanelCropEditor:**
```swift
if viewModel.images.count < 10 {
    // Existing inline picker
} else {
    @State private var showImagePicker = false

    Button {
        showImagePicker = true
    } label: {
        HStack {
            Image(nsImage: viewModel.images[effectiveIndex.wrappedValue].thumbnail)
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
}
```

**ImagePickerGrid.swift (new):**
- `LazyVGrid` with 48x48 thumbnails
- `Searchable` modifier for filename filtering
- Tap to select, dismisses popover

---

## Batch 4 — Gesture Redesign

### Two-Finger Scroll Pan
**Priority:** P2
**Files:** New `ScrollPanView.swift`, `CollageEditorView.swift`

**Rationale:** Single-finger `DragGesture` conflicts with click+drag for sidebar reorder. Two-finger scroll is the macOS convention for panning content.

**New file `ScrollPanView.swift`:**
- `NSViewRepresentable` with transparent `NSView`
- Override `scrollWheel(with:)` to capture two-finger scroll events
- Track pan state: begin on `.began` phase, commit on `.ended` phase
- Convert scroll delta to pan delta: `pan(by: CGSize(width: -deltaX, height: -deltaY))`
- Hit-test `NSEvent.locationInWindow` (converted to view coords) against panels to lock target

**Coordinate verification:**
```
Scroll down (finger moves up on trackpad) → deltaY < 0 → pan(by: (0, -deltaY)) → positive Y delta
Drag down (finger moves down on screen)   → translation.height > 0 → pan(by: (0, translation.height)) → positive Y delta
Both produce same visual result: crop viewport moves down
```

**Integration in `CollageEditorView.swift`:**
- Remove `DragGesture(minimumDistance: 5)` block (lines 66-84)
- Add `.overlay` with `ScrollPanView(viewModel: viewModel, panels: viewModel.panels, previewSize: geometry.size)` filling the GeometryReader
- Reuse `dragPanelId` state variable for scroll pan targeting
- Keep `MagnificationGesture` (pinch zoom) and `onTapGesture` (panel selection) unchanged

**Why no conflict:**
- Two-finger trackpad scroll → `NSEventType.scrollWheel` → `ScrollPanView`
- Option+scroll or trackpad pinch → `MagnificationGesture` → zoom
- Single tap → `onTapGesture` → panel selection
- These are distinct input modes handled by different systems

**Implementation details for `ScrollPanView`:**
```swift
struct ScrollPanView: NSViewRepresentable {
    let viewModel: CollageViewModel
    let panels: [ImagePanel]
    let previewSize: CGSize
    @Binding var dragPanelId: UUID?

    func makeNSView(context: Context) -> NSView {
        let view = ScrollPanNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let view = nsView as! ScrollPanNSView
        view.panels = panels
        view.previewSize = previewSize
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    class Coordinator: NSObject {
        let viewModel: CollageViewModel
        // ... methods to call viewModel.beginPan, pan, applyPan
    }

    class ScrollPanNSView: NSView {
        var coordinator: Coordinator?
        var panels: [ImagePanel] = []
        var previewSize: CGSize = .zero
        private var activePanelId: UUID?

        override func scrollWheel(with event: NSEvent) {
            guard event.type == .scrollWheel else { return }

            // Convert window coords to view coords for hit testing
            let location = convert(event.locationInWindow, from: nil)

            let deltaX = -event.scrollingDeltaX
            let deltaY = -event.scrollingDeltaY

            switch event.mPhase {
            case .began:
                if activePanelId == nil {
                    // Hit-test to find panel
                    activePanelId = hitTestPanel(at: location)
                    if let id = activePanelId {
                        coordinator?.beginPan(id)
                    }
                }
            case .changed:
                if let id = activePanelId {
                    coordinator?.pan(by: CGSize(width: deltaX, height: deltaY))
                    coordinator?.applyPanLive()
                }
            case .ended, .mayBegin, .cancelled, .failed:
                if let id = activePanelId {
                    coordinator?.applyPan(id)
                }
                activePanelId = nil
            default:
                break
            }
        }

        private func hitTestPanel(at location: CGPoint) -> UUID? {
            // Same logic as panelAt in CollageEditorView
            for panel in panels {
                // Compute scaled frame and check containment
                // ...
            }
            return nil
        }
    }
}
```

**Note:** The `NSEvent.mPhase` approach may need a debounce for continuous trackpad scroll, since `.ended` fires after each scroll burst. A 100ms no-events timer after `.changed` stops firing would commit the pan.

---

## Summary of All Changes

| Priority | Batch | Items | New Files | Risk |
|----------|-------|-------|-----------|------|
| P0 | 1 | #1 ScrollView, #2 mosaic cap+warning, #5 Add Images row | — | None |
| P1 | 2 | #3 thumbnails, #4 hero strip, #8 search, #9 reorder | — | Medium |
| P2 | 3 | #6 popover picker, #7 debounce, #10 hit test cache | `ImagePickerGrid.swift` | Low-Medium |
| P2 | 4 | Two-finger scroll pan | `ScrollPanView.swift` | High |

## Anti-Patterns to Avoid
- Don't switch sidebar to `LazyVGrid` — loses `Form` section headers and native styling
- Don't add a fourth `NavigationSplitView` column — three panes is the macOS convention
- Don't load full-resolution thumbnails — generate 64x64 max
- Don't block main thread for thumbnail generation — use background queue
- Don't renumber sidebar items after filtering — show original position number
- Keep AppKit bridge narrow — isolate `ScrollPanView` behind small wrapper
