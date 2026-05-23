import CoreGraphics
import Foundation

struct ImagePanel: Identifiable, Equatable {
    let id: UUID
    let imageIndex: Int
    let frame: CGRect

    init(id: UUID = UUID(), imageIndex: Int, frame: CGRect) {
        self.id = id
        self.imageIndex = imageIndex
        self.frame = frame
    }

    static func == (lhs: ImagePanel, rhs: ImagePanel) -> Bool {
        lhs.id == rhs.id
    }
}

struct CropInfo: Codable, Equatable {
    let panelId: UUID
    let sourceRect: CGRect
    let destinationRect: CGRect

    init(panelId: UUID, sourceRect: CGRect, destinationRect: CGRect) {
        self.panelId = panelId
        self.sourceRect = sourceRect
        self.destinationRect = destinationRect
    }
}
