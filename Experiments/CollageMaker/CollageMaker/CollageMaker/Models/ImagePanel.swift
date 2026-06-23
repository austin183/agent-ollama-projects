import CoreGraphics
import Foundation

struct ImagePanel: Identifiable, Equatable {
    let id: UUID
    let imageIndex: Int
    let geometry: PanelGeometry

    /// Backward-compatible accessor — returns bounding rect of geometry.
    var frame: CGRect { geometry.boundingRect }

    init(id: UUID = UUID(), imageIndex: Int, frame: CGRect) {
        self.id = id
        self.imageIndex = imageIndex
        self.geometry = .rect(frame)
    }

    init(id: UUID = UUID(), imageIndex: Int, geometry: PanelGeometry) {
        self.id = id
        self.imageIndex = imageIndex
        self.geometry = geometry
    }

    static func == (lhs: ImagePanel, rhs: ImagePanel) -> Bool {
        lhs.id == rhs.id
    }
}

struct CropInfo: Codable, Equatable {
    let panelId: UUID
    let sourceRect: CGRect
    let destination: PanelGeometry

    /// Backward-compatible accessor — returns bounding rect of destination.
    var destinationRect: CGRect { destination.boundingRect }

    init(panelId: UUID, sourceRect: CGRect, destinationRect: CGRect) {
        self.panelId = panelId
        self.sourceRect = sourceRect
        self.destination = .rect(destinationRect)
    }

    init(panelId: UUID, sourceRect: CGRect, destination: PanelGeometry) {
        self.panelId = panelId
        self.sourceRect = sourceRect
        self.destination = destination
    }

    enum CodingKeys: String, CodingKey {
        case panelId, sourceRect, destinationType, destinationRect, destinationPathVertices
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(panelId, forKey: .panelId)
        try container.encode(sourceRect, forKey: .sourceRect)
        switch destination {
        case .rect:
            try container.encode("rect" as String, forKey: .destinationType)
            try container.encode(destination.boundingRect, forKey: .destinationRect)
        case .path:
            try container.encode("path" as String, forKey: .destinationType)
            try container.encode(destination.boundingRect, forKey: .destinationRect)
            if let vertices = destination.pathVertices {
                try container.encode(vertices, forKey: .destinationPathVertices)
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        panelId = try container.decode(UUID.self, forKey: .panelId)
        sourceRect = try container.decode(CGRect.self, forKey: .sourceRect)
        let destRect = try container.decode(CGRect.self, forKey: .destinationRect)
        let destType = try container.decodeIfPresent(String.self, forKey: .destinationType) ?? "rect"
        if destType == "path" {
            let vertices = try container.decodeIfPresent([CGPoint].self, forKey: .destinationPathVertices)
            if let vertices, vertices.count >= 3 {
                destination = PanelGeometry.path(fromVertices: vertices, boundingRect: destRect)
            } else {
                destination = .path(cgPath: CGPath(rect: destRect, transform: nil), boundingRect: destRect)
            }
        } else {
            destination = .rect(destRect)
        }
    }

    static func == (lhs: CropInfo, rhs: CropInfo) -> Bool {
        lhs.panelId == rhs.panelId &&
        lhs.sourceRect == rhs.sourceRect &&
        lhs.destination.boundingRect == rhs.destination.boundingRect
    }
}
