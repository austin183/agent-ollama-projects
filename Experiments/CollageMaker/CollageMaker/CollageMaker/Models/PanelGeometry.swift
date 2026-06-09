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

    /// Computes the CGAffineTransform to convert a CGPath from canvas coordinates
    /// (CoreGraphics, origin=bottom-left) to SwiftUI view coordinates (origin=top-left).
    static func transformForPanel(boundingRect: CGRect, targetRect: CGRect) -> CGAffineTransform {
        guard boundingRect.width > 0, boundingRect.height > 0 else {
            return .identity
        }
        let scaleX = targetRect.width / boundingRect.width
        let scaleY = targetRect.height / boundingRect.height
        var t = CGAffineTransform(translationX: -boundingRect.origin.x * scaleX,
                                   y: boundingRect.origin.y * scaleY + targetRect.height)
        t = t.scaledBy(x: scaleX, y: -scaleY)
        return t
    }
}
