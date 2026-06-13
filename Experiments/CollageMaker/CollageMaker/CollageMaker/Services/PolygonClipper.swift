import CoreGraphics

/// Pure struct — Sutherland-Hodgman polygon clipping against an axis-aligned rectangle.
struct PolygonClipper {
    /// Clips a subject polygon to the given clipping rectangle.
    /// Returns the clipped polygon vertices, or an empty array if fully outside.
    static func clip(_ subject: [CGPoint], to clipRect: CGRect) -> [CGPoint] {
        guard !subject.isEmpty else { return [] }

        var result = subject
        result = clipEdge(result, respect: .left(clipRect.minX))
        result = clipEdge(result, respect: .right(clipRect.maxX))
        result = clipEdge(result, respect: .top(clipRect.minY))
        result = clipEdge(result, respect: .bottom(clipRect.maxY))
        return result
    }

    private static func clipEdge(_ input: [CGPoint], respect: ClipEdge) -> [CGPoint] {
        guard !input.isEmpty else { return [] }
        var output: [CGPoint] = []
        var prev = input[input.count - 1]
        var prevInside = respect.isInside(prev)

        for curr in input {
            let currInside = respect.isInside(curr)
            if currInside {
                if !prevInside {
                    if let intersect = respect.intersection(from: prev, to: curr) {
                        output.append(intersect)
                    }
                }
                output.append(curr)
            } else if prevInside {
                if let intersect = respect.intersection(from: prev, to: curr) {
                    output.append(intersect)
                }
            }
            prev = curr
            prevInside = currInside
        }
        return output
    }

    private enum ClipEdge {
        case left(CGFloat), right(CGFloat), top(CGFloat), bottom(CGFloat)

        func isInside(_ p: CGPoint) -> Bool {
            switch self {
                case .left(let x): return p.x >= x
                case .right(let x): return p.x <= x
                case .top(let y): return p.y >= y
                case .bottom(let y): return p.y <= y
            }
        }

        func intersection(from: CGPoint, to: CGPoint) -> CGPoint? {
            let t = tValue(from: from, to: to)
            guard t.isFinite, t >= 0, t <= 1 else { return nil }
            return CGPoint(
                x: from.x + t * (to.x - from.x),
                y: from.y + t * (to.y - from.y)
            )
        }

        func tValue(from: CGPoint, to: CGPoint) -> CGFloat {
            switch self {
                case .left(let x):
                    let dx = to.x - from.x
                    guard dx != 0 else { return .infinity }
                    return (x - from.x) / dx
                case .right(let x):
                    let dx = to.x - from.x
                    guard dx != 0 else { return .infinity }
                    return (x - from.x) / dx
                case .top(let y):
                    let dy = to.y - from.y
                    guard dy != 0 else { return .infinity }
                    return (y - from.y) / dy
                case .bottom(let y):
                    let dy = to.y - from.y
                    guard dy != 0 else { return .infinity }
                    return (y - from.y) / dy
            }
        }
    }
}
