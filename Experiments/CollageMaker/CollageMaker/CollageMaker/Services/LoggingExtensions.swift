import CoreGraphics
import Foundation

struct DebugHelpers {
    static func rectStr(_ r: CGRect) -> String {
        String(format: "(\(Int(r.origin.x)),\(Int(r.origin.y))) \(Int(r.width))x\(Int(r.height))")
    }

    static func pointStr(_ p: CGPoint) -> String {
        String(format: "(\(Int(p.x)),\(Int(p.y)))")
    }

    static func sizeStr(_ s: CGSize) -> String {
        String(format: "\(Int(s.width))x\(Int(s.height))")
    }
}
