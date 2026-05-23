import AppKit
import CoreGraphics
import Foundation

struct ImageItem: Identifiable, Equatable {
    let id: UUID
    let nsImage: NSImage
    let cgImage: CGImage
    let thumbnail: NSImage
    let filename: String
    let size: CGSize

    init(id: UUID = UUID(), nsImage: NSImage, cgImage: CGImage, thumbnail: NSImage, filename: String, size: CGSize) {
        self.id = id
        self.nsImage = nsImage
        self.cgImage = cgImage
        self.thumbnail = thumbnail
        self.filename = filename
        self.size = size
    }

    static func == (lhs: ImageItem, rhs: ImageItem) -> Bool {
        lhs.id == rhs.id
    }
}
