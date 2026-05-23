# Drag and Drop

SwiftUI drag-and-drop APIs for reordering, cross-view transfer, and external content import.

## API Tiers

| Use Case | API | macOS |
|----------|-----|-------|
| Reorder items in a List | `onMove(perform:)` | 10.15+ |
| Drag Transferable items between views | `draggable(_:)` + `dropDestination(for:action:)` | 15+ |
| Drag raw data (images from Finder) | `onDrag`/`onDrop` with `NSItemProvider` | 11+ |
| Custom canvas drop zones with feedback | `onDrop(of:isTargeted:perform:)` | 11+ |
| Fine-grained drop control | `onDrop(of:delegate:)` + `DropDelegate` | 11+ |

## List Reordering with `onMove`

Simplest approach — no `Transferable` conformance needed. Only works on `DynamicViewContent` inside `List` or `OutlineGroup`.

```swift
List {
    ForEach(images) { image in
        ImageThumbnail(image: image)
    }
    .onMove { from, to in
        images.move(fromOffsets: from, toOffset: to)
    }
}
```

Disable reordering for specific rows with `.moveDisabled(true)`. Pass `nil` to disable entirely.

## Modern Transferable API

### Making a Type Transferable

```swift
extension CollageImage: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .collageImage)
    }
}

extension UTType {
    static var collageImage = UTType(exportedAs: "com.collagemaker.image")
}
```

`CodableRepresentation` auto-serializes `Codable` types. Use `DataRepresentation` for manual encoding or `ProxyRepresentation` for fallback to simpler types.

Built-in `Transferable` types: `String`, `Data`, `URL`, `Image`.

### Drag Source

```swift
ImageThumbnail(image: image)
    .draggable(image) {
        ThumbnailView(image: image)  // Custom drag preview
    }
```

Without the preview closure, SwiftUI uses a snapshot of the source view.

### Drop Destination

```swift
RoundedRectangle(cornerRadius: 8)
    .dropDestination(for: CollageImage.self) { images, location in
        for image in images {
            viewModel.assignImage(image, to: panelIndex)
        }
        return true
    }
```

The `action` closure receives `[T]` dropped items and `CGPoint` drop location. On `List`/`Table`, `CGPoint` is replaced with `Int` index.

### Move vs Insert Logic

When a dropped item may already exist in the destination (e.g., reordering between panels):

```swift
.dropDestination(for: CollageImage.self) { images, location in
    guard let image = images.first else { return false }

    if let existing = viewModel.findImage(image) {
        viewModel.moveImage(existing, to: panelIndex)
    } else {
        viewModel.assignImage(image, to: panelIndex)
    }
    return true
}
```

## Legacy NSItemProvider API

### Drag Source

```swift
Text(name)
    .onDrag {
        NSItemProvider(object: name as NSString)
    } preview: {
        Text(name).background(Color.yellow)
    }
```

### Drop Destination with Targeting Feedback

```swift
@State private var isTargeted = false

var body: some View {
    RoundedRectangle(cornerRadius: 8)
        .fill(isTargeted ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2))
        .onDrop(of: [.text], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: kUTTypeText as String) { data, _ in
                if let data = data as? Data,
                   let text = String(data: data, encoding: .utf8) {
                    // handle dropped text
                }
            }
            return true
        }
}
```

### Finder Drag Gotcha

Finder drag payloads send `public.file-url`, not the content type of the file. To accept files dragged from Finder:

```swift
.onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
  guard let provider = providers.first,
        let item = try? await provider.loadItem(
          forTypeIdentifier: UTType.fileURL.identifier
        ) as? Data else { return false }

  let url: URL
  if let data = item as? Data,
     let string = String(data: data, encoding: .utf8),
     let urlStr = CFURLCreateStringByReplacingPercentEscapes(
       kCFAllocatorDefault, string as CFString, nil
    ) {
    url = URL(string: urlStr as String)!
  } else if let nsurl = item as? NSURL {
    url = nsurl as URL
  } else {
    return false
  }

  // Validate extension after extraction
  guard ["jpg", "jpeg", "png"].contains(url.pathExtension.lowercased()) else {
    return false
  }

  // Process url...
  return true
}
```

**Key points:**
- **Accept `UTType.fileURL.identifier`** for Finder drags -- filtering for `public.jpeg`/`public.png` won't match
- **`NSItemProvider` payload types vary** -- the extracted item can be `Data` (UTF-8 URL string) or `NSURL`; handle both
- **Validate file extension after extraction** -- the UTI is `file-url`, not the content type

## Advanced: DropDelegate

For per-item processing, session-level tracking, or custom drop operations:

```swift
class MyDropDelegate: DropDelegate {
    func performDrop(info: DropInfo) -> Bool {
        // Full control over drop processing
        return true
    }

    func dropSessionDidUpdate(session: DropSession, info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }
}
```

Use `onDrop(of: [.text], delegate: MyDropDelegate())`.

## DynamicViewContent Modifiers

Available on `ForEach`/`Section`:

| Modifier | Purpose |
|----------|---------|
| `onMove(perform:)` | Reorder within collection |
| `onDelete(perform:)` | Delete items (called AFTER visual removal) |
| `onInsert(of:perform:)` | Handle external `NSItemProvider` insertion |
| `dropDestination(for:action:)` | Handle `Transferable` drops (takes `Int` index) |

## UTType Registration

Custom UTTypes must be declared in `Info.plist` under `UTExportedTypeDeclarations`:

```xml
<key>UTExportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeIdentifier</key>
        <string>com.collagemaker.image</string>
        <key>UTTypeConformsTo</key>
        <array>
            <string>com.apple.property-list</string>
        </array>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array>
                <string>collageimage</string>
            </array>
        </dict>
    </dict>
</array>
```

Without this, cross-app drag-and-drop with your custom type will fail.

## Gotchas

- **`onMove` requires `List`/`OutlineGroup`** — Does not work on arbitrary `ForEach` blocks. For custom canvas layouts, use `onDrag`/`onDrop` or `draggable`/`dropDestination`.
- **`onDelete` fires after visual removal** — Delete from your data source inside the closure.
- **`Transferable` requires macOS 15+** — Use `NSItemProvider` for earlier targets.
- **Multiple item drags** — Both APIs support dragging multiple items. Action closures receive arrays.
- **`.contentShape(.dragPreview, shape)`** — Controls the lift preview shape (the ghost following the cursor). Separate from the `draggable(_:preview:)` closure.

## Pitfalls

- **`.onDrop(of:)` UTI mismatch with Finder** — Filtering for `public.jpeg`/`public.png` doesn't match Finder drag payloads. Accept `UTType.fileURL.identifier` and validate extension after extraction
- **`NSItemProvider` payload type varies** — File URL payloads can be `Data` (UTF-8 string) or `NSURL`. Handle both in `loadItem(forTypeIdentifier:)`

## HIG: Drag and Drop Semantics

### Move vs. Copy

| Context | Behavior |
|---|---|
| Same container (panel to panel) | **Move** — swap images |
| Different container (sidebar to canvas) | **Copy** — don't remove from sidebar |
| Between apps (Finder to app) | **Copy** — always |

### Visual Feedback

```swift
@State private var isTargeted = false

PanelView(panel: panel)
    .overlay {
        if isTargeted {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor, lineWidth: 2)
                .fill(Color.accentColor.opacity(0.1))
        }
    }
    .onDrop(of: [.text], isTargeted: $isTargeted) { providers in
        // handle drop
    }
```

- **Highlight target** when dragging over valid destination
- **Show `circle.slash`** for invalid drop targets
- **Only highlight while content is above destination**
- **Identify one destination at a time** when multiple exist

### Option Key for Copy

Check for Option key at drop time to force copy within same container:

```swift
.dropDestination(for: CollageImage.self) { images, location in
    let event = NSApp.currentEvent
    let isCopy = event?.modifierFlags.contains(.option) == true

    if isCopy {
        viewModel.copyImage(images.first!, to: panelIndex)
    } else {
        viewModel.moveImage(images.first!, to: panelIndex)
    }
    return true
}
```

### Undo Support

Register undo before completing drop operations:

```swift
.dropDestination(for: CollageImage.self) { images, location in
    guard let image = images.first else { return false }
    let oldIndex = viewModel.panelIndex(for: image)

    viewModel.undoManager.registerUndo(withTarget: viewModel) { target in
        target.assignImage(image, to: oldIndex)
    }
    viewModel.undoManager.setActionName("Move Image")
    viewModel.assignImage(image, to: panelIndex)
    return true
}
```

### Rules

- **Support throughout the app** — users will try drag and drop everywhere
- **Offer alternatives** — context menu "Replace Image", sidebar "Remove" for users who can't drag
- **Support multi-item drag** — show badge with item count during multi-image drops
- **Let people undo** — sometimes drops land in wrong destinations
- **Auto-scroll destination** when dragging over scrolling containers
