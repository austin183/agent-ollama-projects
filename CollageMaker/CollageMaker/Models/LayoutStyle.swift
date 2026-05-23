import SwiftUI

enum LayoutStyle: String, CaseIterable, Identifiable, Codable {
    case uniform
    case hero
    case mosaic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uniform: "Uniform"
        case .hero: "Hero"
        case .mosaic: "Mosaic"
        }
    }

    var icon: String {
        switch self {
        case .uniform: "square.grid.2x2.fill"
        case .hero: "rectangle.stack.fill"
        case .mosaic: "photo.on.rectangle.angled"
        }
    }
}
