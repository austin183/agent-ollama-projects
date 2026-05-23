# SwiftUI Drag and Drop Research

> Source: Apple Developer Documentation — "Adopting drag and drop using SwiftUI", "Making a view into a drag source", "onMove(perform:)"
> Date: 2026-05-11

---

## Summary

SwiftUI provides two distinct drag-and-drop API tiers:

1. **Modern Transferable API (iOS 18+/macOS 15+)** — `draggable(_:)` + `dropDestination(for:action:isTargeted:)` with the `Transferable` protocol. Declarative, type-safe, handles serialization/deserialization automatically via `TransferRepresentation`.

2. **Legacy NSItemProvider API** — `onDrag(_:preview:)` + `onDrop(of:isTargeted:perform:)` with `NSItemProvider`. Lower-level, gives direct access to raw item providers and UTType identifiers.

3. **List Reordering** — `onMove(perform:)` for in-place reordering within a `List`. Simplest approach, no drag-and-drop plumbing needed.

For CollageMaker, the **Transferable API** is the recommended approach for both sidebar reordering and canvas drop handling, with `onMove` as a simpler alternative for sidebar-only reordering.

---

## API Tier 1: Modern Transferable API

### Drag Source: `draggable(_:preview:)`

Make any view a drag source by adding the `draggable(_:)` modifier. The dragged value must conform to `Transferable`.

```swift
List {
    ForEach(dataModel.contacts) { contact in
        NavigationLink {
            ContactDetailView(contact: contact)
        } label: {
            CompactContactView(contact: contact)
                .draggable(contact) {
                    ThumbnailView(contact: contact)
                }
        }
    }
}
```

The `preview` closure provides a custom view shown while dragging. Without it, SwiftUI uses a snapshot of the source view.

**Customizing the lift preview shape:**

```swift
Text(name)
    .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 7))
    .draggable(name) {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .frame(width: 300, height: 300)
                .foregroundStyle(.yellow.gradient)
            Text("Drop \(name)")
                .font(.title)
                .foregroundStyle(.red)
        }
    }
```

### Drop Destination: `dropDestination(for:action:isTargeted:)`

```swift
.dropDestination(for: Contact.self) { droppedContacts, index in
    dataModel.handleDroppedContacts(
        droppedContacts: droppedContacts,
        index: index
    )
}
```

The `action` closure receives:
- `[T]` — array of dropped items of type `T` (must conform to `Transferable`)
- `CGPoint` — drop location on the view (for custom views). For `List`/`Table`, this is replaced with `Int` index.

### Conforming to `Transferable`

The `Transferable` protocol requires implementing `transferRepresentation`, a static property that composes one or more `TransferRepresentation` types:

```swift
extension Contact: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        // 1. Custom content type (highest priority)
        CodableRepresentation(contentType: .exampleContact)

        // 2. Standard vCard format for interoperability
        DataRepresentation(contentType: .vCard) { contact in
            try contact.toVCardData()
        } importing: { data in
            try await parseVCardData(data)
        }
        .suggestedFileName { $0.fullName }

        // 3. Fallback: phone number as plain text
        ProxyRepresentation { contact in
            contact.phoneNumber
        } importing: { value in
            Contact(
                id: UUID().uuidString,
                givenName: value,
                familyName: "",
                phoneNumber: ""
            )
        }
    }
}
```

**TransferRepresentation types (in priority order):**

| Type | Purpose |
|------|---------|
| `CodableRepresentation` | Auto-serializes `Codable` types with a custom UTType |
| `DataRepresentation` | Manual `Data` encoding/decoding with a UTType |
| `ProxyRepresentation` | Falls back to a simpler type (e.g., `String`) for broad compatibility |

### Built-in Transferable Types

`String`, `Data`, `URL`, and `Image` already conform to `Transferable`, requiring no additional work.

### Handling Dropped Items (Move vs. Insert)

```swift
func handleDroppedContacts(droppedContacts: [Contact], index: Int? = nil) {
    guard let firstContact = droppedContacts.first else { return }

    // If the contact already exists in the list, MOVE it
    if let existingIndex = contacts.firstIndex(where: { $0.id == firstContact.id }) {
        let indexSet = IndexSet(integer: existingIndex)
        contacts.move(fromOffsets: indexSet, toOffset: index ?? contacts.endIndex)
    } else {
        // Otherwise, INSERT it as new
        contacts.insert(firstContact, at: index ?? contacts.endIndex)
    }
}
```

### Custom UTType Declaration

```swift
import UniformTypeIdentifiers

extension UTType {
    static var profile = UTType(exportedAs: "com.example.profile")
}
```

Must also be declared in the app's `Info.plist` under `UTExportedTypeDeclarations`.

---

## API Tier 2: Legacy NSItemProvider API

### Drag Source: `onDrag(_:preview:)`

```swift
struct MyView: View {
    let name = "Mei Chen"

    var body: some View {
        Text(name)
            .onDrag {
                NSItemProvider(object: name as NSString)
            } preview: {
                Text(name)
                    .background(Color.yellow)
            }
    }
}
```

### Drop Destination: `onDrop(of:isTargeted:perform:)`

```swift
.onDrop(of: [.text], isTargeted: isTargeted) { providers in
    guard let provider = providers.first else { return false }

    provider.loadItem(forTypeIdentifier: kUTTypeText as String) { data, error in
        if let data = data as? Data,
           let text = String(data: data, encoding: .utf8) {
            // handle dropped text
        }
    }
    return true
}
```

### Drop Destination with Delegate: `onDrop(of:delegate:)`

For advanced scenarios (e.g., per-item processing, session-level tracking):

```swift
.onDrop(of: [.text], delegate: MyDropDelegate())
```

Where `MyDropDelegate` conforms to `DropDelegate`:

```swift
class MyDropDelegate: DropDelegate {
    func performDrop(info: DropInfo) -> Bool {
        // Full control over drop processing
        return true
    }

    func dropSessionDidUpdate(session: DropSession, info: DropInfo) -> DropProposal? {
        // Customize drop behavior per session
        DropProposal(operation: .copy)
    }
}
```

**Key types:**
- `DropInfo` — provides item providers, location, and proposed operation
- `DropProposal` — specifies the drop operation (`.copy`, `.move`, `.link`, `.forbidden`)
- `DropOperation` — enum of allowed operations
- `DropSession` / `DragSession` — session-level tracking

---

## API Tier 3: List Reordering with `onMove(perform:)`

The simplest approach for reordering items within a `List`. Available since macOS 10.15.

```swift
List {
    ForEach(profiles) { profile in
        Text(profile.name)
    }
    .onMove { indices, newOffset in
        profiles.move(fromOffsets: indices, toOffset: newOffset)
    }
}
```

**Parameters:**
- `indices: IndexSet` — source indices being moved
- `newOffset: Int` — destination index

**Disabling reordering for specific rows:**

```swift
Text(profile.name)
    .moveDisabled(true)  // This row cannot be moved
```

**Passing `nil` disables reordering entirely:**

```swift
.onMove(nil)  // No reordering allowed
```

---

## DynamicViewContent Modifiers

`DynamicViewContent` (conformed by `ForEach`, `Section`) provides these modifiers:

| Modifier | Purpose |
|----------|---------|
| `onMove(perform:)` | Reorder items within the collection |
| `onDelete(perform:)` | Delete items (called AFTER visual removal) |
| `onInsert(of:perform:)` | Handle external item insertion via `NSItemProvider` |
| `dropDestination(for:action:)` | Handle `Transferable` item drops (takes `Int` index) |

---

## CollageMaker Applicability

### 1. Sidebar Image Reordering

**Recommended: `onMove(perform:)`** — simplest, no `Transferable` conformance needed.

```swift
struct Sidebar: View {
    @Binding var images: [CollageImage]

    var body: some View {
        List {
            ForEach(images) { image in
                ImageThumbnail(image: image)
            }
            .onMove { from, to in
                images.move(fromOffsets: from, toOffset: to)
            }
        }
    }
}
```

**Alternative: `draggable` + `dropDestination`** — if you also want drag from sidebar to canvas:

```swift
ForEach(images) { image in
    ImageThumbnail(image: image)
        .draggable(image)
}
.onMove { from, to in
    images.move(fromOffsets: from, toOffset: to)
}
```

### 2. Drag from Sidebar to Canvas (Panel Assignment)

**Recommended: `draggable` + `dropDestination` with `Transferable`**

Make `CollageImage` conform to `Transferable`:

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

Canvas panels become drop destinations:

```swift
struct CanvasPanel: View {
    let panelIndex: Int
    @EnvironmentObject var collageModel: CollageModel

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.2))
            .dropDestination(for: CollageImage.self) { images, location in
                for image in images {
                    collageModel.assignImage(to: panelIndex, at: location)
                }
                return true
            }
    }
}
```

### 3. Drag from Finder to Canvas

Use `DataRepresentation` with `UTType.image` to accept images from outside the app:

```swift
extension CollageImage: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .image) { image in
            try image.pngData()!
        } importing: { data in
            CollageImage(nsImage: NSImage(data: data)!)
        }
    }
}
```

### 4. Drag Reordering on Canvas (Between Panels)

Use `dropDestination` on each panel with move-vs-insert logic:

```swift
.dropDestination(for: CollageImage.self) { images, location in
    guard let image = images.first else { return false }

    // Check if image is already on canvas (move) vs. from sidebar (insert)
    if let existing = collageModel.findImage(image) {
        collageModel.moveImage(existing, to: panelIndex, at: location)
    } else {
        collageModel.assignImage(image, to: panelIndex, at: location)
    }
    return true
}
```

---

## macOS-Specific Considerations and Gotchas

### 1. `onMove` Requires `List` or `OutlineGroup`

`onMove(perform:)` only works on `DynamicViewContent` inside a `List` or `OutlineGroup`. It does not work on arbitrary `ForEach` blocks. For custom canvas layouts, use `onDrag`/`onDrop` or `draggable`/`dropDestination` instead.

### 2. macOS Uses Mouse, Not Touch

On macOS, drag operations are initiated by click-and-drag, not long-press. The system handles the gesture recognition. However, the visual feedback (preview, cursor changes) is the same.

### 3. `NSItemProvider` vs `Transferable`

- `Transferable` is the modern approach but requires macOS 15+ / Xcode 16+
- `NSItemProvider` (`onDrag`/`onDrop`) works on macOS 10.15+
- `dropDestination(for:action:isTargeted:)` with `CGPoint` is **deprecated** in favor of the `DynamicViewContent` variant that takes `Int` index

### 4. UTType Registration

Custom UTTypes must be declared in the app's `Info.plist` under `UTExportedTypeDeclarations`. Without this, cross-app drag-and-drop with your custom type will fail. The UTType should conform to `UTType.data`, `UTType.package`, or a subtype thereof.

### 5. `onDelete` vs `onMove` Timing

`onDelete(perform:)` is called **after** the row is visually removed from the `List`. You must delete from your data source inside the closure. `onMove(perform:)` is called when the user releases the dragged item at its new position.

### 6. `moveDisabled(_:)` for Conditional Reordering

Use `.moveDisabled(true)` on individual rows to prevent them from being moved. Useful for pinned items, headers, or locked panels.

### 7. Content Shape for Drag Preview

Use `.contentShape(.dragPreview, shape)` to control the shape of the lift preview (the ghost image that follows the cursor). This is separate from the custom preview closure in `draggable(_:preview:)`.

### 8. Drop Targeting Feedback

The `isTargeted` parameter in `onDrop(of:isTargeted:perform:)` provides a binding that is `true` while the dragged item is hovering over the drop zone. Use this to show visual feedback:

```swift
@State private var isTargeted = false

var body: some View {
    RoundedRectangle(cornerRadius: 8)
        .fill(isTargeted ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2))
        .onDrop(of: [.text], isTargeted: $isTargeted) { providers in
            // handle drop
            return true
        }
}
```

### 9. Multiple Item Drags

Both APIs support dragging multiple items. The action closures receive arrays (`[T]` or `[NSItemProvider]`). Handle accordingly.

### 10. `DropDelegate` for Fine-Grained Control

When `onDrop(of:isTargeted:perform:)` isn't enough, use `onDrop(of:delegate:)` with a custom `DropDelegate` to:
- Control the drop operation per session (`.copy`, `.move`, `.link`)
- Process items individually with full `DropInfo` access
- Handle session-level updates via `dropSessionDidUpdate`

---

## Quick Reference: Which API to Use

| Use Case | Recommended API |
|----------|----------------|
| Reorder items in a `List` | `onMove(perform:)` |
| Drag `Transferable` items between views/apps | `draggable(_:)` + `dropDestination(for:action:)` |
| Drag raw data (images from Finder) | `draggable` + `DataRepresentation` or `onDrag`/`onDrop` with `NSItemProvider` |
| Custom canvas drop zones with visual feedback | `onDrop(of:isTargeted:perform:)` or `dropDestination(for:action:isTargeted:)` |
| Fine-grained drop control (per-session, per-item) | `onDrop(of:delegate:)` with `DropDelegate` |
| Cross-app compatibility with older macOS | `onDrag`/`onDrop` with `NSItemProvider` |
