import Foundation

enum BackgroundStyle: String, CaseIterable, Identifiable, Codable {
    case solid, gradient, image

    var id: String { rawValue }
}
