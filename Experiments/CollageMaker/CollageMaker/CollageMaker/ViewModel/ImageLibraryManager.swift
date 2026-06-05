import AppKit
import Foundation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

private let logger = Logger(
    subsystem: "austin183.indie.CollageMaker",
    category: "ImageLibrary"
)

@MainActor
@Observable
final class ImageLibraryManager {
    var images: [ImageItem] = []
    var customImageOrder: [Int] = []

    var onImagesChanged: (() -> Void)?

    func browseImages() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.jpeg, .png, .tiff, .heic, .heif]

        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            if response == .OK {
                Task { [weak self] in
                    await self?.addImages(from: panel.urls)
                }
            }
        }
    }

    func addImages(from urls: [URL]) async {
        let newItems = await withTaskGroup(of: ImageItem?.self) { group in
            for url in urls {
                group.addTask {
                    guard let data = FileManager.default.contents(atPath: url.path) else { return nil }

                    let imagePair = await MainActor.run { () -> (NSImage, CGImage)? in
                        guard let nsImage = NSImage(data: data),
                              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                            return nil
                        }
                        return (nsImage, cgImage)
                    }
                    guard let (_, cgImage) = imagePair else { return nil }

                    let thumbSize: CGSize
                    if cgImage.width > cgImage.height {
                        thumbSize = CGSize(width: 64, height: CGFloat(cgImage.height) * 64 / CGFloat(cgImage.width))
                    } else {
                        thumbSize = CGSize(width: CGFloat(cgImage.width) * 64 / CGFloat(cgImage.height), height: 64)
                    }

                    guard let context = CGContext(
                        data: nil,
                        width: Int(thumbSize.width),
                        height: Int(thumbSize.height),
                        bitsPerComponent: 8,
                        bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                    ) else { return nil }

                    context.interpolationQuality = .high
                    context.draw(cgImage, in: CGRect(origin: .zero, size: thumbSize))

                    guard let drawnCG = context.makeImage() else { return nil }
                    let thumbnail = NSImage(cgImage: drawnCG, size: thumbSize)

                    return ImageItem(
                        cgImage: cgImage,
                        thumbnail: thumbnail,
                        filename: url.lastPathComponent,
                        size: CGSize(width: cgImage.width, height: cgImage.height)
                    )
                }
            }

            var items: [ImageItem] = []
            for await item in group {
                if let item { items.append(item) }
            }
            return items
        }

        guard !newItems.isEmpty else { return }
        images.append(contentsOf: newItems)
        logger.info("Added \(newItems.count) image(s); total count \(self.images.count)")
        onImagesChanged?()
    }

    func removeImage(at index: Int) -> (item: ImageItem, at: Int)? {
        guard index < images.count else { return nil }
        let removed = images[index]
        images.remove(at: index)
        return (removed, index)
    }

    func moveImages(from: IndexSet, to: Int) {
        let first = from.first
        let last = from.last
        let count = images.count

        if let first, let last, !customImageOrder.isEmpty {
            let oldPos = buildMoveMapping(fromFirst: first, fromLast: last, to: to, count: count)
            customImageOrder = customImageOrder.map { customImageOrder[oldPos[$0]] }
        }

        images.move(fromOffsets: from, toOffset: to)
        onImagesChanged?()
    }

    func clearAll() -> [ImageItem] {
        let oldImages = images
        images.removeAll()
        customImageOrder.removeAll()
        return oldImages
    }

    private func buildMoveMapping(fromFirst: Int, fromLast: Int, to: Int, count: Int) -> [Int] {
        var oldPos = Array(0..<count)

        guard to != fromFirst else { return oldPos }

        if to < fromFirst {
            oldPos[to] = fromLast
            for i in to..<fromLast {
                oldPos[i + 1] = i
            }
        } else {
            oldPos[to] = fromFirst
            for i in (fromFirst + 1)...to {
                oldPos[i - 1] = i
            }
        }

        return oldPos
    }
}
