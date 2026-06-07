import CoreGraphics
import Testing
@testable import CollageMaker

@Suite struct LayoutGeneratorTests {

    // MARK: - Empty and single image

    @Test func emptyReturnsNoPanels() {
        let panels = LayoutGenerator.generate(numImages: 0)
        #expect(panels.isEmpty)
    }

    @Test func singleImageUniform() {
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)
        #expect(panels.count == 1)
        #expect(panels[0].imageIndex == 0)
        #expect(panels[0].frame.size == SizeConstants.defaultCanvasSize)
    }

    @Test func singleImageHero() {
        let panels = LayoutGenerator.generate(numImages: 1, style: .hero)
        #expect(panels.count == 1)
    }

    @Test func singleImageMosaic() {
        let panels = LayoutGenerator.generate(numImages: 1, style: .mosaic)
        #expect(panels.count == 1)
        #expect(panels[0].frame.size == SizeConstants.defaultCanvasSize)
    }

    // MARK: - Uniform style

    @Test func uniformTwoImages() {
        let panels = LayoutGenerator.generate(numImages: 2, style: .uniform)
        #expect(panels.count == 2)
        #expect(panels[0].imageIndex == 0)
        #expect(panels[1].imageIndex == 1)
    }

    @Test func uniformFourImages() {
        let panels = LayoutGenerator.generate(numImages: 4, style: .uniform)
        #expect(panels.count == 4)
    }

    @Test func uniformSixImages() {
        let panels = LayoutGenerator.generate(numImages: 6, style: .uniform)
        #expect(panels.count == 6)
    }

    @Test func uniformPanelsWithinCanvasBounds() {
        let panels = LayoutGenerator.generate(numImages: 6, style: .uniform)
        for panel in panels {
            #expect(panel.frame.origin.x >= 0)
            #expect(panel.frame.origin.y >= 0)
            #expect(panel.frame.maxX <= SizeConstants.defaultCanvasSize.width)
            #expect(panel.frame.maxY <= SizeConstants.defaultCanvasSize.height)
        }
    }

    @Test func uniformAllImageIndicesUnique() {
        let panels = LayoutGenerator.generate(numImages: 6, style: .uniform)
        let indices = Set(panels.map { $0.imageIndex })
        #expect(indices.count == panels.count)
    }

    // MARK: - Hero style

    @Test func heroTwoImages() {
        let panels = LayoutGenerator.generate(numImages: 2, style: .hero)
        #expect(panels.count == 2)
        #expect(panels[0].imageIndex == 0)
    }

    @Test func heroFourImages() {
        let panels = LayoutGenerator.generate(numImages: 4, style: .hero)
        #expect(panels.count == 4)
    }

    @Test func heroPanelsWithinCanvasBounds() {
        let panels = LayoutGenerator.generate(numImages: 5, style: .hero)
        for panel in panels {
            #expect(panel.frame.origin.x >= 0)
            #expect(panel.frame.origin.y >= 0)
            #expect(panel.frame.maxX <= SizeConstants.defaultCanvasSize.width + 10)
            #expect(panel.frame.maxY <= SizeConstants.defaultCanvasSize.height)
        }
    }

    @Test func heroAllImageIndicesUnique() {
        let panels = LayoutGenerator.generate(numImages: 5, style: .hero)
        let indices = Set(panels.map { $0.imageIndex })
        #expect(indices.count == panels.count)
    }

    @Test func heroWithCustomOrderFirstIsHero() {
        let order = [3, 0, 2, 1]
        let panels = LayoutGenerator.generate(numImages: 4, style: .hero, imageOrder: order)
        #expect(panels[0].imageIndex == 3)
        #expect(panels[1].imageIndex == 0)
        #expect(panels[2].imageIndex == 2)
        #expect(panels[3].imageIndex == 1)
    }

    @Test func heroWithCustomOrderAllIndicesUnique() {
        let order = [3, 1, 0, 4, 2]
        let panels = LayoutGenerator.generate(numImages: 5, style: .hero, imageOrder: order)
        #expect(panels[0].imageIndex == 3)
        let indices = Set(panels.map { $0.imageIndex })
        #expect(indices.count == 5)
    }

    // MARK: - Mosaic style

    @Test func mosaicTwoImages() {
        let panels = LayoutGenerator.generate(numImages: 2, style: .mosaic)
        #expect(panels.count == 2)
    }

    @Test func mosaicFourImages() {
        let panels = LayoutGenerator.generate(numImages: 4, style: .mosaic)
        #expect(panels.count == 4)
    }

    @Test func mosaicPanelsWithinCanvasBounds() {
        let panels = LayoutGenerator.generate(numImages: 6, style: .mosaic)
        for panel in panels {
            #expect(panel.frame.origin.x >= 0)
            #expect(panel.frame.origin.y >= 0)
            #expect(panel.frame.maxX <= SizeConstants.defaultCanvasSize.width + 1)
            #expect(panel.frame.maxY <= SizeConstants.defaultCanvasSize.height + 1)
        }
    }

    @Test func mosaicAllImageIndicesUnique() {
        let panels = LayoutGenerator.generate(numImages: 8, style: .mosaic)
        let indices = Set(panels.map { $0.imageIndex })
        #expect(indices.count == panels.count)
    }

    // MARK: - Gutter

    @Test func gutterAffectsPanelSize() {
        let noGutter = LayoutGenerator.generate(numImages: 4, gutter: 0, style: .uniform)
        let withGutter = LayoutGenerator.generate(numImages: 4, gutter: 10, style: .uniform)
        #expect(withGutter[0].frame.width < noGutter[0].frame.width)
    }

    // MARK: - Many images

    @Test func uniformTwelveImages() {
        let panels = LayoutGenerator.generate(numImages: 12, style: .uniform)
        #expect(panels.count == 12)
    }

    @Test func heroTwelveImages() {
        let panels = LayoutGenerator.generate(numImages: 12, style: .hero)
        #expect(panels.count == 12)
    }

    // MARK: - Diagonal Slices style

    @Test func diagonalSlicesProducesPathGeometry() {
        let panels = LayoutGenerator.generate(numImages: 4, style: .diagonalSlices, sliceAngle: 45)
        #expect(panels.count == 4)
        for panel in panels {
            #expect(panel.geometry.cgPath != nil, "Panel should have CGPath geometry")
        }
    }

    @Test func diagonalSlicesCoversCanvas() {
        let panels = LayoutGenerator.generate(numImages: 3, style: .diagonalSlices, sliceAngle: 45)
        let canvas = CGRect(origin: .zero, size: SizeConstants.defaultCanvasSize)
        for panel in panels {
            #expect(canvas.intersects(panel.frame))
        }
    }

    @Test func diagonalSlicesSingleImage() {
        let panels = LayoutGenerator.generate(numImages: 1, style: .diagonalSlices)
        #expect(panels.count == 1)
        #expect(panels[0].frame == CGRect(origin: .zero, size: SizeConstants.defaultCanvasSize))
    }

    @Test func diagonalSlicesAllImageIndicesUnique() {
        let panels = LayoutGenerator.generate(numImages: 6, style: .diagonalSlices)
        let indices = Set(panels.map { $0.imageIndex })
        #expect(indices.count == panels.count)
    }

    @Test func diagonalSlicesWithCustomOrder() {
        let order = [3, 0, 2, 1]
        let panels = LayoutGenerator.generate(numImages: 4, style: .diagonalSlices, imageOrder: order)
        #expect(panels[0].imageIndex == 3)
        #expect(panels[1].imageIndex == 0)
        #expect(panels[2].imageIndex == 2)
        #expect(panels[3].imageIndex == 1)
    }

    @Test func diagonalSlicesZeroAngleProducesVerticalStrips() {
        let panels = LayoutGenerator.generate(numImages: 3, style: .diagonalSlices, sliceAngle: 0)
        #expect(panels.count == 3)
        for panel in panels {
            #expect(panel.frame.origin.y == 0)
            #expect(panel.frame.maxY == SizeConstants.defaultCanvasSize.height)
        }
    }

    @Test func diagonalSlicesNegativeAngle() {
        let panels = LayoutGenerator.generate(numImages: 4, style: .diagonalSlices, sliceAngle: -30)
        #expect(panels.count == 4)
        for panel in panels {
            #expect(panel.geometry.cgPath != nil)
        }
    }

    @Test func diagonalSlicesTwoImages() {
        let panels = LayoutGenerator.generate(numImages: 2, style: .diagonalSlices, sliceAngle: 45)
        #expect(panels.count == 2)
        #expect(panels[0].imageIndex == 0)
        #expect(panels[1].imageIndex == 1)
        for panel in panels {
            #expect(panel.geometry.cgPath != nil)
        }
    }

    @Test func diagonalSlicesLargeAngle() {
        let panels = LayoutGenerator.generate(numImages: 4, style: .diagonalSlices, sliceAngle: 70)
        #expect(panels.count == 4)
        for panel in panels {
            #expect(panel.geometry.cgPath != nil)
            #expect(panel.frame.width > 0)
            #expect(panel.frame.height > 0)
        }
    }

    @Test func diagonalSlicesPanelsWithinReasonableBounds() {
        let panels = LayoutGenerator.generate(numImages: 4, style: .diagonalSlices, sliceAngle: 45)
        let canvas = CGRect(origin: .zero, size: SizeConstants.defaultCanvasSize)
        for panel in panels {
            let intersection = canvas.intersection(panel.frame)
            let overlapRatio = intersection.width * intersection.height / panel.frame.width * panel.frame.height
            #expect(overlapRatio > 0.5, "Panel should have significant overlap with canvas")
        }
    }

    // MARK: - Hexagonal style

    @Test func hexagonalProducesPathGeometry() {
        let panels = LayoutGenerator.generate(numImages: 7, style: .hexagonal, hexSpacing: 8)
        #expect(panels.count == 7)
        for panel in panels {
            #expect(panel.geometry.cgPath != nil)
        }
    }

    @Test func hexagonalFirstPanelIsCenter() {
        let canvas = CGRect(origin: .zero, size: SizeConstants.defaultCanvasSize)
        let center = CGPoint(x: canvas.midX, y: canvas.midY)
        let panels = LayoutGenerator.generate(numImages: 7, style: .hexagonal, hexSpacing: 8)
        let firstPanel = panels[0]
        #expect(abs(firstPanel.frame.midX - center.x) < 10)
        #expect(abs(firstPanel.frame.midY - center.y) < 10)
    }

    @Test func hexagonalSingleImage() {
        let panels = LayoutGenerator.generate(numImages: 1, style: .hexagonal)
        #expect(panels.count == 1)
        #expect(panels[0].frame == CGRect(origin: .zero, size: SizeConstants.defaultCanvasSize))
    }

    @Test func hexagonalAllImageIndicesUnique() {
        let panels = LayoutGenerator.generate(numImages: 10, style: .hexagonal)
        let indices = Set(panels.map { $0.imageIndex })
        #expect(indices.count == panels.count)
    }

    @Test func hexagonalWithCustomOrder() {
        let order = [3, 0, 2, 1]
        let panels = LayoutGenerator.generate(numImages: 4, style: .hexagonal, imageOrder: order)
        #expect(panels[0].imageIndex == 3)
        #expect(panels[1].imageIndex == 0)
        #expect(panels[2].imageIndex == 2)
        #expect(panels[3].imageIndex == 1)
    }

    @Test func hexagonalTwoImages() {
        let panels = LayoutGenerator.generate(numImages: 2, style: .hexagonal)
        #expect(panels.count == 2)
        #expect(panels[0].imageIndex == 0)
        #expect(panels[1].imageIndex == 1)
        for panel in panels {
            #expect(panel.geometry.cgPath != nil)
        }
    }

    @Test func hexagonalThirteenImages() {
        let panels = LayoutGenerator.generate(numImages: 13, style: .hexagonal)
        #expect(panels.count == 13)
        for panel in panels {
            #expect(panel.geometry.cgPath != nil)
            #expect(panel.frame.width > 0)
            #expect(panel.frame.height > 0)
        }
    }

    @Test func hexagonalPanelsOverlapCanvas() {
        let panels = LayoutGenerator.generate(numImages: 7, style: .hexagonal, hexSpacing: 8)
        let canvas = CGRect(origin: .zero, size: SizeConstants.defaultCanvasSize)
        for panel in panels {
            #expect(canvas.intersects(panel.frame))
        }
    }

    @Test func hexagonalSpacingAffectsLayout() {
        let tight = LayoutGenerator.generate(numImages: 7, style: .hexagonal, hexSpacing: 2)
        let loose = LayoutGenerator.generate(numImages: 7, style: .hexagonal, hexSpacing: 20)
        // Larger spacing → smaller visual hexagons (more gap between neighbors)
        #expect(loose[0].frame.width < tight[0].frame.width)
    }

    @Test func hexagonalPanelsDoNotOverlap() {
        let panels = LayoutGenerator.generate(numImages: 7, style: .hexagonal, hexSpacing: 8)
        // For pointy-top hex: frame.width = sqrt(3) * R → R = frame.width / sqrt(3)
        // Minimum center distance for non-overlap = 2 * R
        let R = panels[0].frame.width / sqrt(3.0)
        let minDist = 2 * R
        for i in 0..<panels.count {
            for j in (i + 1)..<panels.count {
                let dx = panels[i].frame.midX - panels[j].frame.midX
                let dy = panels[i].frame.midY - panels[j].frame.midY
                let dist = sqrt(dx * dx + dy * dy)
                #expect(dist >= minDist - 0.5, "Panels \(i) and \(j) overlap: distance \(dist) < \(minDist)")
            }
        }
    }
}
