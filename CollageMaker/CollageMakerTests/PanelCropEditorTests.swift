import CoreGraphics
import Foundation
import Testing
@testable import CollageMaker

@MainActor
@Suite struct PanelCropEditorTests {

    // MARK: - Source Rect In Container

    @Test func sourceRectFullImageFillsContainer() {
        let crop = CropInfo(
            panelId: UUID(),
            sourceRect: CGRect(origin: .zero, size: CGSize(width: 200, height: 200)),
            destinationRect: CGRect(origin: .zero, size: CGSize(width: 400, height: 400))
        )
        let imageSize = CGSize(width: 200, height: 200)
        let container = CGSize(width: 800, height: 600)

        let result = CropManager.sourceRectInContainer(crop, imageSize: imageSize, container: container)

        #expect(result.origin.x == 100)
        #expect(result.origin.y == 0)
        #expect(result.width == 600)
        #expect(result.height == 600)
    }

    @Test func sourceRectQuarterCropShowsCorrectRegion() {
        let crop = CropInfo(
            panelId: UUID(),
            sourceRect: CGRect(x: 100, y: 100, width: 100, height: 100),
            destinationRect: CGRect(origin: .zero, size: CGSize(width: 400, height: 400))
        )
        let imageSize = CGSize(width: 200, height: 200)
        let container = CGSize(width: 800, height: 800)

        let result = CropManager.sourceRectInContainer(crop, imageSize: imageSize, container: container)

        #expect(result.origin.x == 400)
        #expect(result.origin.y == 400)
        #expect(result.width == 400)
        #expect(result.height == 400)
    }

    @Test func sourceRectPortraitImageLetterboxes() {
        let crop = CropInfo(
            panelId: UUID(),
            sourceRect: CGRect(origin: .zero, size: CGSize(width: 100, height: 200)),
            destinationRect: CGRect(origin: .zero, size: CGSize(width: 400, height: 400))
        )
        let imageSize = CGSize(width: 100, height: 200)
        let container = CGSize(width: 800, height: 800)

        let result = CropManager.sourceRectInContainer(crop, imageSize: imageSize, container: container)

        #expect(result.origin.x > 0)
        #expect(result.origin.x < container.width / 2)
        #expect(result.origin.y == 0)
        #expect(result.height == container.height)
    }

    @Test func sourceRectLandscapeImageLetterboxes() {
        let crop = CropInfo(
            panelId: UUID(),
            sourceRect: CGRect(origin: .zero, size: CGSize(width: 200, height: 100)),
            destinationRect: CGRect(origin: .zero, size: CGSize(width: 400, height: 400))
        )
        let imageSize = CGSize(width: 200, height: 100)
        let container = CGSize(width: 800, height: 800)

        let result = CropManager.sourceRectInContainer(crop, imageSize: imageSize, container: container)

        #expect(result.origin.x == 0)
        #expect(result.origin.y > 0)
        #expect(result.origin.y < container.height / 2)
        #expect(result.width == container.width)
    }

    @Test func sourceRectSmallCropShowsProportionalRegion() {
        let crop = CropInfo(
            panelId: UUID(),
            sourceRect: CGRect(x: 50, y: 50, width: 20, height: 20),
            destinationRect: CGRect(origin: .zero, size: CGSize(width: 400, height: 400))
        )
        let imageSize = CGSize(width: 200, height: 200)
        let container = CGSize(width: 800, height: 800)

        let result = CropManager.sourceRectInContainer(crop, imageSize: imageSize, container: container)

        #expect(result.origin.x == 200)
        #expect(result.origin.y == 200)
        #expect(result.width == 80)
        #expect(result.height == 80)
    }

    @Test func sourceRectStaysWithinContainer() {
        let crop = CropInfo(
            panelId: UUID(),
            sourceRect: CGRect(x: 0, y: 0, width: 150, height: 150),
            destinationRect: CGRect(origin: .zero, size: CGSize(width: 400, height: 400))
        )
        let imageSize = CGSize(width: 200, height: 200)
        let container = CGSize(width: 800, height: 600)

        let result = CropManager.sourceRectInContainer(crop, imageSize: imageSize, container: container)

        #expect(result.origin.x >= 0)
        #expect(result.origin.y >= 0)
        #expect(result.maxX <= container.width)
        #expect(result.maxY <= container.height)
    }

    // MARK: - Canvas To Preview Frame (used by PanelCropEditor indirectly)

    @Test func canvasToPreviewFrameCenteredPanel() {
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)
        let previewSize = CanvasConfig.defaultPreviewSize

        let previewFrame = CropManager.canvasToPreviewFrame(panels[0].frame, in: previewSize)

        #expect(previewFrame.width == previewSize.width)
        #expect(previewFrame.height == previewSize.height)
    }

    @Test func canvasToPreviewFrameMultiplePanelsMaintainProportions() {
        let panels = LayoutGenerator.generate(numImages: 4, style: .uniform)
        let previewSize = CanvasConfig.defaultPreviewSize

        var previewFrames: [CGRect] = []
        for panel in panels {
            previewFrames.append(CropManager.canvasToPreviewFrame(panel.frame, in: previewSize))
        }

        for frame in previewFrames {
            #expect(frame.width > 0)
            #expect(frame.height > 0)
            #expect(frame.origin.x >= 0)
            #expect(frame.origin.y >= 0)
        }
    }
}
