import CoreGraphics
import Foundation

protocol LayoutStrategy {
    func generate(numImages: Int, canvasSize: CGSize, gutter: CGFloat, imageOrder: [Int]?, mosaicSeed: UInt64?) -> [ImagePanel]
}

struct LayoutGenerator {
    static func generate(
        numImages: Int,
        canvasSize: CGSize = SizeConstants.defaultCanvasSize,
        gutter: CGFloat = 4,
        style: LayoutStyle = .hero,
        imageOrder: [Int]? = nil,
        mosaicSeed: UInt64? = nil,
        options: LayoutOptions = LayoutOptions()
    ) -> [ImagePanel] {
        style.makeStrategy(options: options).generate(
            numImages: numImages,
            canvasSize: canvasSize,
            gutter: gutter,
            imageOrder: imageOrder,
            mosaicSeed: mosaicSeed
        )
    }
}

// MARK: - Layout Strategies

struct UniformLayoutStrategy: LayoutStrategy {
    func generate(numImages: Int, canvasSize: CGSize, gutter: CGFloat, imageOrder: [Int]?, mosaicSeed: UInt64?) -> [ImagePanel] {
        guard numImages > 0 else { return [] }

        let columns: Int
        let rows: Int

        if numImages == 1 {
            columns = 1
            rows = 1
        } else {
            columns = min(numImages, 3)
            rows = (numImages + columns - 1) / columns
        }

        let totalGutterX = CGFloat(columns - 1) * gutter
        let totalGutterY = CGFloat(rows - 1) * gutter
        let cellW = (canvasSize.width - totalGutterX) / CGFloat(columns)
        let cellH = (canvasSize.height - totalGutterY) / CGFloat(rows)

        var panels: [ImagePanel] = []
        for i in 0..<numImages {
            let col = i % columns
            let row = i / columns
            let x = CGFloat(col) * (cellW + gutter)
            let y = CGFloat(row) * (cellH + gutter)
            let frame = CGRect(x: x, y: y, width: cellW, height: cellH)
            let imgIdx = imageOrder?[i] ?? i % numImages
            panels.append(ImagePanel(imageIndex: imgIdx, frame: frame))
        }

        return panels
    }
}

struct HeroLayoutStrategy: LayoutStrategy {
    func generate(numImages: Int, canvasSize: CGSize, gutter: CGFloat, imageOrder: [Int]?, mosaicSeed: UInt64?) -> [ImagePanel] {
        guard numImages > 0 else { return [] }
        guard numImages >= 2 else {
            return UniformLayoutStrategy().generate(
                numImages: numImages,
                canvasSize: canvasSize,
                gutter: gutter,
                imageOrder: imageOrder,
                mosaicSeed: mosaicSeed
            )
        }

        let midX = canvasSize.width / 2

        let heroFrame = CGRect(
            x: 0,
            y: 0,
            width: midX - gutter / 2,
            height: canvasSize.height
        )

        let sideW = (midX - gutter / 2)
        let sideAreaH = canvasSize.height
        let remaining = numImages - 1
        let sideCols = remaining <= 2 ? 1 : 2
        let sideRows = (remaining + sideCols - 1) / sideCols
        let sideGutterY = CGFloat(sideRows - 1) * gutter
        let cellH = (sideAreaH - sideGutterY) / CGFloat(sideRows)

        var panels: [ImagePanel] = []
        let heroImgIdx = imageOrder?[0] ?? 0
        panels.append(ImagePanel(imageIndex: heroImgIdx, frame: heroFrame))

        for i in 0..<remaining {
            let col = i % sideCols
            let row = i / sideCols
            let x = midX + gutter / 2 + CGFloat(col) * (sideW / CGFloat(sideCols) + (col > 0 ? gutter : 0))
            let y = CGFloat(row) * (cellH + gutter)
            let cellW = sideW / CGFloat(sideCols)
            let frame = CGRect(x: x, y: y, width: cellW, height: cellH)
            let imgIdx = imageOrder?[i + 1] ?? i + 1
            panels.append(ImagePanel(imageIndex: imgIdx, frame: frame))
        }

        return panels
    }
}

struct MosaicLayoutStrategy: LayoutStrategy {
    func generate(numImages: Int, canvasSize: CGSize, gutter: CGFloat, imageOrder: [Int]?, mosaicSeed: UInt64?) -> [ImagePanel] {
        guard numImages > 0 else { return [] }

        if numImages == 1 {
            let imgIdx = imageOrder?[0] ?? 0
            return [ImagePanel(imageIndex: imgIdx, frame: CGRect(origin: .zero, size: canvasSize))]
        }

        var remaining = CGRect(origin: .zero, size: canvasSize)
        var panels: [ImagePanel] = []
        var imageIdx = 0
        var rng = mosaicSeed.map { SeededPRNG(seed: $0) }

        let maxSplits = min(numImages, 20)

        for _ in 0..<maxSplits {
            guard imageIdx < numImages else { break }

            let w = remaining.width
            let h = remaining.height

            if imageIdx == numImages - 1 {
                let imgIdx = imageOrder?[imageIdx] ?? imageIdx
                panels.append(ImagePanel(imageIndex: imgIdx, frame: remaining))
                break
            }

            let isWide = w > h
            var splitRatio: CGFloat

            let rand: Float
            if var seeded = rng {
                let bits = seeded.next() >> 40 & 0x000FFFFF
                rng = seeded
                rand = Float(bits) / Float(1 << 20)
            } else {
                rand = Float.random(in: 0..<1)
            }

            if rand < 0.3 && panels.count > 0 {
                splitRatio = 0.25
            } else if rand < 0.6 {
                splitRatio = 0.33
            } else {
                splitRatio = 0.4
            }

            if isWide {
                let splitW = w * splitRatio
                let panelFrame = CGRect(x: remaining.origin.x, y: remaining.origin.y, width: splitW, height: h)
                let imgIdx = imageOrder?[imageIdx] ?? imageIdx
                panels.append(ImagePanel(imageIndex: imgIdx, frame: panelFrame))
                remaining = CGRect(
                    x: remaining.origin.x + splitW + gutter,
                    y: remaining.origin.y,
                    width: w - splitW - gutter,
                    height: h
                )
            } else {
                let splitH = h * splitRatio
                let panelFrame = CGRect(x: remaining.origin.x, y: remaining.origin.y, width: w, height: splitH)
                let imgIdx = imageOrder?[imageIdx] ?? imageIdx
                panels.append(ImagePanel(imageIndex: imgIdx, frame: panelFrame))
                remaining = CGRect(
                    x: remaining.origin.x,
                    y: remaining.origin.y + splitH + gutter,
                    width: w,
                    height: h - splitH - gutter
                )
            }

            imageIdx += 1
        }

        return panels
    }
}

// MARK: - LayoutStyle factory

extension LayoutStyle {
    func makeStrategy(options: LayoutOptions) -> LayoutStrategy {
        switch self {
        case .uniform: return UniformLayoutStrategy()
        case .hero: return HeroLayoutStrategy()
        case .mosaic: return MosaicLayoutStrategy()
        case .doubleExposure: return DoubleExposureLayoutStrategy()
        case .diagonalSlices: return DiagonalSlicesLayoutStrategy(angle: options.sliceAngle)
        case .hexagonal: return HexagonalLayoutStrategy(spacing: options.hexSpacing)
        }
    }
}

// MARK: - Stub Strategies

struct DoubleExposureLayoutStrategy: LayoutStrategy {
    func generate(numImages: Int, canvasSize: CGSize, gutter: CGFloat, imageOrder: [Int]?, mosaicSeed: UInt64?) -> [ImagePanel] {
        return UniformLayoutStrategy().generate(
            numImages: numImages,
            canvasSize: canvasSize,
            gutter: gutter,
            imageOrder: imageOrder,
            mosaicSeed: mosaicSeed
        )
    }
}

struct DiagonalSlicesLayoutStrategy: LayoutStrategy {
    let angle: CGFloat

    init(angle: CGFloat = 45.0) {
        self.angle = angle
    }

    func generate(numImages: Int, canvasSize: CGSize, gutter: CGFloat, imageOrder: [Int]?, mosaicSeed: UInt64?) -> [ImagePanel] {
        guard numImages > 0 else { return [] }

        if numImages == 1 {
            let imgIdx = imageOrder?[0] ?? 0
            return [ImagePanel(imageIndex: imgIdx, frame: CGRect(origin: .zero, size: canvasSize))]
        }

        let radians = angle * .pi / 180.0
        let shear = tan(radians)

        let shearOffset = canvasSize.height * shear
        let effectiveGutter = gutter * cos(radians) * cos(radians)
        let totalGutter = CGFloat(numImages - 1) * effectiveGutter
        let colWidth = (canvasSize.width + shearOffset - totalGutter) / CGFloat(numImages)
        let centerOffset = -shearOffset

        var panels: [ImagePanel] = []

        for i in 0..<numImages {
            let unshearedX = centerOffset + CGFloat(i) * (colWidth + effectiveGutter)
            let unshearedRect = CGRect(x: unshearedX, y: 0, width: colWidth, height: canvasSize.height)

            let corners: [CGPoint] = [
                CGPoint(x: unshearedRect.origin.x + unshearedRect.origin.y * shear, y: unshearedRect.origin.y),
                CGPoint(x: unshearedRect.maxX + unshearedRect.origin.y * shear, y: unshearedRect.origin.y),
                CGPoint(x: unshearedRect.maxX + unshearedRect.maxY * shear, y: unshearedRect.maxY),
                CGPoint(x: unshearedRect.origin.x + unshearedRect.maxY * shear, y: unshearedRect.maxY)
            ]

            let mutablePath = CGMutablePath()
            mutablePath.move(to: corners[0])
            mutablePath.addLine(to: corners[1])
            mutablePath.addLine(to: corners[2])
            mutablePath.addLine(to: corners[3])
            mutablePath.closeSubpath()
            let path = mutablePath

            let minX = min(corners[0].x, corners[1].x, corners[2].x, corners[3].x)
            let minY = min(corners[0].y, corners[1].y, corners[2].y, corners[3].y)
            let maxX = max(corners[0].x, corners[1].x, corners[2].x, corners[3].x)
            let maxY = max(corners[0].y, corners[1].y, corners[2].y, corners[3].y)
            let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            let imgIdx = imageOrder?[i] ?? i
            panels.append(ImagePanel(imageIndex: imgIdx, geometry: .path(cgPath: path, boundingRect: bounds)))
        }

        return panels
    }
}

struct HexagonalLayoutStrategy: LayoutStrategy {
    let spacing: CGFloat

    init(spacing: CGFloat = 8.0) {
        self.spacing = spacing
    }

    func generate(numImages: Int, canvasSize: CGSize, gutter: CGFloat, imageOrder: [Int]?, mosaicSeed: UInt64?) -> [ImagePanel] {
        guard numImages > 0 else { return [] }

        if numImages == 1 {
            let imgIdx = imageOrder?[0] ?? 0
            return [ImagePanel(imageIndex: imgIdx, frame: CGRect(origin: .zero, size: canvasSize))]
        }

        let canvasCenter = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

        // Estimate rings needed to hold all images (center + rings)
        let remaining = numImages - 1
        var ringsNeeded = 0
        var capacity = 0
        while capacity < remaining {
            ringsNeeded += 1
            capacity += 6 * ringsNeeded
        }

        // Effective radius for grid spacing; visual radius derived so hexagons don't overlap
        // Min center distance on axial grid = sqrt(3) * R_eff, so R = sqrt(3)/2 * R_eff - S/2
        // Must account for hex extent beyond outermost centers:
        //   Horizontal: sqrt(3)*R_eff*(rings + 0.5) <= W/2
        //   Vertical:   R_eff*(1.5*rings + sqrt(3)/2) <= H/2
        let R_eff = min(canvasSize.width / (sqrt(3.0) * CGFloat(2 * ringsNeeded + 1)),
                        canvasSize.height / (3.0 * CGFloat(ringsNeeded) + sqrt(3.0)))
        let R = max(sqrt(3.0) / 2.0 * R_eff - spacing / 2.0, spacing)

        // Axial coordinate directions for pointy-top hex ring traversal
        // Must follow ring perimeter: (0,-1) → (-1,0) → (-1,+1) → (0,+1) → (+1,0) → (+1,-1)
        let directions: [(dq: Int, dr: Int)] = [
            (0, -1), (-1, 0), (-1, +1), (0, +1), (+1, 0), (+1, -1)
        ]

        // Generate hexagon center positions using axial hex grid
        var centers: [CGPoint] = [canvasCenter]

        for ring in 1...ringsNeeded {
            var q = ring
            var r = 0
            for (dq, dr) in directions {
                for _ in 0..<ring {
                    guard centers.count - 1 < numImages else { break }
                    let x = canvasCenter.x + (CGFloat(q) + CGFloat(r) / 2.0) * sqrt(3.0) * R_eff
                    let y = canvasCenter.y + CGFloat(r) * 1.5 * R_eff
                    centers.append(CGPoint(x: x, y: y))
                    q += dq
                    r += dr
                }
                if centers.count - 1 >= numImages { break }
            }
            if centers.count - 1 >= numImages { break }
        }

        var panels: [ImagePanel] = []
        for i in 0..<numImages {
            guard i < centers.count else { break }
            let center = centers[i]
            let (path, bounds) = createHexagonPath(center: center, radius: R)
            let imgIdx = imageOrder?[i] ?? i
            panels.append(ImagePanel(imageIndex: imgIdx, geometry: .path(cgPath: path, boundingRect: bounds)))
        }

        return panels
    }
}

// MARK: - Hexagon Geometry

private func createHexagonPath(center: CGPoint, radius: CGFloat) -> (path: CGPath, boundingRect: CGRect) {
    let mutablePath = CGMutablePath()
    var vertices: [CGPoint] = []

    for i in 0..<6 {
        let angle = .pi / 6.0 + .pi / 3.0 * CGFloat(i)
        let x = center.x + radius * cos(angle)
        let y = center.y + radius * sin(angle)
        vertices.append(CGPoint(x: x, y: y))
        if i == 0 {
            mutablePath.move(to: vertices[0])
        } else {
            mutablePath.addLine(to: vertices[i])
        }
    }
    mutablePath.closeSubpath()

    let minX = vertices.map { $0.x }.min()!
    let minY = vertices.map { $0.y }.min()!
    let maxX = vertices.map { $0.x }.max()!
    let maxY = vertices.map { $0.y }.max()!
    let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

    return (mutablePath, bounds)
}

// MARK: - Seeded PRNG

/// Deterministic PRNG for reproducible mosaic layouts.
struct SeededPRNG {
    var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z &>> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z &>> 31)
    }
}
