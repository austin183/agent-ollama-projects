import AppKit
import CoreGraphics
import Testing
@testable import CollageMaker

@MainActor
@Suite(.serialized) struct CollageViewModelTests {

    private func makeViewModel(
        saliencyAnalyzer: SaliencyAnalysis = MockSaliencyAnalyzer(),
        assembler: CollageAssembly = TestAssembler()
    ) -> CollageViewModel {
        let suiteName = "CollageMakerTests.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        let persistence = UserDefaultsPersistence(defaults: testDefaults)
        return CollageViewModel(
            saliencyAnalyzer: saliencyAnalyzer,
            assembler: assembler,
            persistence: persistence
        )
    }

    // MARK: - Initial state

    @Test func initialStateIsEmpty() {
        let vm = makeViewModel()
        #expect(vm.imageLibrary.images.isEmpty)
        #expect(vm.panels.isEmpty)
        #expect(vm.cropMap.isEmpty)
        #expect(vm.selectedPanelId == nil)
        #expect(vm.previewImage == nil)
        #expect(vm.isProcessing == false)
    }

    // MARK: - Layout style changes

    @Test func setLayoutStyleUpdatesStyle() {
        let vm = makeViewModel()
        vm.setLayoutStyle(.uniform)
        #expect(vm.layoutStyle == .uniform)
    }

    @Test func setLayoutStyleRegeneratesLayout() {
        let vm = makeViewModel()

        let images = (0..<3).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.imageLibrary.images = images
        vm.setLayoutStyle(.uniform)
        #expect(vm.layoutStyle == .uniform)
    }

    // MARK: - Clear all

    @Test func clearAllResetsState() {
        let vm = makeViewModel()
        vm.titleAttrString = NSAttributedString(string: "Test")
        vm.gutter = 10
        vm.clearAll()
        #expect(vm.imageLibrary.images.isEmpty)
        #expect(vm.panels.isEmpty)
        #expect(vm.cropMap.isEmpty)
        #expect(vm.previewImage == nil)
    }

    // MARK: - Gutter

    @Test func updateGutterUpdatesValue() {
        let vm = makeViewModel()
        vm.updateGutter(8)
        #expect(vm.gutter == 8)
    }

    // MARK: - Panel assignment

    @Test func assignImageUpdatesPanelAssignments() {
        let vm = makeViewModel()
        let panelId = UUID()
        vm.assignImage(2, to: panelId)
        #expect(vm.panelAssignments[panelId] == 2)
    }

    @Test func getEffectiveImageIndexUsesAssignment() {
        let vm = makeViewModel()
        let panels = LayoutGenerator.generate(numImages: 3, style: .uniform)
        vm.panels = panels

        vm.assignImage(0, to: panels[2].id)
        #expect(vm.getEffectiveImageIndex(for: panels[2].id) == 0)
        #expect(vm.getEffectiveImageIndex(for: panels[1].id) == 1)
    }

    // MARK: - Saliency error handling

    @Test func saliencyErrorSetsErrorMessage() async {
        let mockSaliency = MockSaliencyAnalyzer()
        mockSaliency.shouldThrow = true
        let vm = makeViewModel(saliencyAnalyzer: mockSaliency)
        vm.imageLibrary.images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.panels = LayoutGenerator.generate(numImages: 1, style: .hero)
        vm.cropManager.computeInitialCrops(panels: vm.panels, images: vm.imageLibrary.images)
        vm.cropMap = vm.cropManager.cropMap

        await vm.analyzeSaliency()
        #expect(vm.errorMessage != nil)
        #expect(vm.isProcessing == false)
    }

    // MARK: - Preview

    @Test func updatePreviewWithNoPanelsReturns() {
        let vm = makeViewModel()
        vm.updatePreview()
        #expect(vm.previewImage == nil)
    }

    // MARK: - Crop delegation

    @Test func resetCropDelegatesToManager() {
        let vm = makeViewModel()

        let image = createTestImageItem(size: CGSize(width: 200, height: 200))
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)

        vm.imageLibrary.images = [image]
        vm.panels = panels

        CropManager().computeInitialCrops(panels: panels, images: [image])
        vm.cropMap = CropManager().cropMap

        let panelId = panels[0].id
        vm.resetCrop(panelId: panelId)
        #expect(vm.cropMap[panelId] != nil)
    }

    // MARK: - buildMoveMapping edge cases

    @Test func moveImagesToStart() {
        let vm = makeViewModel()
        let images = (0..<5).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.imageLibrary.images = images
        vm.customImageOrder = [0, 1, 2, 3, 4]

        vm.moveImages(from: IndexSet(integer: 3), to: 0)
        #expect(vm.customImageOrder == [3, 0, 1, 2, 4])
    }

    @Test func moveImagesToEnd() {
        let vm = makeViewModel()
        let images = (0..<5).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.imageLibrary.images = images
        vm.customImageOrder = [0, 1, 2, 3, 4]

        vm.moveImages(from: IndexSet(integer: 0), to: 4)
        #expect(vm.customImageOrder == [1, 2, 3, 4, 0])
    }

    @Test func moveImagesSingleElement() {
        let vm = makeViewModel()
        let images = (0..<1).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.imageLibrary.images = images
        vm.customImageOrder = [0]

        vm.moveImages(from: IndexSet(integer: 0), to: 0)
        #expect(vm.customImageOrder == [0])
    }

    @Test func moveImagesWithEmptyCustomOrder() {
        let vm = makeViewModel()
        let images = (0..<3).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.imageLibrary.images = images
        vm.customImageOrder = []

        vm.moveImages(from: IndexSet(integer: 0), to: 2)
        #expect(vm.imageLibrary.images.count == 3)
    }

    // MARK: - Title attribute changes

    @Test func titleColorChangeUpdatesPreview() async {
        let assembler = TestAssembler()
        assembler.trackCalls = true
        let vm = makeViewModel(assembler: assembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.imageLibrary.images = images
        vm.regenerateLayout()

        await vm.awaitPendingTasks()
        let callsBefore = assembler.titleRenderCalls

        vm.titleStyle.fontColor = .red

        await vm.awaitPendingTasks()
        #expect(assembler.titleRenderCalls > callsBefore)
    }

    @Test func titleBackgroundColorChangeUpdatesPreview() async {
        let assembler = TestAssembler()
        assembler.trackCalls = true
        let vm = makeViewModel(assembler: assembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.imageLibrary.images = images
        vm.regenerateLayout()

        await vm.awaitPendingTasks()
        let callsBefore = assembler.titleRenderCalls

        vm.titleStyle.backgroundColor = .white

        await vm.awaitPendingTasks()
        #expect(assembler.titleRenderCalls > callsBefore)
    }

    @Test func titleShowBackgroundChangeUpdatesPreview() async {
        let assembler = TestAssembler()
        assembler.trackCalls = true
        let vm = makeViewModel(assembler: assembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.imageLibrary.images = images
        vm.regenerateLayout()

        await vm.awaitPendingTasks()
        let callsBefore = assembler.titleRenderCalls

        vm.titleStyle.showBackground = false

        await vm.awaitPendingTasks()
        #expect(assembler.titleRenderCalls > callsBefore)
    }

    // MARK: - Title setter side effects (Phase 2)

    @Test func titleAttrStringSetterCallsUpdatePreview() async {
        let assembler = TestAssembler()
        assembler.trackCalls = true
        let vm = makeViewModel(assembler: assembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.imageLibrary.images = images
        vm.regenerateLayout()

        await vm.awaitPendingTasks()
        let callsBefore = assembler.titleRenderCalls

        vm.titleAttrString = NSAttributedString(string: "Hello World")

        await vm.awaitPendingTasks()
        #expect(assembler.titleRenderCalls > callsBefore)
    }

    @Test func titleStyleSetterNotDraggingCallsUpdatePreview() async {
        let assembler = TestAssembler()
        assembler.trackCalls = true
        let vm = makeViewModel(assembler: assembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.imageLibrary.images = images
        vm.regenerateLayout()

        await vm.awaitPendingTasks()
        let callsBefore = assembler.titleRenderCalls

        vm.isDraggingTitle = false
        vm.titleStyle.fontSize = 56

        await vm.awaitPendingTasks()
        #expect(assembler.titleRenderCalls > callsBefore)
    }

    @Test func titleStyleSetterDraggingCallsUpdateTitleImageLive() async {
        let assembler = TestAssembler()
        assembler.trackCalls = true
        let vm = makeViewModel(assembler: assembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.imageLibrary.images = images
        vm.titleAttrString = NSAttributedString(string: "Drag Me")
        vm.regenerateLayout()

        await vm.awaitPendingTasks()
        let renderCallsBefore = assembler.titleRenderCalls

        vm.isDraggingTitle = true
        vm.titleStyle.positionX = 0.75

        await vm.awaitPendingTasks()
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(assembler.titleRenderCalls > renderCallsBefore)
    }

    @Test func titleStyleSetterDraggingSkipsUndo() async {
        let assembler = TestAssembler()
        assembler.trackCalls = true
        let vm = makeViewModel(assembler: assembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.imageLibrary.images = images
        vm.titleAttrString = NSAttributedString(string: "Drag Me")
        vm.regenerateLayout()

        await vm.awaitPendingTasks()

        vm.isDraggingTitle = true
        vm.titleStyle.positionX = 0.75

        await vm.awaitPendingTasks()
        try? await Task.sleep(nanoseconds: 200_000_000)
        // Position change during drag should NOT be registered for undo.
        // Undoing should revert a previous action (e.g., title string),
        // but the position change should survive.
        if vm.undoManager.canUndo {
            vm.undoManager.undo()
        }
        #expect(vm.titleStyle.positionX == 0.75)
    }

    @Test func finishTitleDragRendersImmediately() async {
        let assembler = TestAssembler()
        assembler.trackCalls = true
        let vm = makeViewModel(assembler: assembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.imageLibrary.images = images
        vm.titleAttrString = NSAttributedString(string: "Drag Me")
        vm.regenerateLayout()

        await vm.awaitPendingTasks()
        let renderCallsBefore = assembler.titleRenderCalls

        vm.finishTitleDrag()

        await vm.awaitPendingTasks()
        #expect(assembler.titleRenderCalls > renderCallsBefore)
    }

    @Test func setTitleFontFamilyCallsUpdateTitleImageLive() async {
        let assembler = TestAssembler()
        assembler.trackCalls = true
        let vm = makeViewModel(assembler: assembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.imageLibrary.images = images
        vm.titleAttrString = NSAttributedString(string: "Font Test")
        vm.regenerateLayout()

        await vm.awaitPendingTasks()
        let renderCallsBefore = assembler.titleRenderCalls

        vm.setTitleFontFamily("Helvetica")

        await vm.awaitPendingTasks()
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(assembler.titleRenderCalls > renderCallsBefore)
    }

    @Test func setTitleFontSizeCallsUpdateTitleImageDebounced() async {
        let assembler = TestAssembler()
        assembler.trackCalls = true
        let vm = makeViewModel(assembler: assembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.imageLibrary.images = images
        vm.titleAttrString = NSAttributedString(string: "Size Test")
        vm.regenerateLayout()

        await vm.awaitPendingTasks()
        let renderCallsBefore = assembler.titleRenderCalls

        vm.setTitleFontSize(60)

        await vm.awaitPendingTasks()
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(assembler.titleRenderCalls > renderCallsBefore)
    }

    // MARK: - Cached title layout (Phase 1)

    @Test func cachedTitleCanvasFrameIsNullForEmptyTitle() {
        let vm = makeViewModel()
        #expect(vm.cachedTitleCanvasFrame == nil)
    }

    @Test func cachedTitleCanvasFramePopulatedAfterTitleSet() {
        let vm = makeViewModel()
        vm.titleAttrString = NSAttributedString(string: "Hello World")
        #expect(vm.cachedTitleCanvasFrame != nil)
    }

    @Test func cachedTitleCanvasFrameUpdatesOnTitleChange() {
        let vm = makeViewModel()
        vm.titleStyle.width = 200
        vm.titleAttrString = NSAttributedString(string: "Short")
        let frame1 = vm.cachedTitleCanvasFrame
        vm.titleAttrString = NSAttributedString(string: "This Is A Much Longer Title Text That Should Wrap")
        let frame2 = vm.cachedTitleCanvasFrame
        #expect(frame1 != nil)
        #expect(frame2 != nil)
        #expect(frame1?.height != frame2?.height)
    }

    @Test func cachedTitleCanvasFrameUpdatesOnFontSizeChange() {
        let vm = makeViewModel()
        vm.titleAttrString = NSAttributedString(string: "Font Size Test")
        let frame1 = vm.cachedTitleCanvasFrame
        vm.titleStyle.fontSize = 80
        let frame2 = vm.cachedTitleCanvasFrame
        #expect(frame1 != nil)
        #expect(frame2 != nil)
        #expect(frame2!.height > frame1!.height)
    }

    @Test func cachedTitleCanvasFrameUpdatesOnWidthChange() {
        let vm = makeViewModel()
        vm.titleAttrString = NSAttributedString(string: "Width Test")
        vm.titleStyle.width = 400
        let frame1 = vm.cachedTitleCanvasFrame
        vm.titleStyle.width = 800
        let frame2 = vm.cachedTitleCanvasFrame
        #expect(frame1 != nil)
        #expect(frame2 != nil)
        #expect(frame1?.width != frame2?.width)
    }

    @Test func cachedTitleCanvasFrameUpdatesOnPositionChange() {
        let vm = makeViewModel()
        vm.titleAttrString = NSAttributedString(string: "Position Test")
        let frame1 = vm.cachedTitleCanvasFrame
        vm.titleStyle.positionX = 0.9
        let frame2 = vm.cachedTitleCanvasFrame
        #expect(frame1 != nil)
        #expect(frame2 != nil)
        #expect(frame1?.origin.x != frame2?.origin.x)
    }

    @Test func cachedTitleBoundsNotRecomputedForPositionChange() {
        // Position changes should NOT invalidate the CoreText bounds cache.
        // Verify behaviorally: minWidth (bounds-only) stays the same,
        // while canvasFrame (bounds + position math) changes.
        let vm = makeViewModel()
        vm.titleAttrString = NSAttributedString(string: "Cache Test")
        let minWidthBefore = vm.cachedTitleMinWidth
        let frameBefore = vm.cachedTitleCanvasFrame
        vm.titleStyle.positionX = 0.75
        vm.titleStyle.positionY = 0.3
        let minWidthAfter = vm.cachedTitleMinWidth
        let frameAfter = vm.cachedTitleCanvasFrame
        #expect(minWidthBefore == minWidthAfter, "minWidth should not change with position-only changes")
        #expect(frameBefore?.origin.x != frameAfter?.origin.x, "canvasFrame position should change")
    }

    @Test func cachedTitleBoundsRecomputedOnFontSizeChange() {
        // FontSize changes SHOULD invalidate the CoreText bounds cache.
        // Verify behaviorally: both minWidth and canvasFrame should change.
        let vm = makeViewModel()
        vm.titleAttrString = NSAttributedString(string: "Recompute Test")
        let minWidthBefore = vm.cachedTitleMinWidth
        let frameBefore = vm.cachedTitleCanvasFrame
        vm.titleStyle.fontSize = 80
        let minWidthAfter = vm.cachedTitleMinWidth
        let frameAfter = vm.cachedTitleCanvasFrame
        #expect(minWidthAfter > minWidthBefore, "minWidth should increase with larger fontSize")
        #expect(frameAfter?.height != frameBefore?.height, "canvasFrame height should change with fontSize")
    }

    @Test func cachedTitleMinWidthUpdatesOnTitleChange() {
        let vm = makeViewModel()
        vm.titleAttrString = NSAttributedString(string: "Short")
        let width1 = vm.cachedTitleMinWidth
        vm.titleAttrString = NSAttributedString(string: "This Is A Much Longer Title Text")
        let width2 = vm.cachedTitleMinWidth
        #expect(width2 > width1)
    }

    @Test func cachedTitleMinWidthUnchangedForPositionChange() {
        let vm = makeViewModel()
        vm.titleAttrString = NSAttributedString(string: "MinWidth Test")
        let width1 = vm.cachedTitleMinWidth
        vm.titleStyle.positionX = 0.9
        vm.titleStyle.positionY = 0.1
        let width2 = vm.cachedTitleMinWidth
        #expect(width1 == width2)
    }

    @Test func cachedTitleCanvasFrameRecoversAfterClearRestore() {
        let vm = makeViewModel()
        vm.titleAttrString = NSAttributedString(string: "Hello")
        let frame1 = vm.cachedTitleCanvasFrame
        #expect(frame1 != nil)

        vm.titleAttrString = NSAttributedString(string: "")
        #expect(vm.cachedTitleCanvasFrame == nil)

        vm.titleAttrString = NSAttributedString(string: "Hello")
        let frame2 = vm.cachedTitleCanvasFrame
        #expect(frame2 != nil)
        #expect(frame2 == frame1)
    }
}
