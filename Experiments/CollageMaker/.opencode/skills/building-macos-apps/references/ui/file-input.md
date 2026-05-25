# File Input — Drag-and-Drop, PhotosPicker, NSOpenPanel, NSSavePanel

## Drag-and-Drop

```swift
.onDrop(of: [.jpeg, .png], isTargeted: $isDragging) { providers in
    for provider in providers {
        if provider.hasItemConformingToTypeIdentifier(.jpeg) {
            provider.loadDataRepresentation(forTypeIdentifier: .jpeg) { data, _ in
                if let data, let image = NSImage(data: data) {
                    // add image
                }
            }
        }
    }
    return true
}
```

## PhotosPicker (JPEG support)

- Load as `Data`, not `Image` — `Image` Transferable only exports PNG
- `item.loadTransferable(type: Data.self) { ... NSImage(data:) }`

## NSOpenPanel for Folder Browse

```swift
let panel = NSOpenPanel()
panel.canChooseDirectories = true
panel.canChooseFiles = false
if panel.runModal() == .OK, let url = panel.url { ... }
```

## NSSavePanel for Export

```swift
let panel = NSSavePanel()
panel.allowedContentTypes = [.jpeg]
panel.nameFieldStringValue = "Output.jpg"
let response = NSApplication.shared.runModal(for: panel)
if response == .OK, let url = panel.url { ... }
```
