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
}
