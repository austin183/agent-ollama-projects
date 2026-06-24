import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import CollageMaker

@MainActor
@Suite(.serialized) struct TitleManagerTests {

    // Helpers

    private func makeManager(
        titleCanvasFrame frame: CGRect,
        minWidth: CGFloat = 0,
        previewSize: CGSize = SizeConstants.defaultPreviewSize
    ) -> (manager: TitleManager, previewSize: CGSize) {
        let manager = TitleManager()
        manager.testCanvasFrameOverride = frame
        manager.testMinWidthOverride = minWidth
        return (manager, previewSize)
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
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame)

        let result = manager.hitTestTitle(location: CGPoint(x: 200, y: 415), previewSize: previewSize)

        #expect(result == TitleHitResult.resize(.left))
    }

    @Test func hitTestRightResizeHandle() {
        // Canvas frame: (400, 200, 400, 80)
        // Preview: maxX=400, threshold 10 -> [390..410]
        let frame = CGRect(x: 400, y: 200, width: 400, height: 80)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame)

        let result = manager.hitTestTitle(location: CGPoint(x: 400, y: 415), previewSize: previewSize)

        #expect(result == TitleHitResult.resize(.right))
    }

    @Test func hitTestDragRegion() {
        // Canvas frame: (400, 200, 400, 80)
        // Preview: (200, 400, 200, 40)
        // Center of preview frame
        let frame = CGRect(x: 400, y: 200, width: 400, height: 80)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame)

        let result = manager.hitTestTitle(location: CGPoint(x: 300, y: 415), previewSize: previewSize)

        #expect(result == TitleHitResult.drag)
    }

    @Test func hitTestOutsideFrame() {
        let frame = CGRect(x: 400, y: 200, width: 400, height: 80)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame)

        let result = manager.hitTestTitle(location: CGPoint(x: 100, y: 100), previewSize: previewSize)

        #expect(result == TitleHitResult.none)
    }

    @Test func hitTestBelowFrame() {
        let frame = CGRect(x: 400, y: 200, width: 400, height: 80)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame)

        let result = manager.hitTestTitle(location: CGPoint(x: 300, y: 500), previewSize: previewSize)

        #expect(result == TitleHitResult.none)
    }

    @Test func hitTestAboveFrame() {
        let frame = CGRect(x: 400, y: 200, width: 400, height: 80)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame)

        let result = manager.hitTestTitle(location: CGPoint(x: 300, y: 300), previewSize: previewSize)

        #expect(result == TitleHitResult.none)
    }

    @Test func hitTestLeftHandleAboveFrame() {
        let frame = CGRect(x: 400, y: 200, width: 400, height: 80)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame)

        let result = manager.hitTestTitle(location: CGPoint(x: 200, y: 300), previewSize: previewSize)

        #expect(result == TitleHitResult.none)
    }

    @Test func hitTestRightHandleBelowFrame() {
        let frame = CGRect(x: 400, y: 200, width: 400, height: 80)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame)

        let result = manager.hitTestTitle(location: CGPoint(x: 400, y: 500), previewSize: previewSize)

        #expect(result == TitleHitResult.none)
    }

    @Test func hitTestLeftHandleEdgeCases() {
        // Canvas frame: (400, 200, 400, 80)
        // Preview minX = 200. Handle threshold = 10.
        // Handle range: [190..210]
        let frame = CGRect(x: 400, y: 200, width: 400, height: 80)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame)

        #expect(manager.hitTestTitle(location: CGPoint(x: 190, y: 415), previewSize: previewSize) == TitleHitResult.resize(.left))
        #expect(manager.hitTestTitle(location: CGPoint(x: 210, y: 415), previewSize: previewSize) == TitleHitResult.resize(.left))
    }

    @Test func hitTestJustOutsideHandleThreshold() {
        // Preview minX = 200. Handle threshold = 10.
        // 190 - 0.5 = 189.5 is outside handle, outside frame -> none
        let frame = CGRect(x: 400, y: 200, width: 400, height: 80)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame)

        let result = manager.hitTestTitle(location: CGPoint(x: 189.5, y: 415), previewSize: previewSize)

        #expect(result == TitleHitResult.none)
    }

    @Test func hitTestWithScaledPreview() {
        // previewSize == canvasSize, so no scaling or Y-flip
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let canvasSize = SizeConstants.defaultCanvasSize
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame, previewSize: canvasSize)

        #expect(manager.hitTestTitle(location: CGPoint(x: 960, y: 540), previewSize: previewSize) == TitleHitResult.drag)
        #expect(manager.hitTestTitle(location: CGPoint(x: 10, y: 540), previewSize: previewSize) == TitleHitResult.resize(.left))
        #expect(manager.hitTestTitle(location: CGPoint(x: 1910, y: 540), previewSize: previewSize) == TitleHitResult.resize(.right))
    }

    @Test func hitTestCenterOfTitle() {
        // Zero-size frame still has handle zones around it.
        // The left handle zone covers [minX-10 .. minX+10] vertically across the frame.
        // For a zero-size frame at (480, 270) in preview, the left handle catches at x=480.
        let frame = CGRect(x: 960, y: 540, width: 0, height: 0)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame)

        let result = manager.hitTestTitle(location: CGPoint(x: 480, y: 270), previewSize: previewSize)

        #expect(result == TitleHitResult.resize(.left))
    }

    // MARK: - computeTitleDragOffset

    @Test func computeDragOffsetAtTitleCenter() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame)

        // Canvas center of title -> preview
        let startCanvas = CGPoint(x: 1160, y: 580)
        let startPreview = toPreview(CGRect(x: startCanvas.x, y: startCanvas.y, width: 0, height: 0), previewSize: previewSize).origin
        let offset = manager.computeTitleDragOffset(startLocation: startPreview, previewSize: previewSize)

        #expect(offset.x == 0)
        #expect(offset.y == 0)
    }

    @Test func computeDragOffsetProducesNonZeroOffset() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame)

        // Canvas (1000, 600) -> preview (500, 240)
        let startCanvas = CGPoint(x: 1000, y: 600)
        let startPreview = toPreview(CGRect(x: startCanvas.x, y: startCanvas.y, width: 0, height: 0), previewSize: previewSize).origin
        let offset = manager.computeTitleDragOffset(startLocation: startPreview, previewSize: previewSize)

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
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame, previewSize: canvasSize)

        // titleCenter in canvas: (500, 330)
        let titleCenter = CGPoint(x: frame.midX, y: frame.minY + frame.height / 2)
        let startPreview = CoordinateConverter.canvasToPreviewFrame(
            CGRect(x: titleCenter.x, y: titleCenter.y, width: 0, height: 0),
            in: canvasSize,
            canvasSize: canvasSize
        ).origin
        let offset = manager.computeTitleDragOffset(startLocation: startPreview, previewSize: previewSize)

        #expect(abs(offset.x) < 0.01, "offset.x=\(offset.x)")
        #expect(abs(offset.y) < 0.01, "offset.y=\(offset.y)")
    }

    @Test func computeDragOffsetTopLeft() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame)

        // Canvas (960, 540) -> preview (480, 270)
        let startCanvas = CGPoint(x: 960, y: 540)
        let startPreview = toPreview(CGRect(x: startCanvas.x, y: startCanvas.y, width: 0, height: 0), previewSize: previewSize).origin
        let offset = manager.computeTitleDragOffset(startLocation: startPreview, previewSize: previewSize)

        // titleCenter = (1160, 580). offset = (1160-960, 580-540) = (200, 40)
        #expect(offset.x == 200)
        #expect(offset.y == 40)
    }

    @Test func computeDragOffsetBottomRight() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame)

        // Canvas (1360, 620) -> preview (680, 130)
        let startCanvas = CGPoint(x: 1360, y: 620)
        let startPreview = toPreview(CGRect(x: startCanvas.x, y: startCanvas.y, width: 0, height: 0), previewSize: previewSize).origin
        let offset = manager.computeTitleDragOffset(startLocation: startPreview, previewSize: previewSize)

        // titleCenter = (1160, 580). offset = (1160-1360, 580-620) = (-200, -40)
        #expect(offset.x == -200)
        #expect(offset.y == -40)
    }

    // MARK: - computeTitleResize

    @Test func computeResizeRightEdgeExpands() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame, minWidth: 100)

        // Canvas (1400, 540) -> preview (700, 270)
        let screenLoc = toPreview(CGRect(x: 1400, y: 540, width: 0, height: 0), previewSize: previewSize).origin
        let (width, posDelta) = manager.computeTitleResize(
            screenLocation: screenLoc,
            edge: .right,
            previewSize: previewSize
        )

        // canvasX = 1400. newWidth = max(100, 1400-960) = 440
        #expect(width == 440)
        #expect(posDelta == 0)
    }

    @Test func computeResizeRightEdgeShrinks() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame, minWidth: 100)

        // Canvas (1100, 540) -> preview (550, 270)
        let screenLoc = toPreview(CGRect(x: 1100, y: 540, width: 0, height: 0), previewSize: previewSize).origin
        let (width, posDelta) = manager.computeTitleResize(
            screenLocation: screenLoc,
            edge: .right,
            previewSize: previewSize
        )

        // canvasX = 1100. newWidth = max(100, 1100-960) = 140
        #expect(width == 140)
        #expect(posDelta == 0)
    }

    @Test func computeResizeRightEdgeClampsToMinWidth() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame, minWidth: 200)

        // Canvas (1000, 540) -> preview (500, 270)
        let screenLoc = toPreview(CGRect(x: 1000, y: 540, width: 0, height: 0), previewSize: previewSize).origin
        let (width, posDelta) = manager.computeTitleResize(
            screenLocation: screenLoc,
            edge: .right,
            previewSize: previewSize
        )

        // canvasX = 1000. newWidth = max(200, 1000-960) = max(200, 40) = 200
        #expect(width == 200)
    }

    @Test func computeResizeLeftEdgeExpands() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame, minWidth: 100)

        // Canvas (800, 540) -> preview (400, 270)
        let screenLoc = toPreview(CGRect(x: 800, y: 540, width: 0, height: 0), previewSize: previewSize).origin
        let (width, posDelta) = manager.computeTitleResize(
            screenLocation: screenLoc,
            edge: .left,
            previewSize: previewSize
        )

        // canvasX = 800. newWidth = max(100, 1360-800) = 560
        #expect(width == 560)
        // dx = (400 - 560) / 2 = -80. posDelta = -80/1920
        #expect(posDelta < 0)
    }

    @Test func computeResizeLeftEdgeShrinks() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame, minWidth: 100)

        // Canvas (1200, 540) -> preview (600, 270)
        let screenLoc = toPreview(CGRect(x: 1200, y: 540, width: 0, height: 0), previewSize: previewSize).origin
        let (width, posDelta) = manager.computeTitleResize(
            screenLocation: screenLoc,
            edge: .left,
            previewSize: previewSize
        )

        // canvasX = 1200. newWidth = max(100, 1360-1200) = 160
        #expect(width == 160)
        // dx = (400 - 160) / 2 = 120. posDelta = 120/1920 > 0
        #expect(posDelta > 0)
    }

    @Test func computeResizeLeftEdgeClampsToMinWidth() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame, minWidth: 300)

        // Canvas (1300, 540) -> preview (650, 270)
        let screenLoc = toPreview(CGRect(x: 1300, y: 540, width: 0, height: 0), previewSize: previewSize).origin
        let (width, posDelta) = manager.computeTitleResize(
            screenLocation: screenLoc,
            edge: .left,
            previewSize: previewSize
        )

        // canvasX = 1300. newWidth = max(300, 1360-1300) = max(300, 60) = 300
        #expect(width == 300)
    }

    @Test func computeResizeLeftEdgePositionDelta() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame, minWidth: 100)

        // Canvas (800, 540) -> preview (400, 270)
        let screenLoc = toPreview(CGRect(x: 800, y: 540, width: 0, height: 0), previewSize: previewSize).origin
        let (_, posDelta) = manager.computeTitleResize(
            screenLocation: screenLoc,
            edge: .left,
            previewSize: previewSize
        )

        // newWidth = 560. dx = (400-560)/2 = -80. posDelta = -80/1920
        let canvasSize = SizeConstants.defaultCanvasSize
        let expectedDelta = -80.0 / canvasSize.width
        #expect(posDelta == expectedDelta)
    }

    @Test func computeResizeNoneReturnsZero() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame)

        let (width, posDelta) = manager.computeTitleResize(
            screenLocation: CGPoint(x: 500, y: 300),
            edge: TitleResizeEdge.none,
            previewSize: previewSize
        )

        #expect(width == 0)
        #expect(posDelta == 0)
    }

    @Test func computeResizeRightEdgeNoPositionDelta() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame, minWidth: 100)

        let screenLoc = toPreview(CGRect(x: 1500, y: 540, width: 0, height: 0), previewSize: previewSize).origin
        let (_, posDelta) = manager.computeTitleResize(
            screenLocation: screenLoc,
            edge: .right,
            previewSize: previewSize
        )

        #expect(posDelta == 0)
    }

    // MARK: - computeTitleDragPosition

    @Test func computeDragPositionIdentity() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame)

        // Canvas (960, 540) -> preview (480, 270)
        let screenLoc = toPreview(CGRect(x: 960, y: 540, width: 0, height: 0), previewSize: previewSize).origin
        let (posX, posY) = manager.computeTitleDragPosition(
            screenLocation: screenLoc,
            offset: CGPoint.zero,
            previewSize: previewSize
        )

        // canvasPoint = (960, 540). posX = 960/1920 = 0.5. posY = 1 - 540/1080 = 0.5
        #expect(posX == 0.5)
        #expect(posY == 0.5)
    }

    @Test func computeDragPositionWithOffset() {
        let frame = CGRect(x: 960, y: 540, width: 400, height: 80)
        let (manager, previewSize) = makeManager(titleCanvasFrame: frame)

        // Canvas (960, 540) -> preview (480, 270)
        let screenLoc = toPreview(CGRect(x: 960, y: 540, width: 0, height: 0), previewSize: previewSize).origin
        let offset = CGPoint(x: 100, y: 50)
        let (posX, posY) = manager.computeTitleDragPosition(
            screenLocation: screenLoc,
            offset: offset,
            previewSize: previewSize
        )

        // canvasPoint = (960, 540). posX = (960+100)/1920. posY = 1-(540+50)/1080
        #expect(posX == (960 + 100) / SizeConstants.defaultCanvasSize.width)
        #expect(posY == 1.0 - (540 + 50) / SizeConstants.defaultCanvasSize.height)
    }

    // MARK: - Bounds Caching

    @Test func boundsCacheHitOnPositionChange() {
        let manager = TitleManager()
        manager.titleAttrString = NSAttributedString(string: "Hello")
        manager.titleStyle = .defaultStyle()

        _ = manager.canvasFrame  // compute and cache
        let frame1 = manager.canvasFrame

        // Position-only change should hit the bounds cache
        manager.titleStyle.positionX = 0.75
        let frame2 = manager.canvasFrame

        // Frame origin should differ (position changed)
        #expect(frame1?.origin.x != frame2?.origin.x, "position change should shift frame")
        // But frame size should be the same (bounds cached)
        #expect(frame1?.size == frame2?.size, "cached bounds should produce same size")
    }

    @Test func boundsCacheInvalidateOnFontChange() {
        let manager = TitleManager()
        manager.titleAttrString = NSAttributedString(string: "Hello")
        manager.titleStyle = .defaultStyle()

        _ = manager.canvasFrame  // compute and cache
        let size1 = manager.canvasFrame?.size

        // Font change should invalidate the bounds cache
        manager.titleStyle.fontSize = 72
        let size2 = manager.canvasFrame?.size

        // Size should differ (bounds recomputed)
        #expect(size1 != size2, "font change should invalidate bounds cache and change size")
    }

    @Test func boundsCacheInvalidateOnWidthChange() {
        let manager = TitleManager()
        manager.titleAttrString = NSAttributedString(string: "Hello")
        manager.titleStyle = .defaultStyle()

        _ = manager.canvasFrame  // compute and cache
        let frame1 = manager.canvasFrame

        // Width change should invalidate the bounds cache
        manager.titleStyle.width = 600
        let frame2 = manager.canvasFrame

        #expect(frame1?.width != frame2?.width, "width change should invalidate bounds cache")
    }

    @Test func boundsCacheMissOnEmptyTitle() {
        let manager = TitleManager()
        manager.titleAttrString = NSAttributedString(string: "Hello")
        manager.titleStyle = .defaultStyle()

        _ = manager.canvasFrame  // compute and cache
        #expect(manager.canvasFrame != nil)

        // Clearing title should invalidate cache and return nil
        manager.titleAttrString = NSAttributedString(string: "")
        #expect(manager.canvasFrame == nil)
    }

    // MARK: - reset()

    @Test func resetClearsTitleState() {
        let manager = TitleManager()
        manager.titleAttrString = NSAttributedString(string: "Hello")
        manager.titleStyle.positionX = 0.3
        manager.titleStyle.fontSize = 64
        manager.isDraggingTitle = true

        manager.reset()

        #expect(manager.title == "")
        #expect(manager.titleStyle == .defaultStyle())
        #expect(manager.isDraggingTitle == false)
    }

    @Test func resetClearsCanvasFrame() {
        let manager = TitleManager()
        manager.titleAttrString = NSAttributedString(string: "Hello")
        manager.titleStyle = .defaultStyle()

        #expect(manager.canvasFrame != nil)

        manager.reset()

        #expect(manager.canvasFrame == nil)
    }

    @Test func resetClearsMinWidth() {
        let manager = TitleManager()
        manager.titleAttrString = NSAttributedString(string: "Hello")
        manager.titleStyle = .defaultStyle()

        #expect(manager.minWidth > 0)

        manager.reset()

        #expect(manager.minWidth == 0)
    }

    @Test func resetAllowsNewTitle() {
        let manager = TitleManager()
        manager.titleAttrString = NSAttributedString(string: "First")
        manager.titleStyle = .defaultStyle()
        _ = manager.canvasFrame

        manager.reset()
        #expect(manager.canvasFrame == nil)

        manager.titleAttrString = NSAttributedString(string: "Second")
        #expect(manager.canvasFrame != nil)
    }

    // MARK: - canvasFrame

    @Test func canvasFrameNilForEmptyTitle() {
        let manager = TitleManager()
        #expect(manager.canvasFrame == nil)
    }

    @Test func canvasFrameNotNilWithTitle() {
        let manager = TitleManager()
        manager.titleAttrString = NSAttributedString(string: "Hello")
        manager.titleStyle = .defaultStyle()

        let frame = manager.canvasFrame
        #expect(frame != nil)
        #expect(frame!.width > 0)
        #expect(frame!.height > 0)
    }

    @Test func canvasFrameReflectsPosition() {
        let manager = TitleManager()
        manager.titleAttrString = NSAttributedString(string: "Hello")
        manager.titleStyle = .defaultStyle()

        manager.titleStyle.positionX = 0.1
        let frameLeft = manager.canvasFrame

        manager.titleStyle.positionX = 0.9
        let frameRight = manager.canvasFrame

        #expect(frameLeft!.minX < frameRight!.minX, "positionX 0.9 should be to the right of 0.1")
    }

    @Test func canvasFrameUsesOverride() {
        let (manager, _) = makeManager(titleCanvasFrame: CGRect(x: 100, y: 200, width: 300, height: 50))
        // With override set directly, canvasFrame returns the override
        #expect(manager.canvasFrame == CGRect(x: 100, y: 200, width: 300, height: 50))
    }

    // MARK: - Protocol-based updateImage / finishDrag

    private final class TrackingPreviewUpdatable: PreviewUpdatable {
        var updateTitleImageCalls = 0
        var lastAttrString: NSAttributedString?
        var lastStyle: TitleStyle?
        var lastCanvasSize: CGSize = .zero
        var incrementTitleVersionCalls = 0
        var cancelDebouncerCalls: [String] = []

        func updateTitleImage(attrString: NSAttributedString, style: TitleStyle, canvasSize: CGSize) {
            updateTitleImageCalls += 1
            lastAttrString = attrString
            lastStyle = style
            lastCanvasSize = canvasSize
        }

        func incrementTitleVersion() {
            incrementTitleVersionCalls += 1
        }

        func updateBackground(config: BackgroundConfig, canvasSize: CGSize, backgroundImage: CGImage?, previewSize: CGSize) {
            // Not used by TitleManager
        }

        func cancelDebouncer(id: String) {
            cancelDebouncerCalls.append(id)
        }
    }

    @Test func updateImageCallsUpdaterMethods() {
        let manager = TitleManager()
        manager.titleAttrString = NSAttributedString(string: "Hello")
        manager.titleStyle = .defaultStyle()

        let updater = TrackingPreviewUpdatable()
        manager.updateImage(updater: updater)

        #expect(updater.incrementTitleVersionCalls == 1)
        #expect(updater.updateTitleImageCalls == 1)
        #expect(updater.lastAttrString?.string == "Hello")
        #expect(updater.lastCanvasSize == SizeConstants.defaultCanvasSize)
    }

    @Test func finishDragCancelsDebouncerAndSaves() {
        let manager = TitleManager()
        manager.titleAttrString = NSAttributedString(string: "Hello")
        manager.titleStyle = .defaultStyle()

        let updater = TrackingPreviewUpdatable()
        manager.finishDrag(updater: updater)

        #expect(updater.cancelDebouncerCalls == ["titleImage"])
        #expect(updater.incrementTitleVersionCalls == 1)
        #expect(updater.updateTitleImageCalls == 1)
    }

    @Test func finishDragPassesCurrentStyleToUpdater() {
        let manager = TitleManager()
        manager.titleAttrString = NSAttributedString(string: "Test")
        manager.titleStyle.fontSize = 72
        manager.titleStyle.positionX = 0.3

        let updater = TrackingPreviewUpdatable()
        manager.finishDrag(updater: updater)

        #expect(updater.lastStyle?.fontSize == 72)
        #expect(updater.lastStyle?.positionX == 0.3)
    }
}
