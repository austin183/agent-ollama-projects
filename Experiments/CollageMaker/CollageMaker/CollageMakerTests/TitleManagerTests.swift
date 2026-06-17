import CoreGraphics
import Testing
@testable import CollageMaker

@MainActor
@Suite(.serialized) struct TitleManagerTests {

    // Helpers

    private func makeHandler(
        titleCanvasFrame frame: CGRect,
        previewSize: CGSize = SizeConstants.defaultPreviewSize
    ) -> TitleDragHandler {
        TitleDragHandler(titleCanvasFrame: frame, previewSize: previewSize)
    }

    /// Converts a canvas rect to its preview-space equivalent for test assertions.
    private func toPreview(_ canvasRect: CGRect, previewSize: CGSize = SizeConstants.defaultPreviewSize) -> CGRect {
        CoordinateConverter.canvasToPreviewFrame(canvasRect, in: previewSize, canvasSize: SizeConstants.defaultCanvasSize)
    }

    // MARK: - hitTestTitle

    @Test func hitTestLeftResizeHandle() {
        // Canvas frame: (400, 200, 400, 80)
        // Preview: minX=200, minY=400, width=200, height=40
        // Left handle at preview minX=200, threshold 10 on each side -> [190..210]
        let frame = CGRect(x: 400, y: 200, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        let result = handler.hitTest(at: CGPoint(x: 200, y: 415))

        #expect(result == .resize(.left))
    }

    @Test func hitTestRightResizeHandle() {
        // Canvas frame: (400, 200, 400, 80)
        // Preview: maxX=400, threshold 10 -> [390..410]
        let frame = CGRect(x: 400, y: 200, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        let result = handler.hitTest(at: CGPoint(x: 400, y: 415))

        #expect(result == .resize(.right))
    }

    @Test func hitTestDragRegion() {
        // Canvas frame: (400, 200, 400, 80)
        // Preview: (200, 400, 200, 40)
        // Center of preview frame
        let frame = CGRect(x: 400, y: 200, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        let result = handler.hitTest(at: CGPoint(x: 300, y: 415))

        #expect(result == .drag)
    }

    @Test func hitTestOutsideFrame() {
        let frame = CGRect(x: 400, y: 200, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        let result = handler.hitTest(at: CGPoint(x: 100, y: 100))

        #expect(result == .none)
    }

    @Test func hitTestBelowFrame() {
        let frame = CGRect(x: 400, y: 200, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        let result = handler.hitTest(at: CGPoint(x: 300, y: 500))

        #expect(result == .none)
    }

    @Test func hitTestAboveFrame() {
        let frame = CGRect(x: 400, y: 200, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        let result = handler.hitTest(at: CGPoint(x: 300, y: 300))

        #expect(result == .none)
    }

    @Test func hitTestLeftHandleAboveFrame() {
        let frame = CGRect(x: 400, y: 200, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        let result = handler.hitTest(at: CGPoint(x: 200, y: 300))

        #expect(result == .none)
    }

    @Test func hitTestRightHandleBelowFrame() {
        let frame = CGRect(x: 400, y: 200, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        let result = handler.hitTest(at: CGPoint(x: 400, y: 500))

        #expect(result == .none)
    }

    @Test func hitTestLeftHandleEdgeCases() {
        // Canvas frame: (400, 200, 400, 80)
        // Preview minX = 200. Handle threshold = 10.
        // Handle range: [190..210]
        let frame = CGRect(x: 400, y: 200, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        #expect(handler.hitTest(at: CGPoint(x: 190, y: 415)) == .resize(.left))
        #expect(handler.hitTest(at: CGPoint(x: 210, y: 415)) == .resize(.left))
    }

    @Test func hitTestJustOutsideHandleThreshold() {
        // Preview minX = 200. Handle threshold = 10.
        // 190 - 0.5 = 189.5 is outside handle, outside frame -> none
        let frame = CGRect(x: 400, y: 200, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        let result = handler.hitTest(at: CGPoint(x: 189.5, y: 415))

        #expect(result == .none)
    }

    @Test func hitTestWithScaledPreview() {
        // previewSize == canvasSize, so no scaling or Y-flip
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let handler = makeHandler(titleCanvasFrame: frame, previewSize: SizeConstants.defaultCanvasSize)

        #expect(handler.hitTest(at: CGPoint(x: 960, y: 540)) == .drag)
        #expect(handler.hitTest(at: CGPoint(x: 10, y: 540)) == .resize(.left))
        #expect(handler.hitTest(at: CGPoint(x: 1910, y: 540)) == .resize(.right))
    }

    @Test func hitTestCenterOfTitle() {
        // Zero-size frame still has handle zones around it.
        // The left handle zone covers [minX-10 .. minX+10] vertically across the frame.
        // For a zero-size frame at (480, 270) in preview, the left handle catches at x=480.
        let frame = CGRect(x: 960, y: 540, width: 0, height: 0)
        let handler = makeHandler(titleCanvasFrame: frame)

        let result = handler.hitTest(at: CGPoint(x: 480, y: 270))

        #expect(result == .resize(.left))
    }

    // MARK: - computeTitleDragOffset

    @Test func computeDragOffsetAtTitleCenter() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        // Canvas center of title -> preview
        let startCanvas = CGPoint(x: 1160, y: 580)
        let startPreview = toPreview(CGRect(x: startCanvas.x, y: startCanvas.y, width: 0, height: 0)).origin
        let offset = handler.computeDragOffset(startLocation: startPreview)

        #expect(offset.x == 0)
        #expect(offset.y == 0)
    }

    @Test func computeDragOffsetProducesNonZeroOffset() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        // Canvas (1000, 600) -> preview (500, 240)
        let startCanvas = CGPoint(x: 1000, y: 600)
        let startPreview = toPreview(CGRect(x: startCanvas.x, y: startCanvas.y, width: 0, height: 0)).origin
        let offset = handler.computeDragOffset(startLocation: startPreview)

        // titleCenter = (1160, 580). startCanvas = (1000, 600).
        // offset = (1160-1000, 580-600) = (160, -20)
        let expectedY: CGFloat = -20
        #expect(abs(offset.x - 160) < 0.01, "offset.x=\(offset.x)")
        #expect(abs(offset.y - expectedY) < 0.01, "offset.y=\(offset.y)")
    }

    @Test func computeDragOffsetWithScaledPreview() {
        // previewSize == canvasSize, Y-flip still applies.
        // Use toPreview to convert canvas center to screen coords.
        let canvasSize = SizeConstants.defaultCanvasSize
        let frame = CGRect(x: 400, y: 300, width: 200, height: 60)
        let handler = makeHandler(titleCanvasFrame: frame, previewSize: canvasSize)

        // titleCenter in canvas: (500, 330)
        let titleCenter = CGPoint(x: frame.midX, y: frame.minY + frame.height / 2)
        let startPreview = CoordinateConverter.canvasToPreviewFrame(
            CGRect(x: titleCenter.x, y: titleCenter.y, width: 0, height: 0),
            in: canvasSize,
            canvasSize: canvasSize
        ).origin
        let offset = handler.computeDragOffset(startLocation: startPreview)

        #expect(abs(offset.x) < 0.01, "offset.x=\(offset.x)")
        #expect(abs(offset.y) < 0.01, "offset.y=\(offset.y)")
    }

    @Test func computeDragOffsetTopLeft() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        // Canvas (960, 540) -> preview (480, 270)
        let startCanvas = CGPoint(x: 960, y: 540)
        let startPreview = toPreview(CGRect(x: startCanvas.x, y: startCanvas.y, width: 0, height: 0)).origin
        let offset = handler.computeDragOffset(startLocation: startPreview)

        // titleCenter = (1160, 580). offset = (1160-960, 580-540) = (200, 40)
        #expect(offset.x == 200)
        #expect(offset.y == 40)
    }

    @Test func computeDragOffsetBottomRight() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        // Canvas (1360, 620) -> preview (680, 130)
        let startCanvas = CGPoint(x: 1360, y: 620)
        let startPreview = toPreview(CGRect(x: startCanvas.x, y: startCanvas.y, width: 0, height: 0)).origin
        let offset = handler.computeDragOffset(startLocation: startPreview)

        // titleCenter = (1160, 580). offset = (1160-1360, 580-620) = (-200, -40)
        #expect(offset.x == -200)
        #expect(offset.y == -40)
    }

    // MARK: - computeTitleResize

    @Test func computeResizeRightEdgeExpands() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        // Canvas (1400, 540) -> preview (700, 270)
        let screenLoc = toPreview(CGRect(x: 1400, y: 540, width: 0, height: 0)).origin
        let (width, posDelta) = handler.computeResizeWidth(
            screenLocation: screenLoc,
            edge: .right,
            currentFrame: frame,
            minWidth: 100,
            canvasSize: SizeConstants.defaultCanvasSize
        )

        // canvasX = 1400. newWidth = max(100, 1400-960) = 440
        #expect(width == 440)
        #expect(posDelta == 0)
    }

    @Test func computeResizeRightEdgeShrinks() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        // Canvas (1100, 540) -> preview (550, 270)
        let screenLoc = toPreview(CGRect(x: 1100, y: 540, width: 0, height: 0)).origin
        let (width, posDelta) = handler.computeResizeWidth(
            screenLocation: screenLoc,
            edge: .right,
            currentFrame: frame,
            minWidth: 100,
            canvasSize: SizeConstants.defaultCanvasSize
        )

        // canvasX = 1100. newWidth = max(100, 1100-960) = 140
        #expect(width == 140)
        #expect(posDelta == 0)
    }

    @Test func computeResizeRightEdgeClampsToMinWidth() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        // Canvas (1000, 540) -> preview (500, 270)
        let screenLoc = toPreview(CGRect(x: 1000, y: 540, width: 0, height: 0)).origin
        let (width, posDelta) = handler.computeResizeWidth(
            screenLocation: screenLoc,
            edge: .right,
            currentFrame: frame,
            minWidth: 200,
            canvasSize: SizeConstants.defaultCanvasSize
        )

        // canvasX = 1000. newWidth = max(200, 1000-960) = max(200, 40) = 200
        #expect(width == 200)
    }

    @Test func computeResizeLeftEdgeExpands() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        // Canvas (800, 540) -> preview (400, 270)
        let screenLoc = toPreview(CGRect(x: 800, y: 540, width: 0, height: 0)).origin
        let (width, posDelta) = handler.computeResizeWidth(
            screenLocation: screenLoc,
            edge: .left,
            currentFrame: frame,
            minWidth: 100,
            canvasSize: SizeConstants.defaultCanvasSize
        )

        // canvasX = 800. newWidth = max(100, 1360-800) = 560
        #expect(width == 560)
        // dx = (400 - 560) / 2 = -80. posDelta = -80/1920
        #expect(posDelta < 0)
    }

    @Test func computeResizeLeftEdgeShrinks() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        // Canvas (1200, 540) -> preview (600, 270)
        let screenLoc = toPreview(CGRect(x: 1200, y: 540, width: 0, height: 0)).origin
        let (width, posDelta) = handler.computeResizeWidth(
            screenLocation: screenLoc,
            edge: .left,
            currentFrame: frame,
            minWidth: 100,
            canvasSize: SizeConstants.defaultCanvasSize
        )

        // canvasX = 1200. newWidth = max(100, 1360-1200) = 160
        #expect(width == 160)
        // dx = (400 - 160) / 2 = 120. posDelta = 120/1920 > 0
        #expect(posDelta > 0)
    }

    @Test func computeResizeLeftEdgeClampsToMinWidth() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        // Canvas (1300, 540) -> preview (650, 270)
        let screenLoc = toPreview(CGRect(x: 1300, y: 540, width: 0, height: 0)).origin
        let (width, posDelta) = handler.computeResizeWidth(
            screenLocation: screenLoc,
            edge: .left,
            currentFrame: frame,
            minWidth: 300,
            canvasSize: SizeConstants.defaultCanvasSize
        )

        // canvasX = 1300. newWidth = max(300, 1360-1300) = max(300, 60) = 300
        #expect(width == 300)
    }

    @Test func computeResizeLeftEdgePositionDelta() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        // Canvas (800, 540) -> preview (400, 270)
        let screenLoc = toPreview(CGRect(x: 800, y: 540, width: 0, height: 0)).origin
        let (_, posDelta) = handler.computeResizeWidth(
            screenLocation: screenLoc,
            edge: .left,
            currentFrame: frame,
            minWidth: 100,
            canvasSize: SizeConstants.defaultCanvasSize
        )

        // newWidth = 560. dx = (400-560)/2 = -80. posDelta = -80/1920
        let canvasSize = SizeConstants.defaultCanvasSize
        let expectedDelta = -80.0 / canvasSize.width
        #expect(posDelta == expectedDelta)
    }

    @Test func computeResizeNoneReturnsZero() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        let (width, posDelta) = handler.computeResizeWidth(
            screenLocation: CGPoint(x: 500, y: 300),
            edge: .none,
            currentFrame: frame,
            minWidth: 100,
            canvasSize: SizeConstants.defaultCanvasSize
        )

        #expect(width == 0)
        #expect(posDelta == 0)
    }

    @Test func computeResizeRightEdgeNoPositionDelta() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        let screenLoc = toPreview(CGRect(x: 1500, y: 540, width: 0, height: 0)).origin
        let (_, posDelta) = handler.computeResizeWidth(
            screenLocation: screenLoc,
            edge: .right,
            currentFrame: frame,
            minWidth: 100,
            canvasSize: SizeConstants.defaultCanvasSize
        )

        #expect(posDelta == 0)
    }

    // MARK: - computeDragPosition

    @Test func computeDragPositionIdentity() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        // Canvas (960, 540) -> preview (480, 270)
        let screenLoc = toPreview(CGRect(x: 960, y: 540, width: 0, height: 0)).origin
        let (posX, posY) = handler.computeDragPosition(
            screenLocation: screenLoc,
            offset: .zero,
            canvasSize: SizeConstants.defaultCanvasSize
        )

        // canvasPoint = (960, 540). posX = 960/1920 = 0.5. posY = 1 - 540/1080 = 0.5
        #expect(posX == 0.5)
        #expect(posY == 0.5)
    }

    @Test func computeDragPositionWithOffset() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let handler = makeHandler(titleCanvasFrame: frame)

        // Canvas (960, 540) -> preview (480, 270)
        let screenLoc = toPreview(CGRect(x: 960, y: 540, width: 0, height: 0)).origin
        let offset = CGPoint(x: 100, y: 50)
        let (posX, posY) = handler.computeDragPosition(
            screenLocation: screenLoc,
            offset: offset,
            canvasSize: SizeConstants.defaultCanvasSize
        )

        // canvasPoint = (960, 540). posX = (960+100)/1920. posY = 1-(540+50)/1080
        #expect(posX == (960 + 100) / SizeConstants.defaultCanvasSize.width)
        #expect(posY == 1.0 - (540 + 50) / SizeConstants.defaultCanvasSize.height)
    }
}
