# File Export and Import

## File Export with `.fileExporter`

```swift
Button("Export…") { isShowingExport = true }
.fileExporter(
    isPresented: $isShowingExport,
    document: exportDocument,
    contentType: .png
) { result in
    switch result {
    case .success(let url): print("Saved to \(url)")
    case .failure(let error): print("Export failed: \(error)")
    @unknown default: break
    }
}
```

The `document` parameter must conform to `ReferenceFileDocument` (one-way export) or `FileDocument` (open/save).

## Importing External Content

```swift
.importsItemProviders(selection.isEmpty ? [] : UTType.image.types) { providers in
    for provider in providers {
        if let url = try? await provider.loadItem(
            forTypeIdentifier: UTType.image.identifier
        ) as? URL {
            viewModel.addImage(from: url)
        }
    }
}
```

Conditionally disable import by passing empty array when no selection exists.

## Drag-and-Drop Reference

For full drag-and-drop patterns (Transferable API, onMove reordering, NSItemProvider, Finder drag extraction), see [../gestures/drag-and-drop.md](../gestures/drag-and-drop.md).
