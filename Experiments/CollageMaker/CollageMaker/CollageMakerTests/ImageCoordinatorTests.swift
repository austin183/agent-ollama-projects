import AppKit
import CoreGraphics
import Testing
@testable import CollageMaker

@MainActor
@Suite(.serialized) struct ImageCoordinatorTests {

    private func makeCoordinator(
        saliencyAnalyzer: SaliencyAnalysis = MockSaliencyAnalyzer(),
        assembler: CollageAssembly = TestAssembler()
    ) -> (coordinator: ImageCoordinator, target: MockCoordinationTarget, imageLibrary: ImageLibraryManager, layoutManager: LayoutManager, cropManager: CropManager) {
        let target = MockCoordinationTarget()
        let imageLibrary = ImageLibraryManager()
        let layoutManager = LayoutManager()
        let cropManager = CropManager()
        let previewManager = PreviewManager(assembler: assembler)
        let undoManager = UndoManager()
        let coordinator = ImageCoordinator(
            imageLibrary: imageLibrary,
            layoutManager: layoutManager,
            cropManager: cropManager,
            previewManager: previewManager,
            undoManager: undoManager,
            saliencyAnalyzer: saliencyAnalyzer
        )
        coordinator.target = target
        return (coordinator, target, imageLibrary, layoutManager, cropManager)
    }

    // MARK: - Remove Image

    @Test func removeImageReturnsRemovedItemAndIndex() {
        let (coord, _, lib, _, _) = makeCoordinator()
        let item = createTestImageItem(filename: "test.jpg")
        lib.images = [item]

        let result = coord.removeImage(at: 0)

        #expect(result != nil)
        #expect(result?.item.id == item.id)
        #expect(result?.at == 0)
        #expect(lib.images.isEmpty)
    }

    @Test func removeImageOutOfBoundsReturnsNil() {
        let (coord, _, _, _, _) = makeCoordinator()

        let result = coord.removeImage(at: 0)

        #expect(result == nil)
    }

    @Test func removeImageMiddleReturnsCorrectIndex() {
        let (coord, _, lib, _, _) = makeCoordinator()
        let items = (0..<3).map { i in
            createTestImageItem(filename: "\(i).jpg")
        }
        lib.images = items

        let result = coord.removeImage(at: 1)

        #expect(result?.item.id == items[1].id)
        #expect(result?.at == 1)
        #expect(lib.images.count == 2)
    }

    // MARK: - Move Images

    @Test func moveImagesReturnsOldCustomOrder() {
        let (coord, _, lib, _, _) = makeCoordinator()
        lib.images = (0..<3).map { _ in createTestImageItem() }
        lib.customImageOrder = [0, 1, 2]

        let oldOrder = coord.moveImages(from: IndexSet([0]), to: 2)

        #expect(oldOrder == [0, 1, 2])
    }

    @Test func moveImagesUpdatesCustomOrder() {
        let (coord, _, lib, _, _) = makeCoordinator()
        lib.images = (0..<3).map { _ in createTestImageItem() }
        lib.customImageOrder = [0, 1, 2]

        _ = coord.moveImages(from: IndexSet([0]), to: 2)

        #expect(lib.customImageOrder == [1, 2, 0])
    }

    @Test func moveImagesClearsPanelAssignments() {
        let (coord, _, lib, layout, _) = makeCoordinator()
        lib.images = (0..<3).map { _ in createTestImageItem() }
        lib.customImageOrder = [0, 1, 2]
        layout.panelAssignments = [UUID(): 0, UUID(): 1]

        _ = coord.moveImages(from: IndexSet([0]), to: 2)

        #expect(layout.panelAssignments.isEmpty)
    }

    // MARK: - Clear Domain

    @Test func clearDomainClearsImagesAndSaliency() {
        let (coord, _, lib, layout, crop) = makeCoordinator()
        let images = (0..<3).map { _ in createTestImageItem() }
        lib.images = images
        let panels = LayoutGenerator.generate(numImages: 3, style: .uniform)
        layout.panels = panels
        let panelId = panels[0].id
        crop.cropMap[panelId] = CropInfo(panelId: panelId, sourceRect: CGRect(x: 0, y: 0, width: 50, height: 50), destination: panels[0].geometry)
        coord.saliencyResults = [0: SaliencyResult(center: .zero, radius: 10, confidence: 0.9)]

        let state = coord.clearDomain()

        #expect(lib.images.isEmpty)
        #expect(coord.saliencyResults.isEmpty)
        #expect(state.images.count == 3)
        #expect(state.panels.count == 3)
        #expect(state.cropMap.count == 1)
    }

    @Test func clearDomainOnEmptyReturnsEmptyState() {
        let (coord, _, _, _, _) = makeCoordinator()

        let state = coord.clearDomain()

        #expect(state.images.isEmpty)
        #expect(state.panels.isEmpty)
        #expect(state.cropMap.isEmpty)
    }

    // MARK: - Assign Image

    @Test func assignImageUpdatesPanelAssignments() {
        let (coord, target, _, layout, _) = makeCoordinator()
        let panelId = UUID()

        coord.assignImage(2, to: panelId)

        #expect(layout.panelAssignments[panelId] == 2)
        #expect(target.resetCropCalls.contains(panelId))
        #expect(target.updatePanelPreviewCalls.contains(panelId))
    }

    // MARK: - Get Effective Image Index

    @Test func getEffectiveImageIndexUsesExplicitAssignment() {
        let (coord, _, _, layout, _) = makeCoordinator()
        let panels = LayoutGenerator.generate(numImages: 3, style: .uniform)
        layout.panels = panels
        coord.assignImage(0, to: panels[2].id)

        let index = coord.getEffectiveImageIndex(for: panels[2].id)

        #expect(index == 0)
    }

    @Test func getEffectiveImageIndexFallsBackToPanelIndex() {
        let (coord, _, _, layout, _) = makeCoordinator()
        let panels = LayoutGenerator.generate(numImages: 3, style: .uniform)
        layout.panels = panels

        let index = coord.getEffectiveImageIndex(for: panels[1].id)

        #expect(index == 1)
    }

    @Test func getEffectiveImageIndexReturnsNilForUnknownPanel() {
        let (coord, _, _, layout, _) = makeCoordinator()
        layout.panels = LayoutGenerator.generate(numImages: 2, style: .uniform)

        let index = coord.getEffectiveImageIndex(for: UUID())

        #expect(index == nil)
    }

    // MARK: - Select Panel For Image

    @Test func selectPanelForImageSelectsMatchingPanel() {
        let (coord, target, lib, layout, _) = makeCoordinator()
        let images = (0..<3).map { _ in createTestImageItem() }
        lib.images = images
        let panels = LayoutGenerator.generate(numImages: 3, style: .uniform)
        layout.panels = panels

        coord.selectPanelForImage(at: 1)

        #expect(target.selectedPanelId == panels[1].id)
    }

    @Test func selectPanelForImageWithExplicitAssignment() {
        let (coord, target, lib, layout, _) = makeCoordinator()
        let images = (0..<3).map { _ in createTestImageItem() }
        lib.images = images
        let panels = LayoutGenerator.generate(numImages: 3, style: .uniform)
        layout.panels = panels
        layout.panelAssignments[panels[0].id] = 2

        coord.selectPanelForImage(at: 2)

        #expect(target.selectedPanelId == panels[0].id)
    }

    @Test func selectPanelForImageOutOfBoundsDoesNothing() {
        let (coord, target, lib, layout, _) = makeCoordinator()
        lib.images = [createTestImageItem()]
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)
        layout.panels = panels
        target.selectedPanelId = panels[0].id

        coord.selectPanelForImage(at: 10)

        #expect(target.selectedPanelId == panels[0].id)
    }

    // MARK: - Swap Panel Images

    @Test func swapPanelImagesReturnsNilForSameId() {
        let (coord, _, _, _, _) = makeCoordinator()
        let panels = LayoutGenerator.generate(numImages: 2, style: .uniform)
        coord.layoutManager.panels = panels

        let state = coord.swapPanelImages(sourceId: panels[0].id, targetId: panels[0].id)

        #expect(state == nil)
    }

    @Test func swapPanelImagesReturnsStateAndSwapsAssignments() {
        let (coord, target, lib, layout, _) = makeCoordinator()
        let images = (0..<2).map { _ in createTestImageItem() }
        lib.images = images
        lib.customImageOrder = [0, 1]
        let panels = LayoutGenerator.generate(numImages: 2, style: .uniform)
        layout.panels = panels
        layout.panelAssignments[panels[0].id] = 0
        layout.panelAssignments[panels[1].id] = 1

        let state = coord.swapPanelImages(sourceId: panels[0].id, targetId: panels[1].id)

        #expect(state != nil)
        #expect(state?.sourceAssign == 0)
        #expect(state?.targetAssign == 1)
        #expect(layout.panelAssignments[panels[0].id] == 1)
        #expect(layout.panelAssignments[panels[1].id] == 0)
        #expect(lib.customImageOrder == [1, 0])
        #expect(target.updatePanelPreviewCalls.contains(panels[0].id))
        #expect(target.updatePanelPreviewCalls.contains(panels[1].id))
    }

    @Test func swapPanelImagesSwapsCropsWhenBothExist() {
        let (coord, _, lib, layout, crop) = makeCoordinator()
        let images = (0..<2).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        lib.images = images
        lib.customImageOrder = [0, 1]
        let panels = LayoutGenerator.generate(numImages: 2, style: .uniform)
        layout.panels = panels

        let cropA = CropInfo(panelId: panels[0].id, sourceRect: CGRect(x: 0, y: 0, width: 100, height: 100), destination: panels[0].geometry)
        let cropB = CropInfo(panelId: panels[1].id, sourceRect: CGRect(x: 50, y: 50, width: 100, height: 100), destination: panels[1].geometry)
        crop.cropMap[panels[0].id] = cropA
        crop.cropMap[panels[1].id] = cropB

        _ = coord.swapPanelImages(sourceId: panels[0].id, targetId: panels[1].id)

        #expect(crop.cropMap[panels[0].id]?.sourceRect == cropB.sourceRect)
        #expect(crop.cropMap[panels[1].id]?.sourceRect == cropA.sourceRect)
    }

    @Test func swapPanelImagesDoesNotSwapCropsWhenOnlyOneExists() {
        let (coord, _, lib, layout, crop) = makeCoordinator()
        let images = (0..<2).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        lib.images = images
        lib.customImageOrder = [0, 1]
        let panels = LayoutGenerator.generate(numImages: 2, style: .uniform)
        layout.panels = panels

        let cropA = CropInfo(panelId: panels[0].id, sourceRect: CGRect(x: 0, y: 0, width: 100, height: 100), destination: panels[0].geometry)
        crop.cropMap[panels[0].id] = cropA

        _ = coord.swapPanelImages(sourceId: panels[0].id, targetId: panels[1].id)

        #expect(crop.cropMap[panels[0].id]?.sourceRect == cropA.sourceRect)
        #expect(crop.cropMap[panels[1].id] == nil)
    }

    // MARK: - Analyze Saliency

    @Test func analyzeSaliencyUpdatesResultsAndCrops() async {
        let mockSaliency = MockSaliencyAnalyzer()
        let (coord, target, lib, layout, _) = makeCoordinator(saliencyAnalyzer: mockSaliency)
        let images = (0..<2).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        lib.images = images
        let panels = LayoutGenerator.generate(numImages: 2, style: .uniform)
        layout.panels = panels

        await coord.analyzeSaliency()

        #expect(coord.saliencyResults.count == 2)
        #expect(target.beginProcessingCalls == 1)
        #expect(target.endProcessingCalls == 1)
        #expect(target.updatePreviewCalls == 1)
        #expect(target.updateAllPanelPreviewsCalls == 1)
        #expect(target.cancelDebouncerCalls.contains("previewRender"))
    }

    @Test func analyzeSaliencySetsErrorMessageOnError() async {
        let mockSaliency = MockSaliencyAnalyzer()
        mockSaliency.shouldThrow = true
        let (coord, target, lib, layout, _) = makeCoordinator(saliencyAnalyzer: mockSaliency)
        lib.images = [createTestImageItem()]
        layout.panels = LayoutGenerator.generate(numImages: 1, style: .uniform)

        await coord.analyzeSaliency()

        #expect(target.errorMessage != nil)
        #expect(target.beginProcessingCalls == 1)
        #expect(target.endProcessingCalls == 1)
    }

    @Test func analyzeSaliencyReturnsEarlyWhenNoImages() async {
        let (coord, target, _, _, _) = makeCoordinator()
        target.isProcessing = false

        await coord.analyzeSaliency()

        #expect(target.beginProcessingCalls == 0)
        #expect(target.endProcessingCalls == 0)
    }

    // MARK: - Browse Images

    @Test func browseImagesDelegatesToImageLibrary() {
        let (coord, _, _, _, _) = makeCoordinator()
        #expect(throws: Never.self) {
            coord.browseImages()
        }
    }
}
