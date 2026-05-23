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
        #expect(panels[0].frame.size == CanvasConfig.defaultCanvasSize)
    }

    @Test func singleImageHero() {
        let panels = LayoutGenerator.generate(numImages: 1, style: .hero)
        #expect(panels.count == 1)
    }

    @Test func singleImageMosaic() {
        let panels = LayoutGenerator.generate(numImages: 1, style: .mosaic)
        #expect(panels.count == 1)
        #expect(panels[0].frame.size == CanvasConfig.defaultCanvasSize)
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
            #expect(panel.frame.maxX <= CanvasConfig.defaultCanvasSize.width)
            #expect(panel.frame.maxY <= CanvasConfig.defaultCanvasSize.height)
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
            #expect(panel.frame.maxX <= CanvasConfig.defaultCanvasSize.width + 10)
            #expect(panel.frame.maxY <= CanvasConfig.defaultCanvasSize.height)
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
            #expect(panel.frame.maxX <= CanvasConfig.defaultCanvasSize.width + 1)
            #expect(panel.frame.maxY <= CanvasConfig.defaultCanvasSize.height + 1)
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
}
