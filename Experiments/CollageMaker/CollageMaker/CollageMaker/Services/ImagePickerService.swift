import AppKit
import UniformTypeIdentifiers

/// Abstracts NSOpenPanel-based image selection so views and tests
/// do not depend on AppKit directly.
protocol ImagePicker: Sendable {
    func pickImage(allowedTypes: [UTType]) async -> (image: NSImage?, path: String?)
}

/// Production implementation that presents an NSOpenPanel on the main thread.
final class DefaultImagePicker: ImagePicker {
    @MainActor
    func pickImage(allowedTypes: [UTType]) async -> (image: NSImage?, path: String?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = allowedTypes

        NSApplication.shared.activate(ignoringOtherApps: true)

        return await withCheckedContinuation { continuation in
            panel.begin { response in
                guard response == .OK, let url = panel.url else {
                    continuation.resume(returning: (nil, nil))
                    return
                }

                guard let data = try? Data(contentsOf: url),
                      let image = NSImage(data: data) else {
                    continuation.resume(returning: (nil, nil))
                    return
                }

                continuation.resume(returning: (image, url.path))
            }
        }
    }
}
