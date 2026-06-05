import AppKit
import CoreGraphics
import Foundation

struct ImageItem: Identifiable, Equatable {
    let id: UUID
    let cgImage: CGImage
    let thumbnail: NSImage
    let filename: String
    let size: CGSize

    var nsImage: NSImage {
        NSImage(cgImage: cgImage, size: size)
    }

    init(id: UUID = UUID(), cgImage: CGImage, thumbnail: NSImage, filename: String, size: CGSize) {
        self.id = id
        self.cgImage = cgImage
        self.thumbnail = thumbnail
        self.filename = filename
        self.size = size
    }

    static func == (lhs: ImageItem, rhs: ImageItem) -> Bool {
        lhs.id == rhs.id
    }
}
