import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import CollageMaker

@MainActor
@Suite(.serialized) struct LayoutManagerTests {

    private func makeSetup(
        numImages: Int = 3,
        style: LayoutStyle = .uniform,
        assembler: CollageAssembly = TestAssembler()
    ) -> (manager: LayoutManager, cropManager: CropManager, previewManager: PreviewManager, images: [ImageItem], saliencyResults: [Int: SaliencyResult]) {
        let manager = LayoutManager()
        manager.layoutStyle = style
        let cropManager = CropManager()
        let previewManager = PreviewManager(assembler: assembler)
        let images = (0..<numImages).map { i in
            createTestImageItem(color: NSColor.systemBlue, size: CGSize(width: 200, height: 200), filename: "\(i).jpg")
        }
        let saliencyResults: [Int: SaliencyResult] = [:]
        return (manager, cropManager, previewManager, images, saliencyResults)
    }

    // MARK: - Regenerate Layout Basic

    @Test func regenerateLayoutCreatesPanels() {
        let (manager, crop, preview, images, saliency) = makeSetup(numImages: 4)

        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        #expect(manager.panels.count == 4)
        #expect(manager.panelAssignments.count == 4)
    }

    @Test func regenerateLayoutEmptyImagesDoesNothing() {
        let (manager, crop, preview, _, saliency) = makeSetup()

        manager.regenerateLayout(
            images: [],
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        #expect(manager.panels.isEmpty)
        #expect(manager.panelAssignments.isEmpty)
    }

    @Test func regenerateLayoutIncrementsLayoutVersion() {
        let (manager, crop, preview, images, saliency) = makeSetup(numImages: 3)

        let versionBefore = manager.layoutVersion

        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        #expect(manager.layoutVersion == versionBefore + 1)
    }

    @Test func regenerateLayoutMultipleCallsIncrementVersion() {
        let (manager, crop, preview, images, saliency) = makeSetup(numImages: 3)

        for _ in 0..<3 {
            manager.regenerateLayout(
                images: images,
                customImageOrder: [],
                cropManager: crop,
                previewManager: preview,
                saliencyResults: saliency,
                preserveCrops: false
            )
        }

        #expect(manager.layoutVersion == 3)
    }

    // MARK: - Panel Assignments

    @Test func regenerateLayoutCreatesSequentialAssignments() {
        let (manager, crop, preview, images, saliency) = makeSetup(numImages: 4)

        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        for (i, panel) in manager.panels.enumerated() {
            #expect(manager.panelAssignments[panel.id] == i)
        }
    }

    @Test func regenerateLayoutRespectsCustomImageOrder() {
        let (manager, crop, preview, images, saliency) = makeSetup(numImages: 4)
        let order = [3, 1, 0, 2]

        manager.regenerateLayout(
            images: images,
            customImageOrder: order,
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        #expect(manager.panels.count == 4)
        for (i, panel) in manager.panels.enumerated() {
            #expect(manager.panelAssignments[panel.id] == order[i])
        }
    }

    @Test func regenerateLayoutIgnoresMismatchedOrderLength() {
        let (manager, crop, preview, images, saliency) = makeSetup(numImages: 4)
        let order = [0, 1]

        manager.regenerateLayout(
            images: images,
            customImageOrder: order,
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        for (i, panel) in manager.panels.enumerated() {
            #expect(manager.panelAssignments[panel.id] == i)
        }
    }

    // MARK: - Preserve Crops: true

    @Test func regenerateLayoutPreserveCropsTruePreservesSourceRects() {
        let (manager, crop, preview, images, saliency) = makeSetup(numImages: 3)

        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        let modifiedCrops = manager.panels.map { panel in
            guard let existing = crop.cropMap[panel.id] else {
                return CropInfo(panelId: panel.id, sourceRect: CGRect(x: 10, y: 10, width: 50, height: 50), destination: panel.geometry)
            }
            return CropInfo(
                panelId: panel.id,
                sourceRect: CGRect(x: existing.sourceRect.origin.x + 10, y: existing.sourceRect.origin.y + 10, width: existing.sourceRect.width, height: existing.sourceRect.height),
                destination: panel.geometry
            )
        }
        for (i, panel) in manager.panels.enumerated() {
            crop.cropMap[panel.id] = modifiedCrops[i]
        }

        let sourceRectsBefore = crop.cropsBySlot(manager.panels)

        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: true
        )

        let sourceRectsAfter = crop.cropsBySlot(manager.panels)
        for i in 0..<sourceRectsBefore.count {
            #expect(sourceRectsAfter[i] == sourceRectsBefore[i])
        }
    }

    @Test func regenerateLayoutPreserveCropsTruePreservesPanelCount() {
        let (manager, crop, preview, images, saliency) = makeSetup(numImages: 5)

        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        let panelsBefore = manager.panels.count

        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: true
        )

        #expect(manager.panels.count == panelsBefore)
    }

    // MARK: - Preserve Crops: false

    @Test func regenerateLayoutPreserveCropsFalseResetsCrops() {
        let (manager, crop, preview, images, saliency) = makeSetup(numImages: 3)

        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        for panel in manager.panels {
            #expect(crop.cropMap[panel.id] != nil)
        }
    }

    @Test func regenerateLayoutPreserveCropsFalseWithSaliencyUsesSaliencyCrops() {
        let (manager, crop, preview, images, _) = makeSetup(numImages: 3)
        let saliency: [Int: SaliencyResult] = [
            0: SaliencyResult(center: CGPoint(x: 150, y: 150), radius: 30, confidence: 0.95),
            1: SaliencyResult(center: CGPoint(x: 50, y: 50), radius: 20, confidence: 0.8),
            2: SaliencyResult(center: CGPoint(x: 100, y: 100), radius: 25, confidence: 0.9),
        ]

        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        #expect(crop.cropMap.count == 3)
        for panel in manager.panels {
            #expect(crop.cropMap[panel.id] != nil)
        }
    }

    // MARK: - Layout Style Transitions

    @Test func layoutStyleTransitionUniformToHero() {
        let (manager, crop, preview, images, saliency) = makeSetup(numImages: 4, style: .uniform)

        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        let uniformPanels = manager.panels.map { $0.frame }

        manager.layoutStyle = .hero
        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        let heroPanels = manager.panels.map { $0.frame }
        #expect(heroPanels != uniformPanels)
        #expect(manager.panels.count == 4)
    }

    @Test func layoutStyleTransitionHeroToMosaic() {
        let (manager, crop, preview, images, saliency) = makeSetup(numImages: 4, style: .hero)

        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        let heroPanels = manager.panels.map { $0.frame }

        manager.layoutStyle = .mosaic
        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        let mosaicPanels = manager.panels.map { $0.frame }
        #expect(mosaicPanels != heroPanels)
        #expect(manager.panels.count == 4)
    }

    @Test func layoutStyleTransitionPreservesAssignmentsWithPreserveCrops() {
        let (manager, crop, preview, images, saliency) = makeSetup(numImages: 3, style: .uniform)

        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        for (i, panel) in manager.panels.enumerated() {
            manager.panelAssignments[panel.id] = i
        }

        manager.layoutStyle = .hero
        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: true
        )

        #expect(manager.panelAssignments.count == 3)
        for (i, panel) in manager.panels.enumerated() {
            #expect(manager.panelAssignments[panel.id] == i)
        }
    }

    // MARK: - Panel Assignment Persistence

    @Test func panelAssignmentsPersistAcrossRegenerations() {
        let (manager, crop, preview, images, saliency) = makeSetup(numImages: 3)

        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        let firstPanelId = manager.panels[0].id
        manager.panelAssignments[firstPanelId] = 2

        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        #expect(manager.panelAssignments.count == 3)
    }

    @Test func panelAssignmentsResetOnRegenerate() {
        let (manager, crop, preview, images, saliency) = makeSetup(numImages: 3)

        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        for (i, panel) in manager.panels.enumerated() {
            manager.panelAssignments[panel.id] = (2 - i)
        }

        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        for (i, panel) in manager.panels.enumerated() {
            #expect(manager.panelAssignments[panel.id] == i)
        }
    }

    // MARK: - Reset

    @Test func resetRestoresDefaults() {
        let (manager, crop, preview, images, saliency) = makeSetup(numImages: 3, style: .mosaic)

        manager.gutter = 10
        manager.diagonalSliceAngle = 60
        manager.hexagonalSpacing = 16
        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        manager.reset()

        #expect(manager.layoutStyle == .hero)
        #expect(manager.gutter == 0)
        #expect(manager.diagonalSliceAngle == 45.0)
        #expect(manager.hexagonalSpacing == 8.0)
        #expect(manager.panels.isEmpty)
        #expect(manager.panelAssignments.isEmpty)
        #expect(manager.doubleExposureMaskImage == nil)
        #expect(manager.doubleExposureMaskImagePath == nil)
        #expect(manager.doubleExposureMaskOpacity == 0.5)
    }

    @Test func resetIncrementsLayoutVersion() {
        let (manager, _, _, _, _) = makeSetup()

        let versionBefore = manager.layoutVersion
        manager.reset()

        #expect(manager.layoutVersion == versionBefore + 1)
    }

    // MARK: - Setter Methods Return Old Values

    @Test func setLayoutStyleReturnsOldStyle() {
        let manager = LayoutManager()
        manager.layoutStyle = .uniform

        let old = manager.setLayoutStyle(.hero)

        #expect(old == .uniform)
        #expect(manager.layoutStyle == .hero)
    }

    @Test func setGutterReturnsOldValue() {
        let manager = LayoutManager()
        manager.gutter = 5

        let old = manager.setGutter(10)

        #expect(old == 5)
        #expect(manager.gutter == 10)
    }

    @Test func setDiagonalSliceAngleReturnsOldValue() {
        let manager = LayoutManager()
        manager.diagonalSliceAngle = 30

        let old = manager.setDiagonalSliceAngle(60)

        #expect(old == 30)
        #expect(manager.diagonalSliceAngle == 60)
    }

    @Test func setHexagonalSpacingReturnsOldValue() {
        let manager = LayoutManager()
        manager.hexagonalSpacing = 4

        let old = manager.setHexagonalSpacing(12)

        #expect(old == 4)
        #expect(manager.hexagonalSpacing == 12)
    }

    @Test func setDoubleExposureMaskOpacityReturnsOldValue() {
        let manager = LayoutManager()
        manager.doubleExposureMaskOpacity = 0.3

        let old = manager.setDoubleExposureMaskOpacity(0.7)

        #expect(old == 0.3)
        #expect(manager.doubleExposureMaskOpacity == 0.7)
    }

    @Test func setMaskImageReturnsOldImageAndPath() {
        let manager = LayoutManager()
        let oldImage = createTestNSImage(color: .red, size: CGSize(width: 50, height: 50))
        manager.doubleExposureMaskImage = oldImage
        manager.doubleExposureMaskImagePath = "/old/path.jpg"

        let newImage = createTestNSImage(color: .blue, size: CGSize(width: 50, height: 50))
        let old = manager.setMaskImage(newImage, path: "/new/path.jpg")

        #expect(old.0 === oldImage)
        #expect(old.1 == "/old/path.jpg")
        #expect(manager.doubleExposureMaskImage === newImage)
        #expect(manager.doubleExposureMaskImagePath == "/new/path.jpg")
    }

    @Test func setMaskImageToNilClearsPath() {
        let manager = LayoutManager()
        manager.doubleExposureMaskImage = createTestNSImage(color: .red, size: CGSize(width: 50, height: 50))
        manager.doubleExposureMaskImagePath = "/some/path.jpg"

        _ = manager.setMaskImage(nil, path: nil)

        #expect(manager.doubleExposureMaskImage == nil)
        #expect(manager.doubleExposureMaskImagePath == nil)
    }

    // MARK: - Build Overlay Config

    @Test func buildOverlayConfigReturnsNilForMissingMaskImage() {
        let manager = LayoutManager()

        let config = manager.buildOverlayConfig()

        #expect(config == nil)
    }

    @Test func buildOverlayConfigReturnsConfigWithMaskImage() {
        let manager = LayoutManager()
        manager.doubleExposureMaskImage = createTestNSImage(color: .white, size: CGSize(width: 100, height: 100))
        manager.doubleExposureMaskOpacity = 0.75

        let config = manager.buildOverlayConfig()

        #expect(config != nil)
        #expect(config?.opacity == 0.75)
        #expect(config?.blendMode == .multiply)
    }

    // MARK: - Gutter Affects Layout

    @Test func gutterAffectsPanelFrames() {
        let (manager, crop, preview, images, saliency) = makeSetup(numImages: 4)
        manager.gutter = 0

        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        let noGutterWidth = manager.panels[0].frame.width

        manager.gutter = 20
        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        let withGutterWidth = manager.panels[0].frame.width
        #expect(withGutterWidth < noGutterWidth)
    }

    // MARK: - Preview Images Preservation

    @Test func regenerateLayoutPreserveCropsTruePreservesRenderedImages() {
        let assembler = TestAssembler()
        assembler.panelImage = createTestNSImage(color: .green, size: CGSize(width: 100, height: 100))
        let (manager, crop, preview, images, saliency) = makeSetup(numImages: 3, assembler: assembler)

        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        for panel in manager.panels {
            preview.panelRenderedImages[panel.id] = createTestNSImage(color: .yellow, size: CGSize(width: 100, height: 100))
        }

        let renderedBefore = preview.panelRenderedImagesBySlot(manager.panels)

        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: true
        )

        let renderedAfter = preview.panelRenderedImagesBySlot(manager.panels)
        for i in 0..<renderedBefore.count {
            #expect(renderedAfter[i] === renderedBefore[i])
        }
    }

    @Test func regenerateLayoutPreserveCropsFalseClearsRenderedImages() {
        let assembler = TestAssembler()
        let (manager, crop, preview, images, saliency) = makeSetup(numImages: 3, assembler: assembler)

        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        for panel in manager.panels {
            preview.panelRenderedImages[panel.id] = createTestNSImage(color: .yellow, size: CGSize(width: 100, height: 100))
        }

        manager.regenerateLayout(
            images: images,
            customImageOrder: [],
            cropManager: crop,
            previewManager: preview,
            saliencyResults: saliency,
            preserveCrops: false
        )

        #expect(preview.panelRenderedImages.isEmpty)
    }
}
