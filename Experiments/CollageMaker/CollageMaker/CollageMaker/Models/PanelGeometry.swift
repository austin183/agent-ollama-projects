import CoreGraphics
import Foundation

/// Represents the shape of a panel — either a simple rectangle or an arbitrary CGPath.
///
/// `CGPath` is reference-type and not `Sendable`, but all paths are created on `@MainActor`
/// and only read on background threads for CoreGraphics drawing, making `@unchecked Sendable` safe.
enum PanelGeometry: @unchecked Sendable {
    case rect(CGRect)
    case path(cgPath: CGPath, boundingRect: CGRect)

    var boundingRect: CGRect {
        switch self {
        case .rect(let r): return r
        case .path(_, let r): return r
        }
    }

    var cgPath: CGPath? {
        switch self {
        case .rect(let r): return CGPath(rect: r, transform: nil)
        case .path(let p, _): return p
        }
    }
}
