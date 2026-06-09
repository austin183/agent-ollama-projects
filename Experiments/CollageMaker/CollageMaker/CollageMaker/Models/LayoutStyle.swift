import CoreGraphics
import SwiftUI

/// Strategy-specific parameters for layout generation.
/// New layouts read only the properties they need — adding a parameter
/// for one strategy does not affect the signature of callers.
struct LayoutOptions {
    var sliceAngle: CGFloat = 45.0
    var hexSpacing: CGFloat = 8.0

    /// Required — Swift does not synthesize a parameterless init when a custom init is present.
    init() {}
    init(sliceAngle: CGFloat, hexSpacing: CGFloat) {
        self.sliceAngle = sliceAngle
        self.hexSpacing = hexSpacing
    }
}

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
