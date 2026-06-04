import Foundation
import OSLog
import UniformTypeIdentifiers

private let logger = Logger(
    subsystem: "austin183.indie.CollageMaker",
    category: "DropHandler"
)

struct DropHandler {
    private let imageTypes: [UTType]

    init() {
        self.imageTypes = [.jpeg, .png, .tiff, .heic, .heif]
    }

    func loadImageURLs(from itemProviders: [NSItemProvider]) async -> [URL] {
        let loadedUrls = await withTaskGroup(of: URL?.self) { group in
            for provider in itemProviders {
                group.addTask {
                    await self.extractURL(from: provider)
                }
            }

            var urls: [URL] = []
            for await url in group {
                if let url { urls.append(url) }
            }
            return urls
        }

        return loadedUrls
    }

    private func extractURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }

        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, error in
                if let error {
                    logger.error("Load file URL error: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                    return
                }

                var url: URL?
                if let data = item as? Data,
                   let urlStr = String(data: data, encoding: .utf8) {
                    url = URL(string: urlStr)
                    if let u = url, !u.isFileURL, u.absoluteString.hasPrefix("file://") {
                        url = URL(fileURLWithPath: String(urlStr.dropFirst(7)))
                    }
                } else if let nsurl = item as? NSURL {
                    url = nsurl as URL
                }

                if let url, url.isFileURL {
                    let ext = url.pathExtension
                    if let uti = UTType(filenameExtension: ext),
                       imageTypes.contains(uti) {
                        continuation.resume(returning: url)
                    } else {
                        logger.error("Unsupported type: \(ext, privacy: .public)")
                        continuation.resume(returning: nil)
                    }
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
