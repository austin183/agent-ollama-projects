import CoreGraphics
import Foundation
import Testing
@testable import CollageMaker

@MainActor
@Suite(.serialized) struct CropManagerTests {

    @Test func computeInitialCropsCreatesEntries() {
        let manager = CropManager()
        let image = createTestImageItem(size: CGSize(width: 200, height: 200))
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)

        manager.computeInitialCrops(panels: panels, images: [image])
        #expect(manager.cropMap.count == 1)
        #expect(manager.cropMap[panels[0].id] != nil)
    }

    @Test func computeInitialCropsMultiplePanels() {
        let manager = CropManager()
        let images = (0..<4).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        let panels = LayoutGenerator.generate(numImages: 4, style: .uniform)

        manager.computeInitialCrops(panels: panels, images: images)
        #expect(manager.cropMap.count == 4)
    }

    @Test func cropsArraySortedByY() {
        let manager = CropManager()
        let images = (0..<4).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        let panels = LayoutGenerator.generate(numImages: 4, style: .uniform)

        manager.computeInitialCrops(panels: panels, images: images)
        let sorted = manager.cropsArray
        for i in 0..<sorted.count - 1 {
            #expect(sorted[i].destinationRect.origin.y <= sorted[i + 1].destinationRect.origin.y)
        }
    }

    @Test func panCropMovesSourceRect() {
        let manager = CropManager()
        let image = createTestImageItem(size: CGSize(width: 4000, height: 4000))
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)

        manager.computeInitialCrops(panels: panels, images: [image])
        let panelId = panels[0].id

        manager.beginPinch(panelId: panelId)
        manager.pinch(magnification: 0.5)
        manager.applyPinch(panelId: panelId, panels: panels, images: [image])

        let afterZoom = manager.cropMap[panelId]!.sourceRect.origin

        manager.beginPan(panelId: panelId)
        manager.pan(by: CGSize(width: 100, height: 100))
        manager.applyPan(panelId: panelId, panels: panels, images: [image])

        let afterPan = manager.cropMap[panelId]!.sourceRect.origin
        #expect(afterPan.x < afterZoom.x || afterPan.y < afterZoom.y)
    }

    @Test func panCropClampsToBounds() {
        let manager = CropManager()
        let image = createTestImageItem(size: CGSize(width: 100, height: 100))
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)

        manager.computeInitialCrops(panels: panels, images: [image])
        let panelId = panels[0].id

        manager.beginPan(panelId: panelId)
        manager.pan(by: CGSize(width: -5000, height: -5000))
        manager.applyPan(panelId: panelId, panels: panels, images: [image])

        let crop = manager.cropMap[panelId]!
        #expect(crop.sourceRect.origin.x >= 0)
        #expect(crop.sourceRect.origin.y >= 0)
    }

    @Test func panCropClampsMaxBounds() {
        let manager = CropManager()
        let image = createTestImageItem(size: CGSize(width: 100, height: 100))
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)

        manager.computeInitialCrops(panels: panels, images: [image])
        let panelId = panels[0].id

        manager.beginPan(panelId: panelId)
        manager.pan(by: CGSize(width: 5000, height: 5000))
        manager.applyPan(panelId: panelId, panels: panels, images: [image])

        let crop = manager.cropMap[panelId]!
        let maxOX = max(0, image.size.width - crop.sourceRect.width)
        let maxOY = max(0, image.size.height - crop.sourceRect.height)
        #expect(crop.sourceRect.origin.x <= maxOX + 1)
        #expect(crop.sourceRect.origin.y <= maxOY + 1)
    }

    @Test func pinchZoomInReducesCropSize() {
        let manager = CropManager()
        let image = createTestImageItem(size: CGSize(width: 4000, height: 4000))
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)

        manager.computeInitialCrops(panels: panels, images: [image])
        let panelId = panels[0].id
        let originalSize = manager.cropMap[panelId]!.sourceRect.size

        manager.beginPinch(panelId: panelId)
        manager.pinch(magnification: 2.0)
        manager.applyPinch(panelId: panelId, panels: panels, images: [image])

        let newSize = manager.cropMap[panelId]!.sourceRect.size
        #expect(newSize.width < originalSize.width)
        #expect(newSize.height < originalSize.height)
    }

    @Test func pinchZoomOutIncreasesCropSize() {
        let manager = CropManager()
        let image = createTestImageItem(size: CGSize(width: 8000, height: 4000))
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)

        manager.computeInitialCrops(panels: panels, images: [image])
        let panelId = panels[0].id

        manager.beginPinch(panelId: panelId)
        manager.pinch(magnification: 4.0)
        manager.applyPinch(panelId: panelId, panels: panels, images: [image])

        let zoomedInSize = manager.cropMap[panelId]!.sourceRect.size

        manager.beginPinch(panelId: panelId)
        manager.pinch(magnification: 0.5)
        manager.applyPinch(panelId: panelId, panels: panels, images: [image])

        let newSize = manager.cropMap[panelId]!.sourceRect.size
        #expect(newSize.width > zoomedInSize.width)
        #expect(newSize.height > zoomedInSize.height)
    }

    @Test func pinchZoomClampsToFullImage() {
        let manager = CropManager()
        let image = createTestImageItem(size: CGSize(width: 8000, height: 4000))
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)

        manager.computeInitialCrops(panels: panels, images: [image])
        let panelId = panels[0].id

        manager.beginPinch(panelId: panelId)
        manager.pinch(magnification: 0.1)
        manager.applyPinch(panelId: panelId, panels: panels, images: [image])

        let crop = manager.cropMap[panelId]!
        #expect(crop.sourceRect.width <= image.size.width + 1)
        #expect(crop.sourceRect.height <= image.size.height + 1)
    }

    @Test func pinchZoomClampsTo2xZoomIn() {
        let manager = CropManager()
        let image = createTestImageItem(size: CGSize(width: 4000, height: 4000))
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)

        manager.computeInitialCrops(panels: panels, images: [image])
        let panelId = panels[0].id

        manager.beginPinch(panelId: panelId)
        manager.pinch(magnification: 10.0)
        manager.applyPinch(panelId: panelId, panels: panels, images: [image])

        let crop = manager.cropMap[panelId]!
        let panelSize = crop.destinationRect.size
        let zoom = crop.sourceRect.width / panelSize.width
        #expect(zoom >= 0.5 - 0.001)
        #expect(zoom <= 0.55)
    }

    @Test func resetCropRestoresInitial() {
        let manager = CropManager()
        let image = createTestImageItem(size: CGSize(width: 400, height: 400))
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)

        manager.computeInitialCrops(panels: panels, images: [image])
        let panelId = panels[0].id
        let initial = manager.cropMap[panelId]!.sourceRect

        manager.beginPan(panelId: panelId)
        manager.pan(by: CGSize(width: 100, height: 100))
        manager.applyPan(panelId: panelId, panels: panels, images: [image])

        manager.resetCrop(panelId: panelId, panels: panels, images: [image])
        let reset = manager.cropMap[panelId]!.sourceRect
        #expect(reset == initial)
    }

    @Test func resetAllCrops() {
        let manager = CropManager()
        let images = (0..<3).map { _ in createTestImageItem(size: CGSize(width: 400, height: 400)) }
        let panels = LayoutGenerator.generate(numImages: 3, style: .uniform)

        manager.computeInitialCrops(panels: panels, images: images)
        let initial = manager.cropMap

        for panel in panels {
            manager.beginPan(panelId: panel.id)
            manager.pan(by: CGSize(width: 50, height: 50))
            manager.applyPan(panelId: panel.id, panels: panels, images: images)
        }

        manager.resetAllCrops(panels: panels, images: images)
        #expect(manager.cropMap.count == initial.count)
    }

    @Test func computeCropsFromSaliency() {
        let manager = CropManager()
        let image = createTestImageItem(size: CGSize(width: 400, height: 400))
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)
        let saliency = [0: SaliencyResult(center: CGPoint(x: 350, y: 350), radius: 50, confidence: 0.95)]

        manager.computeCropsFromSaliency(panels: panels, images: [image], results: saliency)
        #expect(manager.cropMap.count == 1)
        let crop = manager.cropMap[panels[0].id]!
        #expect(crop.sourceRect.origin.x >= 0)
        #expect(crop.sourceRect.origin.y >= 0)
    }

    @Test func computeInitialCropsSkipsMissingImage() {
        let manager = CropManager()
        let panels = LayoutGenerator.generate(numImages: 3, style: .uniform)
        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]

        manager.computeInitialCrops(panels: panels, images: images)
        #expect(manager.cropMap.count == 1)
    }

    // MARK: - Coordinate Conversion Tests

    @Test func canvasToPreviewFrameIdentityForMatchingSize() {
        let canvasSize = SizeConstants.defaultCanvasSize
        let previewSize = canvasSize
        let canvasRect = CGRect(x: 100, y: 200, width: 200, height: 150)

        let previewFrame = CropManager.canvasToPreviewFrame(canvasRect, in: previewSize)

        #expect(previewFrame.origin.x == canvasRect.origin.x)
        #expect(previewFrame.size.width == canvasRect.width)
        #expect(previewFrame.size.height == canvasRect.height)
    }

    @Test func canvasToPreviewFrameFlipsYAxis() {
        let previewSize = SizeConstants.defaultPreviewSize
        let canvasRect = CGRect(x: 0, y: 0, width: 100, height: 100)

        let previewFrame = CropManager.canvasToPreviewFrame(canvasRect, in: previewSize)

        #expect(previewFrame.origin.y > 0)
    }

    @Test func canvasToPreviewFrameScalesCorrectly() {
        let previewSize = SizeConstants.defaultPreviewSize
        let canvasRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let previewFrame = CropManager.canvasToPreviewFrame(canvasRect, in: previewSize)

        #expect(previewFrame.size.width == previewSize.width)
        #expect(previewFrame.size.height == previewSize.height)
    }

    @Test func canvasToPreviewFrameHandlesOffset() {
        let previewSize = CGSize(width: 1280, height: 720)
        let canvasRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let previewFrame = CropManager.canvasToPreviewFrame(canvasRect, in: previewSize)

        #expect(previewFrame.origin.x >= 0)
        #expect(previewFrame.origin.y >= 0)
        #expect(previewFrame.maxX <= previewSize.width)
        #expect(previewFrame.maxY <= previewSize.height)
    }

    // MARK: - Screen to Canvas Tests

    @Test func screenToCanvasPointIdentityForMatchingSize() {
        let canvasSize = SizeConstants.defaultCanvasSize
        let screenPoint = CGPoint(x: 960, y: 540)

        let canvasPoint = CropManager.screenToCanvasPoint(screenPoint, in: canvasSize)

        #expect(canvasPoint.x == screenPoint.x)
        #expect(canvasPoint.y == screenPoint.y)
    }

    @Test func screenToCanvasPointFlipsYAxis() {
        let previewSize = SizeConstants.defaultCanvasSize
        let screenPoint = CGPoint(x: 960, y: 0)

        let canvasPoint = CropManager.screenToCanvasPoint(screenPoint, in: previewSize)

        #expect(canvasPoint.y == SizeConstants.defaultCanvasSize.height)
    }

    @Test func screenToCanvasPointScalesDown() {
        let previewSize = SizeConstants.defaultPreviewSize
        let screenPoint = CGPoint(x: 480, y: 270)

        let canvasPoint = CropManager.screenToCanvasPoint(screenPoint, in: previewSize)

        #expect(canvasPoint.x == 960)
        #expect(canvasPoint.y == 540)
    }

    // MARK: - Hit Testing Tests

    @Test func hitTestPanelReturnsPanelWhenLocationInside() {
        let panelId = UUID()
        let panelFrame = CGRect(x: 100, y: 100, width: 200, height: 150)
        let panelFrames: [UUID: CGRect] = [panelId: panelFrame]

        let hitId = CropManager.hitTestPanel(at: CGPoint(x: 150, y: 150), panelFrames: panelFrames, previewSize: CGSize(width: 800, height: 600))

        #expect(hitId == panelId)
    }

    @Test func hitTestPanelReturnsNilWhenLocationOutside() {
        let panelId = UUID()
        let panelFrame = CGRect(x: 100, y: 100, width: 200, height: 150)
        let panelFrames: [UUID: CGRect] = [panelId: panelFrame]

        let hitId = CropManager.hitTestPanel(at: CGPoint(x: 50, y: 50), panelFrames: panelFrames, previewSize: CGSize(width: 800, height: 600))

        #expect(hitId == nil)
    }

    @Test func hitTestPanelReturnsNilForEmptyFrames() {
        let panelFrames: [UUID: CGRect] = [:]

        let hitId = CropManager.hitTestPanel(at: CGPoint(x: 100, y: 100), panelFrames: panelFrames, previewSize: CGSize(width: 800, height: 600))

        #expect(hitId == nil)
    }

    @Test func hitTestPanelReturnsFirstHit() {
        let panelId1 = UUID()
        let panelId2 = UUID()
        let frame1 = CGRect(x: 0, y: 0, width: 200, height: 200)
        let frame2 = CGRect(x: 100, y: 100, width: 200, height: 200)
        let panelFrames: [UUID: CGRect] = [panelId1: frame1, panelId2: frame2]

        let hitId = CropManager.hitTestPanel(at: CGPoint(x: 150, y: 150), panelFrames: panelFrames, previewSize: CGSize(width: 800, height: 600))

        #expect(hitId == panelId1 || hitId == panelId2)
    }

    // MARK: - Zoom Scaling Tests

    @Test func translateZoomUsesDivisionNotMultiplication() {
        let baseZoom: CGFloat = 1.0
        let magnification: CGFloat = 2.0
        let imageSize = CGSize(width: 4000, height: 4000)
        let panelSize = CGSize(width: 960, height: 540)

        let newZoom = CropManager.translateZoom(magnification: magnification, baseZoom: baseZoom, imageSize: imageSize, panelSize: panelSize)

        #expect(newZoom == 0.5)
    }

    @Test func translateZoomClampsToFullImageMax() {
        let baseZoom: CGFloat = 10.0
        let magnification: CGFloat = 0.5
        let imageSize = CGSize(width: 8000, height: 4000)
        let panelSize = CGSize(width: 1920, height: 1080)

        let newZoom = CropManager.translateZoom(magnification: magnification, baseZoom: baseZoom, imageSize: imageSize, panelSize: panelSize)

        let maxZoomOut = Swift.min(imageSize.width / panelSize.width, imageSize.height / panelSize.height)
        #expect(newZoom <= maxZoomOut + 0.0001)
        #expect(newZoom >= maxZoomOut - 0.0001)
    }

    @Test func translateZoomClampsTo2xZoomIn() {
        let baseZoom: CGFloat = 0.5
        let magnification: CGFloat = 2.0
        let imageSize = CGSize(width: 4000, height: 4000)
        let panelSize = CGSize(width: 960, height: 540)

        let newZoom = CropManager.translateZoom(magnification: magnification, baseZoom: baseZoom, imageSize: imageSize, panelSize: panelSize)

        #expect(newZoom >= 0.5 - 0.0001)
        #expect(newZoom <= 0.5 + 0.0001)
    }

    @Test func translateZoomIdentityForMagnificationOne() {
        let baseZoom: CGFloat = 1.5
        let imageSize = CGSize(width: 4000, height: 4000)
        let panelSize = CGSize(width: 960, height: 540)

        let newZoom = CropManager.translateZoom(magnification: 1.0, baseZoom: baseZoom, imageSize: imageSize, panelSize: panelSize)

        #expect(newZoom == baseZoom)
    }

    // MARK: - Source Rect In Container Tests

    @Test func sourceRectInContainerFitsImageInContainer() {
        let crop = CropInfo(
            panelId: UUID(),
            sourceRect: CGRect(origin: .zero, size: CGSize(width: 100, height: 100)),
            destinationRect: CGRect(origin: .zero, size: CGSize(width: 200, height: 200))
        )
        let imageSize = CGSize(width: 100, height: 100)
        let container = CGSize(width: 400, height: 400)

        let result = CropManager.sourceRectInContainer(crop, imageSize: imageSize, container: container)

        #expect(result.width == container.width)
        #expect(result.height == container.height)
    }

    @Test func sourceRectInContainerHandlesPartialCrop() {
        let crop = CropInfo(
            panelId: UUID(),
            sourceRect: CGRect(x: 25, y: 25, width: 50, height: 50),
            destinationRect: CGRect(origin: .zero, size: CGSize(width: 200, height: 200))
        )
        let imageSize = CGSize(width: 100, height: 100)
        let container = CGSize(width: 400, height: 400)

        let result = CropManager.sourceRectInContainer(crop, imageSize: imageSize, container: container)

        #expect(result.origin.x > 0)
        #expect(result.origin.y > 0)
        #expect(result.width < container.width)
        #expect(result.height < container.height)
    }

    @Test func sourceRectInContainerHandlesPortraitImage() {
        let crop = CropInfo(
            panelId: UUID(),
            sourceRect: CGRect(x: 0, y: 50, width: 100, height: 100),
            destinationRect: CGRect(origin: .zero, size: CGSize(width: 200, height: 200))
        )
        let imageSize = CGSize(width: 100, height: 200)
        let container = CGSize(width: 400, height: 400)

        let result = CropManager.sourceRectInContainer(crop, imageSize: imageSize, container: container)

        #expect(result.origin.x > 0)
        #expect(result.origin.y > 0)
    }

    @Test func sourceRectInContainerHandlesLandscapeImage() {
        let crop = CropInfo(
            panelId: UUID(),
            sourceRect: CGRect(x: 50, y: 0, width: 100, height: 100),
            destinationRect: CGRect(origin: .zero, size: CGSize(width: 200, height: 200))
        )
        let imageSize = CGSize(width: 200, height: 100)
        let container = CGSize(width: 400, height: 400)

        let result = CropManager.sourceRectInContainer(crop, imageSize: imageSize, container: container)

        #expect(result.origin.x > 0)
        #expect(result.origin.y > 0)
    }
}
