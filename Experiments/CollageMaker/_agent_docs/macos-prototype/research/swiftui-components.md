# SwiftUI Components for CollageMaker

## PhotosPicker — Image Selection from Photo Library

`PhotosPicker` (from PhotosUI, available macOS 13+) provides system-integrated photo library access.

### Basic Usage

```swift
import SwiftUI
import PhotosUI

struct PhotosSelector: View {
    @State var selectedItems: [PhotosPickerItem] = []

    var body: some View {
        PhotosPicker(selection: $selectedItems, matching: .images) {
            Text("Select Multiple Photos")
        }
    }
}
```

### Loading Selected Items

`PhotosPickerItem` conforms to `Transferable`. Load actual images asynchronously:

```swift
func loadImage(from item: PhotosPickerItem) {
    item.loadTransferable(type: Image.self) { result in
        DispatchQueue.main.async {
            switch result {
            case .success(let image?):
                // Use the SwiftUI Image
            case .success(nil):
                // Empty value
            case .failure(let error):
                // Handle error (e.g., iCloud download failure)
            }
        }
    }
}
```

### Important Notes

- `Image` only supports **PNG** through `Transferable` — for JPEG, load as `Data` and create `NSImage(data:)`
- Use `PHPickerFilter` to customize what's shown:
  - `.images` — images only
  - `.videos` — videos only
  - `.any(of: [.images, .not(.screenshots)])` — images excluding screenshots
- `maxSelectionCount` limits number of selectable items

### Loading NSImage from PhotosPickerItem

```swift
item.loadTransferable(type: Data.self) { result in
    if let data = try? result.get(), let nsImage = NSImage(data: data) {
        // Use nsImage
    }
}
```

## Drag and Drop — `.onDrop` Modifier

The `.onDrop(of:delegate:)` modifier (macOS 11+) handles file drag-and-drop.

### Basic Usage

```swift
var body: some View {
    VStack {
        Text("Drop images here")
    }
    .onDrop(of: [.jpeg, .png], isTargeted: $isDragging) { providers -> Bool in
        // Handle dropped files
        return true
    }
}
```

### Loading Dropped Files

```swift
.onDrop(of: [.jpeg, .png, .image], isTargeted: nil) { providers -> Bool in
    var handled = false
    for provider in providers {
        if provider.hasItemConformingToTypeIdentifier(.jpeg) {
            provider.loadDataRepresentation(forTypeIdentifier: .jpeg) { data, error in
                if let data = data, let image = NSImage(data: data) {
                    // Add image to collection
                }
            }
            handled = true
        }
    }
    return handled
}
```

### UTType Identifiers

- `.jpeg` — JPEG images
- `.png` — PNG images
- `.image` — any image type
- `.fileURL` — file URLs (for getting actual file paths)

### DropDelegate Protocol

For fine-grained control over drop behavior:

```swift
class ImageDropDelegate: DropDelegate {
    func performDrop(info: DropInfo) -> Bool {
        // Handle drop
    }
    func dropChanged(info: DropInfo) {
        // Respond to drop position changes
    }
}
```

## NavigationSplitView — Sidebar + Editor Layout

`NavigationSplitView` (macOS 13+) provides a multi-column layout ideal for the editor.

### Two-Column Layout

```swift
@State private var selectedPanelId: UUID?

var body: some View {
    NavigationSplitView {
        // Sidebar — panel list / image thumbnails
        List(panels, id: \.id, selection: $selectedPanelId) { panel in
            Text("Panel \(panel.imageIndex)")
        }
    } detail: {
        // Detail — collage preview + crop controls
        if let panelId = selectedPanelId {
            PanelCropEditor(panelId: panelId)
        } else {
            CollagePreview()
        }
    }
}
```

### Column Visibility Control

```swift
@State private var columnVisibility = NavigationSplitViewVisibility.all

NavigationSplitView(columnVisibility: $columnVisibility) {
    // sidebar
} detail: {
    // detail
}
```

- `NavigationSplitViewVisibility.all` — show all columns
- `.detailOnly` — hide sidebar
- `.automatic` — system decides

### Column Width

```swift
// In sidebar column:
.navigationSplitViewColumnWidth(ideal: 250)
// Or with range:
.navigationSplitViewColumnWidth(min: 180, ideal: 250, max: 400)
```

## NSOpenPanel — Folder Browse

For selecting a folder of images:

```swift
let panel = NSOpenPanel()
panel.canChooseDirectories = true
panel.canChooseFiles = false
panel.allowsMultipleSelection = false

if panel.runModal() == .OK, let url = panel.url {
    // Load images from directory
    let fileManager = FileManager.default
    let files = try? fileManager.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [.isRegularFileKey]
    )
    // Filter for .jpg, .png files
}
```

## NSSavePanel — Export Dialog

```swift
let panel = NSSavePanel()
panel.allowedContentTypes = [.jpeg]
panel.nameFieldStringValue = "Cover.jpg"

if panel.runModal() == .OK, let url = panel.url {
    // Write JPEG data to url
    jpegData.write(to: url)
}
```

## Recommended UI Structure

```
NavigationSplitView {
    // LEFT: Image list / panel thumbnails
    ScrollView {
        LazyVStack {
            ForEach(images) { image in
                ImageThumbnail(image: image)
                    .onDrag(...)  // Enable reordering
            }
            .onDrop(of: [.image], ...)  // Accept external drops
        }
        .padding()
    }
    // Also include PhotosPicker and folder browse buttons
} detail: {
    // RIGHT: Collage editor
    VStack {
        // Live collage preview (scaled down)
        CollagePreviewView()

        // Selected panel crop controls
        if let selected = selectedPanel {
            PanelCropEditor(panel: selected)
        }

        // Export controls
        ExportPanel()
    }
}
```

## Key SwiftUI Types for Image Display

- `Image(nsImage:)` — display NSImage in SwiftUI
- `Image(decorative:sgImage:scale:)` — display CGImage
- `.resizable()` — make image resizable
- `.aspectRatio(contentMode: .fill)` — fill target rect
- `.clipped()` — clip to bounds
