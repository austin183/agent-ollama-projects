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

    // MARK: - Off-canvas .path Panel Pinch Zoom

    @Test func pinchZoomOffCanvasPathPanelUsesEffectiveOriginClamping() {
        let manager = CropManager()
        let image = createTestImageItem(size: CGSize(width: 4000, height: 4000))

        // Create a .path panel that extends off-canvas to the left
        let canvasSize = SizeConstants.defaultCanvasSize
        let offCanvasRect = CGRect(x: -200, y: 0, width: 600, height: canvasSize.height)
        let mutablePath = CGMutablePath()
        mutablePath.addRect(offCanvasRect)
        let panel = ImagePanel(imageIndex: 0, geometry: .path(cgPath: mutablePath, boundingRect: offCanvasRect))
        let panels = [panel]

        manager.computeInitialCrops(panels: panels, images: [image])
        let panelId = panel.id

        // Pinch zoom in
        manager.beginPinch(panelId: panelId)
        manager.pinch(magnification: 2.0)
        manager.applyPinch(panelId: panelId, panels: panels, images: [image])

        let crop = manager.cropMap[panelId]!
        // Source rect origin should remain non-negative (clamped to image bounds)
        #expect(crop.sourceRect.origin.x >= 0)
        #expect(crop.sourceRect.origin.y >= 0)
        // Source rect should not extend beyond image bounds
        #expect(crop.sourceRect.origin.x + crop.sourceRect.width <= image.size.width + 1)
        #expect(crop.sourceRect.origin.y + crop.sourceRect.height <= image.size.height + 1)
    }

    // MARK: - adjustCropDuringDrag (Pure Function)

    @Test func adjustCropDuringDragBasicDrag() {
        let image = CGSize(width: 1000, height: 1000)
        let crop = CGRect(x: 100, y: 100, width: 200, height: 200)
        let container = CGSize(width: 500, height: 500)
        let translation = CGSize(width: 50, height: 50)

        let result = CropManager.adjustCropDuringDrag(
            translation: translation,
            image: image,
            crop: crop,
            container: container,
            visOffset: .zero,
            visSize: crop.size
        )

        #expect(result.origin.x == 200)
        #expect(result.origin.y == 200)
        #expect(result.size == crop.size)
    }

    @Test func adjustCropDuringDragClampsToImageBounds() {
        let image = CGSize(width: 1000, height: 1000)
        let crop = CGRect(x: 800, y: 800, width: 200, height: 200)
        let container = CGSize(width: 500, height: 500)
        let translation = CGSize(width: 500, height: 500)

        let result = CropManager.adjustCropDuringDrag(
            translation: translation,
            image: image,
            crop: crop,
            container: container,
            visOffset: .zero,
            visSize: crop.size
        )

        #expect(result.origin.x == 800)
        #expect(result.origin.y == 800)
    }

    @Test func adjustCropDuringDragClampsToZeroBounds() {
        let image = CGSize(width: 1000, height: 1000)
        let crop = CGRect(x: 50, y: 50, width: 200, height: 200)
        let container = CGSize(width: 500, height: 500)
        let translation = CGSize(width: -100, height: -100)

        let result = CropManager.adjustCropDuringDrag(
            translation: translation,
            image: image,
            crop: crop,
            container: container,
            visOffset: .zero,
            visSize: crop.size
        )

        #expect(result.origin.x == 0)
        #expect(result.origin.y == 0)
    }

    @Test func adjustCropDuringDragCoordinateTransformLandscape() {
        let image = CGSize(width: 2000, height: 1000)
        let crop = CGRect(x: 100, y: 100, width: 200, height: 100)
        let container = CGSize(width: 500, height: 500)
        let translation = CGSize(width: 10, height: 10)

        let result = CropManager.adjustCropDuringDrag(
            translation: translation,
            image: image,
            crop: crop,
            container: container,
            visOffset: .zero,
            visSize: crop.size
        )

        // Fit: 500x250, offset: (0, 125). ScaleX=4, ScaleY=4.
        // transX = 10*4 = 40, transY = 10*4 = 40
        #expect(result.origin.x == 140)
        #expect(result.origin.y == 140)
    }

    @Test func adjustCropDuringDragPathPanelVisOffset() {
        let image = CGSize(width: 1000, height: 1000)
        let crop = CGRect(x: 100, y: 100, width: 200, height: 200)
        let container = CGSize(width: 500, height: 500)
        let translation = CGSize(width: 50, height: 50)
        let visOffset = CGPoint(x: 50, y: 50)
        let visSize = CGSize(width: 200, height: 200)

        let result = CropManager.adjustCropDuringDrag(
            translation: translation,
            image: image,
            crop: crop,
            container: container,
            visOffset: visOffset,
            visSize: visSize
        )

        // Scale 1:1. trans = (100, 100).
        // effectiveBase = (150, 150). maxEff = (800, 800).
        // newEff = (250, 250). newOX = 250-50 = 200.
        #expect(result.origin.x == 200)
        #expect(result.origin.y == 200)
    }

    @Test func adjustCropDuringDragIdentityForZeroTranslation() {
        let image = CGSize(width: 1000, height: 1000)
        let crop = CGRect(x: 100, y: 200, width: 300, height: 250)
        let container = CGSize(width: 500, height: 500)

        let result = CropManager.adjustCropDuringDrag(
            translation: .zero,
            image: image,
            crop: crop,
            container: container,
            visOffset: .zero,
            visSize: crop.size
        )

        #expect(result == crop)
    }

    @Test func adjustCropDuringDragPreservesCropSize() {
        let image = CGSize(width: 4000, height: 3000)
        let crop = CGRect(x: 500, y: 300, width: 800, height: 600)
        let container = CGSize(width: 1000, height: 800)
        let translation = CGSize(width: 100, height: -50)

        let result = CropManager.adjustCropDuringDrag(
            translation: translation,
            image: image,
            crop: crop,
            container: container,
            visOffset: .zero,
            visSize: crop.size
        )

        #expect(result.size == crop.size)
    }

    @Test func adjustCropDuringDragClampWithVisOffset() {
        let image = CGSize(width: 1000, height: 1000)
        let crop = CGRect(x: 700, y: 700, width: 200, height: 200)
        let container = CGSize(width: 500, height: 500)
        let translation = CGSize(width: 500, height: 500)
        let visOffset = CGPoint(x: 100, y: 100)
        let visSize = CGSize(width: 200, height: 200)

        let result = CropManager.adjustCropDuringDrag(
            translation: translation,
            image: image,
            crop: crop,
            container: container,
            visOffset: visOffset,
            visSize: visSize
        )

        // Scale 1:1. trans = (1000, 1000).
        // effectiveBase = (800, 800). maxEff = (800, 800).
        // newEff clamped to (800, 800). newOX = 800-100 = 700.
        #expect(result.origin.x == 700)
        #expect(result.origin.y == 700)
    }

    // MARK: - handleResize (Pure Function)

    @Test func handleResizeCornerProportionalScaling() {
        let cropBounds = CGRect(x: 100, y: 100, width: 200, height: 200)
        let delta = CGSize(width: 50, height: 50)
        let image = CGSize(width: 1000, height: 1000)
        let crop = CGRect(x: 100, y: 100, width: 200, height: 200)
        let container = CGSize(width: 500, height: 500)
        let panelSize = CGSize(width: 400, height: 400)

        let result = CropManager.handleResize(
            cropBounds: cropBounds,
            edge: .bottomRight,
            delta: delta,
            image: image,
            crop: crop,
            container: container,
            panelSize: panelSize,
            destRect: .zero
        )

        // Anchor = (100, 100). rawW=50, rawH=50. Panel aspect = 1:1.
        // newW=50, newH=50. clampedOX=50, clampedOY=50.
        // Scale 2:1 (image:container). sourceSize = (100, 100).
        // minSource = (200, 200) → clamped up to (200, 200).
        #expect(result.width == 200)
        #expect(result.height == 200)
    }

    @Test func handleResizeEdgeDominantDimension() {
        let cropBounds = CGRect(x: 100, y: 100, width: 200, height: 200)
        let delta = CGSize(width: 80, height: 20)
        let image = CGSize(width: 1000, height: 500)
        let crop = CGRect(x: 100, y: 100, width: 200, height: 100)
        let container = CGSize(width: 500, height: 250)
        let panelSize = CGSize(width: 800, height: 400)

        let result = CropManager.handleResize(
            cropBounds: cropBounds,
            edge: .bottomRight,
            delta: delta,
            image: image,
            crop: crop,
            container: container,
            panelSize: panelSize,
            destRect: .zero
        )

        // Panel aspect = 2:1. rawW=80, rawH=20. rawW/rawH = 4 > 2.
        // Width-dominant: newW=80, newH=40.
        // Scale 2:1. sourceSize = (160, 80).
        // minSourceW = 400, minSourceH = 200.
        // Clamped: sourceSize = (400, 200).
        #expect(result.width == 400)
        #expect(result.height == 200)
    }

    @Test func handleResizeMinimumCropSizeEnforcement() {
        let cropBounds = CGRect(x: 100, y: 100, width: 200, height: 200)
        let delta = CGSize(width: 1, height: 1)
        let image = CGSize(width: 1000, height: 1000)
        let crop = CGRect(x: 100, y: 100, width: 200, height: 200)
        let container = CGSize(width: 500, height: 500)
        let panelSize = CGSize(width: 400, height: 400)

        let result = CropManager.handleResize(
            cropBounds: cropBounds,
            edge: .bottomRight,
            delta: delta,
            image: image,
            crop: crop,
            container: container,
            panelSize: panelSize,
            destRect: .zero
        )

        // minSource = (200, 200). Tiny delta gets clamped up to minimum.
        #expect(result.width == 200)
        #expect(result.height == 200)
    }

    @Test func handleResizeClampsToContainerBounds() {
        let cropBounds = CGRect(x: 100, y: 100, width: 200, height: 200)
        let delta = CGSize(width: 500, height: 500)
        let image = CGSize(width: 1000, height: 1000)
        let crop = CGRect(x: 100, y: 100, width: 200, height: 200)
        let container = CGSize(width: 500, height: 500)
        let panelSize = CGSize(width: 400, height: 400)

        let result = CropManager.handleResize(
            cropBounds: cropBounds,
            edge: .bottomRight,
            delta: delta,
            image: image,
            crop: crop,
            container: container,
            panelSize: panelSize,
            destRect: .zero
        )

        // newW = 500, newH = 500. clampedOX = 0, clampedOY = 0.
        // sourceSize = (1000, 1000). minSource = (200, 200), maxSource = (1000, 1000).
        #expect(result.width == 1000)
        #expect(result.height == 1000)
        #expect(result.origin.x >= 0)
        #expect(result.origin.y >= 0)
    }

    @Test func handleResizeTopLeftCorner() {
        let cropBounds = CGRect(x: 100, y: 100, width: 200, height: 200)
        let delta = CGSize(width: -50, height: -50)
        let image = CGSize(width: 1000, height: 1000)
        let crop = CGRect(x: 100, y: 100, width: 200, height: 200)
        let container = CGSize(width: 500, height: 500)
        let panelSize = CGSize(width: 400, height: 400)

        let result = CropManager.handleResize(
            cropBounds: cropBounds,
            edge: .topLeft,
            delta: delta,
            image: image,
            crop: crop,
            container: container,
            panelSize: panelSize,
            destRect: .zero
        )

        #expect(result.width == 200)
        #expect(result.height == 200)
        #expect(result.origin.x == 500)
        #expect(result.origin.y == 500)
    }

    @Test func handleResizePreservesAspectRatio() {
        let cropBounds = CGRect(x: 100, y: 100, width: 200, height: 200)
        let delta = CGSize(width: 100, height: 30)
        let image = CGSize(width: 1920, height: 1080)
        let crop = CGRect(x: 100, y: 100, width: 200, height: 100)
        let container = CGSize(width: 960, height: 540)
        let panelSize = CGSize(width: 960, height: 540)

        let result = CropManager.handleResize(
            cropBounds: cropBounds,
            edge: .bottomRight,
            delta: delta,
            image: image,
            crop: crop,
            container: container,
            panelSize: panelSize,
            destRect: .zero
        )

        let panelAspect = panelSize.width / panelSize.height
        let resultAspect = result.width / result.height
        #expect(abs(resultAspect - panelAspect) < 0.01, "Aspect ratio should be preserved (expected \(panelAspect), got \(resultAspect))")
    }

    @Test func handleResizeSourceClampedToImageBounds() {
        let cropBounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let delta = CGSize(width: 100, height: 100)
        let image = CGSize(width: 500, height: 500)
        let crop = CGRect(x: 0, y: 0, width: 100, height: 100)
        let container = CGSize(width: 500, height: 500)
        let panelSize = CGSize(width: 400, height: 400)

        let result = CropManager.handleResize(
            cropBounds: cropBounds,
            edge: .bottomRight,
            delta: delta,
            image: image,
            crop: crop,
            container: container,
            panelSize: panelSize,
            destRect: .zero
        )

        #expect(result.origin.x >= 0)
        #expect(result.origin.y >= 0)
        #expect(result.origin.x + result.width <= image.width)
        #expect(result.origin.y + result.height <= image.height)
    }
}
