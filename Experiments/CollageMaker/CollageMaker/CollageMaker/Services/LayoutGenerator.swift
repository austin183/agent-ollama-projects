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
        mosaicSeed: UInt64? = nil
    ) -> [ImagePanel] {
        style.makeStrategy().generate(
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
    func makeStrategy() -> LayoutStrategy {
        switch self {
        case .uniform: return UniformLayoutStrategy()
        case .hero: return HeroLayoutStrategy()
        case .mosaic: return MosaicLayoutStrategy()
        case .doubleExposure: return DoubleExposureLayoutStrategy()
        case .diagonalSlices: return DiagonalSlicesLayoutStrategy()
        case .hexagonal: return HexagonalLayoutStrategy()
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

struct HexagonalLayoutStrategy: LayoutStrategy {
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
