import SwiftUI

enum LayoutStyle: String, CaseIterable, Identifiable, Codable {
    case uniform
    case hero
    case mosaic
    case doubleExposure
    case diagonalSlices
    case hexagonal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uniform: "Uniform"
        case .hero: "Hero"
        case .mosaic: "Mosaic"
        case .doubleExposure: "Double Exposure"
        case .diagonalSlices: "Diagonal Slices"
        case .hexagonal: "Hexagonal"
        }
    }

    var icon: String {
        switch self {
        case .uniform: "square.grid.2x2.fill"
        case .hero: "rectangle.stack.fill"
        case .mosaic: "photo.on.rectangle.angled"
        case .doubleExposure: "person.crop.circle.fill"
        case .diagonalSlices: "line.3.horizontal.decrease"
        case .hexagonal: "hexagon.fill"
        }
    }

}
