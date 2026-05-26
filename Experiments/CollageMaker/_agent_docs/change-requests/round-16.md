there are several areas in CollageViewModel where memory management, main-thread blocking, and concurrency patterns can be modernized for better performance and stability. Since you're using @Observable and targeting Apple platforms, we can leverage modern Swift concurrency to clean this up significantly.

Here are the key optimizations:

1. Remove Manual objectWillChange Notifications
You highlighted objectWillChange.send(self). With the @Observable macro (Swift 5.9+), this is redundant and discouraged. The macro automatically synthesizes change tracking and injects objectWillChange for every property. Manually calling it can cause duplicate SwiftUI updates or interfere with the macro's diffing logic. Just remove it.

2. Fix Main-Thread Blocking I/O in addImages(from:)
Data(contentsOf:) is a synchronous function. Because CollageViewModel is marked @MainActor, calling it inside an async task still runs on the main thread, freezing the UI during image loading.
Fix: Use the async-native FileManager.default.contents(at:) and wrap heavy NSImage/CGContext work in Task.detached.

```
func addImages(from urls: [URL]) async {
    let newItems = await withTaskGroup(of: ImageItem?.self) { group in
        for url in urls {
            group.addTask {
                // 1. Async I/O instead of blocking synchronous Data(contentsOf:)
                let data = try? await FileManager.default.contents(at: url)
                guard let nsImage = NSImage(data: data),
                      let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

                // 2. Heavy pixel manipulation offloaded to a background thread
                let thumbnail = await Task.detached {
                    let thumbSize: CGSize = cgImage.width > cgImage.height 
                        ? CGSize(width: 64, height: CGFloat(cgImage.height) * 64 / CGFloat(cgImage.width))
                        : CGSize(width: CGFloat(cgImage.width) * 64 / CGFloat(cgImage.height), height: 64)

                    guard let context = CGContext(data: nil, width: Int(thumbSize.width), height: Int(thumbSize.height),
                                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
                    context.interpolationQuality = .high
                    context.draw(cgImage, in: CGRect(origin: .zero, size: thumbSize))
                    return context.makeImage().map { NSImage(cgImage: $0, size: thumbSize) }
                }.value

                return thumbnail.map {
                    ImageItem(nsImage: nsImage, cgImage: cgImage, thumbnail: $0, filename: url.lastPathComponent, size: CGSize(width: cgImage.width, height: cgImage.height))
                }
            }
        }
        // ... rest of group collection
    }
    // ...
}
```

3. Debounce persistence.save(self) in didSet
Every time a property changes (e.g., dragging a slider for gutter or gradientAngle), persistence.save(self) fires synchronously. This creates an I/O storm that can cause UI stutter and wear on storage.
Fix: Replace immediate saves with a debounced background task that batches updates.

```
private var saveDebounceTask: Task<Void, Never>?

private func debouncedSave() {
    saveDebounceTask?.cancel()
    saveDebounceTask = Task {
        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
        await persistence.save(self)
    }
}
```

Then replace all persistence.save(self) calls in your didSet blocks with debouncedSave().

4. Offload Heavy Computation from @MainActor
Methods like analyzeSaliency() and updatePreview() trigger heavy computer vision or rendering work. Even though updatePreview uses Task.detached, analyzeSaliency currently runs on the main actor because of Task { ... }. If saliencyAnalyzer.analyzeAll does heavy CV work, it will freeze the UI.
Fix: Use Task.detached for the entire heavy operation, or ensure the analyzer itself runs off the main thread.

```
func analyzeSaliency() async {
    guard !images.isEmpty else { return }
    isProcessing = true
    defer { isProcessing = false }

    // Offload the entire heavy analysis to a background thread
    let results = await Task.detached {
        try await self.saliencyAnalyzer.analyzeAll(self.images.map { $0.cgImage })
    }.value

    // Only update state on the main actor
    await MainActor.run {
        var indexed: [Int: SaliencyResult] = [:]
        for (i, result) in results.enumerated() { indexed[i] = result }
        self.saliencyResults = indexed
        self.cropManager.computeCropsFromSaliency(panels: self.panels, images: self.images, results: indexed)
        self.cropMap = self.cropManager.cropMap
        self.updatePreview()
    }
}
```

5. Modernize DispatchWorkItem Debouncing in applyPanLive()
DispatchWorkItem is legacy. Swift Concurrency provides a cleaner, safer cancellation model.
Fix: Replace with Task.sleep.

```
private var previewDebounceTask: Task<Void, Never>?

func applyPanLive() {
    cropManager.applyPan(panelId: nil, panels: panels, images: images, panelAssignments: panelAssignments, finish: false)
    cropMap = cropManager.cropMap

    previewDebounceTask?.cancel()
    previewDebounceTask = Task {
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
        await updatePreview()
    }
}
```

Summary of Impact
• UI Responsiveness: Eliminates main-thread blocking during image loading and CV analysis.
• Memory/Performance: Prevents I/O storms from rapid UI interactions via debouncing.
• Code Modernization: Replaces GCD DispatchWorkItem with structured concurrency Task.sleep, and removes redundant @Observable boilerplate.

These changes align with Apple's recommended patterns for @MainActor view models and will significantly smooth out interactions in your collage editor. 