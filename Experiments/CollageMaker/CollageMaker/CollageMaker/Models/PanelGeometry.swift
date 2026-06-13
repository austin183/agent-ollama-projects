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

    var isRect: Bool {
        if case .rect = self { return true }
        return false
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

    static func extractPathPoints(_ cgPath: CGPath) -> [CGPoint] {
        class PointCollector { var points: [CGPoint] = [] }
        let collector = PointCollector()
        cgPath.apply(info: Unmanaged.passUnretained(collector).toOpaque()) { info, element in
            let c = Unmanaged<PointCollector>.fromOpaque(info!).takeUnretainedValue()
            let elem = element.pointee
            switch elem.type {
            case .moveToPoint:
                c.points.append(elem.points.pointee)
            case .addLineToPoint:
                c.points.append(elem.points.pointee)
            case .addQuadCurveToPoint:
                c.points.append(elem.points.pointee)
                c.points.append(elem.points.advanced(by: 1).pointee)
            case .addCurveToPoint:
                c.points.append(elem.points.pointee)
                c.points.append(elem.points.advanced(by: 1).pointee)
                c.points.append(elem.points.advanced(by: 2).pointee)
            case .closeSubpath:
                break
            @unknown default:
                break
            }
        }
        return collector.points
    }
}
