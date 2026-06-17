import CoreGraphics
import Foundation
import Testing
@testable import CollageMaker

@Suite struct CoordinateConverterTests {

    // MARK: - Canvas to Preview Frame

    @Test func canvasToPreviewFrameIdentityForMatchingSize() {
        let canvasSize = SizeConstants.defaultCanvasSize
        let canvasRect = CGRect(x: 100, y: 200, width: 200, height: 150)

        let previewFrame = CoordinateConverter.canvasToPreviewFrame(canvasRect, in: canvasSize, canvasSize: canvasSize)

        #expect(previewFrame.origin.x == canvasRect.origin.x)
        #expect(previewFrame.size.width == canvasRect.width)
        #expect(previewFrame.size.height == canvasRect.height)
    }

    @Test func canvasToPreviewFrameFlipsYAxis() {
        let previewSize = SizeConstants.defaultPreviewSize
        let canvasSize = SizeConstants.defaultCanvasSize
        let canvasRect = CGRect(x: 0, y: 0, width: 100, height: 100)

        let previewFrame = CoordinateConverter.canvasToPreviewFrame(canvasRect, in: previewSize, canvasSize: canvasSize)

        #expect(previewFrame.origin.y > 0)
    }

    @Test func canvasToPreviewFrameScalesCorrectly() {
        let previewSize = SizeConstants.defaultPreviewSize
        let canvasSize = SizeConstants.defaultCanvasSize
        let canvasRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let previewFrame = CoordinateConverter.canvasToPreviewFrame(canvasRect, in: previewSize, canvasSize: canvasSize)

        #expect(previewFrame.size.width == previewSize.width)
        #expect(previewFrame.size.height == previewSize.height)
    }

    @Test func canvasToPreviewFrameHandlesOffset() {
        let previewSize = CGSize(width: 1280, height: 720)
        let canvasSize = SizeConstants.defaultCanvasSize
        let canvasRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let previewFrame = CoordinateConverter.canvasToPreviewFrame(canvasRect, in: previewSize, canvasSize: canvasSize)

        #expect(previewFrame.origin.x >= 0)
        #expect(previewFrame.origin.y >= 0)
        #expect(previewFrame.maxX <= previewSize.width)
        #expect(previewFrame.maxY <= previewSize.height)
    }

    // MARK: - Screen to Canvas Point

    @Test func screenToCanvasPointIdentityForMatchingSize() {
        let canvasSize = SizeConstants.defaultCanvasSize
        let screenPoint = CGPoint(x: 960, y: 540)

        let canvasPoint = CoordinateConverter.screenToCanvasPoint(screenPoint, in: canvasSize, canvasSize: canvasSize)

        #expect(canvasPoint.x == screenPoint.x)
        #expect(canvasPoint.y == screenPoint.y)
    }

    @Test func screenToCanvasPointFlipsYAxis() {
        let canvasSize = SizeConstants.defaultCanvasSize
        let screenPoint = CGPoint(x: 960, y: 0)

        let canvasPoint = CoordinateConverter.screenToCanvasPoint(screenPoint, in: canvasSize, canvasSize: canvasSize)

        #expect(canvasPoint.y == canvasSize.height)
    }

    @Test func screenToCanvasPointScalesDown() {
        let previewSize = SizeConstants.defaultPreviewSize
        let canvasSize = SizeConstants.defaultCanvasSize
        let screenPoint = CGPoint(x: 480, y: 270)

        let canvasPoint = CoordinateConverter.screenToCanvasPoint(screenPoint, in: previewSize, canvasSize: canvasSize)

        #expect(canvasPoint.x == 960)
        #expect(canvasPoint.y == 540)
    }

    // MARK: - Hit Testing

    @Test func hitTestPanelReturnsPanelWhenLocationInside() {
        let panelId = UUID()
        let panelFrame = CGRect(x: 100, y: 100, width: 200, height: 150)
        let panelFrames: [UUID: CGRect] = [panelId: panelFrame]
        let canvasSize = SizeConstants.defaultCanvasSize

        let hitId = CoordinateConverter.hitTestPanel(
            at: CGPoint(x: 150, y: 150),
            panelFrames: panelFrames,
            previewSize: CGSize(width: 800, height: 600),
            canvasSize: canvasSize
        )

        #expect(hitId == panelId)
    }

    @Test func hitTestPanelReturnsNilWhenLocationOutside() {
        let panelId = UUID()
        let panelFrame = CGRect(x: 100, y: 100, width: 200, height: 150)
        let panelFrames: [UUID: CGRect] = [panelId: panelFrame]
        let canvasSize = SizeConstants.defaultCanvasSize

        let hitId = CoordinateConverter.hitTestPanel(
            at: CGPoint(x: 50, y: 50),
            panelFrames: panelFrames,
            previewSize: CGSize(width: 800, height: 600),
            canvasSize: canvasSize
        )

        #expect(hitId == nil)
    }

    @Test func hitTestPanelReturnsNilForEmptyFrames() {
        let panelFrames: [UUID: CGRect] = [:]
        let canvasSize = SizeConstants.defaultCanvasSize

        let hitId = CoordinateConverter.hitTestPanel(
            at: CGPoint(x: 100, y: 100),
            panelFrames: panelFrames,
            previewSize: CGSize(width: 800, height: 600),
            canvasSize: canvasSize
        )

        #expect(hitId == nil)
    }

    @Test func hitTestPanelReturnsFirstHit() {
        let panelId1 = UUID()
        let panelId2 = UUID()
        let frame1 = CGRect(x: 0, y: 0, width: 200, height: 200)
        let frame2 = CGRect(x: 100, y: 100, width: 200, height: 200)
        let panelFrames: [UUID: CGRect] = [panelId1: frame1, panelId2: frame2]
        let canvasSize = SizeConstants.defaultCanvasSize

        let hitId = CoordinateConverter.hitTestPanel(
            at: CGPoint(x: 150, y: 150),
            panelFrames: panelFrames,
            previewSize: CGSize(width: 800, height: 600),
            canvasSize: canvasSize
        )

        #expect(hitId == panelId1 || hitId == panelId2)
    }

    // MARK: - Vision to CG Point

    @Test func visionToCGFlipsYAxis() {
        let imageSize = CGSize(width: 1000, height: 2000)
        let visionPoint = CGPoint(x: 0.5, y: 0.0)

        let cgPoint = CoordinateConverter.visionToCG(visionPoint, imageSize: imageSize)

        #expect(cgPoint.x == 500)
        #expect(cgPoint.y == 2000)
    }

    @Test func visionToCGLeavesXUnchanged() {
        let imageSize = CGSize(width: 1000, height: 2000)
        let visionPoint = CGPoint(x: 0.75, y: 0.5)

        let cgPoint = CoordinateConverter.visionToCG(visionPoint, imageSize: imageSize)

        #expect(cgPoint.x == 750)
        #expect(cgPoint.y == 1000)
    }

    @Test func visionToCGOriginBottomLeft() {
        let imageSize = CGSize(width: 100, height: 200)
        let visionPoint = CGPoint(x: 0, y: 0)

        let cgPoint = CoordinateConverter.visionToCG(visionPoint, imageSize: imageSize)

        #expect(cgPoint.x == 0)
        #expect(cgPoint.y == 200)
    }

    @Test func visionToCGTopRight() {
        let imageSize = CGSize(width: 100, height: 200)
        let visionPoint = CGPoint(x: 1, y: 1)

        let cgPoint = CoordinateConverter.visionToCG(visionPoint, imageSize: imageSize)

        #expect(cgPoint.x == 100)
        #expect(cgPoint.y == 0)
    }

    @Test func visionToCGCenter() {
        let imageSize = CGSize(width: 1000, height: 2000)
        let visionPoint = CGPoint(x: 0.5, y: 0.5)

        let cgPoint = CoordinateConverter.visionToCG(visionPoint, imageSize: imageSize)

        #expect(cgPoint.x == 500)
        #expect(cgPoint.y == 1000)
    }

    // MARK: - Vision to CG Rect

    @Test func visionRectToCGFlipsYAxis() {
        let imageSize = CGSize(width: 1000, height: 1000)
        let visionRect = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)

        let cgRect = CoordinateConverter.visionRectToCG(visionRect, imageSize: imageSize)

        #expect(cgRect.origin.x == 0)
        #expect(cgRect.origin.y == 500)
        #expect(cgRect.size.width == 500)
        #expect(cgRect.size.height == 500)
    }

    @Test func visionRectToCGPreservesWidthAndHeight() {
        let imageSize = CGSize(width: 2000, height: 1000)
        let visionRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)

        let cgRect = CoordinateConverter.visionRectToCG(visionRect, imageSize: imageSize)

        #expect(cgRect.size.width == 1000)
        #expect(cgRect.size.height == 500)
    }

    @Test func visionRectToCGFullImage() {
        let imageSize = CGSize(width: 800, height: 600)
        let visionRect = CGRect(x: 0, y: 0, width: 1, height: 1)

        let cgRect = CoordinateConverter.visionRectToCG(visionRect, imageSize: imageSize)

        #expect(cgRect.origin.x == 0)
        #expect(cgRect.origin.y == 0)
        #expect(cgRect.size.width == 800)
        #expect(cgRect.size.height == 600)
    }

    @Test func visionRectToCGTopRightCorner() {
        let imageSize = CGSize(width: 100, height: 100)
        let visionRect = CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)

        let cgRect = CoordinateConverter.visionRectToCG(visionRect, imageSize: imageSize)

        #expect(cgRect.origin.x == 50)
        #expect(cgRect.origin.y == 0)
        #expect(cgRect.size.width == 50)
        #expect(cgRect.size.height == 50)
    }

    // MARK: - Portrait Swap

    @Test func applyPortraitSwapSwapsAxesForPortrait() {
        let cgPoint = CGPoint(x: 300, y: 600)
        let imageSize = CGSize(width: 1000, height: 2000)

        let swapped = CoordinateConverter.applyPortraitSwap(cgPoint, imageSize: imageSize)

        #expect(swapped.x == 600)
        #expect(swapped.y == 300)
    }

    @Test func applyPortraitSwapNoOpForLandscape() {
        let cgPoint = CGPoint(x: 300, y: 200)
        let imageSize = CGSize(width: 1920, height: 1080)

        let swapped = CoordinateConverter.applyPortraitSwap(cgPoint, imageSize: imageSize)

        #expect(swapped.x == cgPoint.x)
        #expect(swapped.y == cgPoint.y)
    }

    @Test func applyPortraitSwapNoOpForSquare() {
        let cgPoint = CGPoint(x: 500, y: 300)
        let imageSize = CGSize(width: 1000, height: 1000)

        let swapped = CoordinateConverter.applyPortraitSwap(cgPoint, imageSize: imageSize)

        #expect(swapped.x == cgPoint.x)
        #expect(swapped.y == cgPoint.y)
    }

    // MARK: - Vision to CG with Portrait

    @Test func visionToCGWithPortraitLandscapeNoSwap() {
        let visionPoint = CGPoint(x: 0.5, y: 0.5)
        let imageSize = CGSize(width: 1920, height: 1080)

        let cgPoint = CoordinateConverter.visionToCGWithPortrait(visionPoint, imageSize: imageSize)

        #expect(cgPoint.x == 960)
        #expect(cgPoint.y == 540)
    }

    @Test func visionToCGWithPortraitPortraitSwaps() {
        let visionPoint = CGPoint(x: 0.5, y: 0.5)
        let imageSize = CGSize(width: 1080, height: 1920)

        let cgPoint = CoordinateConverter.visionToCGWithPortrait(visionPoint, imageSize: imageSize)

        let expectedCG = CoordinateConverter.visionToCG(visionPoint, imageSize: imageSize)
        #expect(cgPoint.x == expectedCG.y)
        #expect(cgPoint.y == expectedCG.x)
    }

    @Test func visionToCGWithPortraitBottomLeftOrigin() {
        let visionPoint = CGPoint(x: 0, y: 0)
        let imageSize = CGSize(width: 1000, height: 2000)

        let cgPoint = CoordinateConverter.visionToCGWithPortrait(visionPoint, imageSize: imageSize)

        let cgOnly = CoordinateConverter.visionToCG(visionPoint, imageSize: imageSize)
        #expect(cgPoint.x == cgOnly.y)
        #expect(cgPoint.y == cgOnly.x)
    }

    @Test func visionToCGWithPortraitCenterPoint() {
        let visionPoint = CGPoint(x: 0.5, y: 0.5)
        let imageSize = CGSize(width: 1000, height: 2000)

        let cgPoint = CoordinateConverter.visionToCGWithPortrait(visionPoint, imageSize: imageSize)

        #expect(cgPoint.x == 1000)
        #expect(cgPoint.y == 500)
    }
}
