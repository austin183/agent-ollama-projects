import AppKit
import CoreGraphics
import Testing
@testable import CollageMaker

// MARK: - Mock services

final class MockSaliencyAnalyzer: SaliencyAnalysis {
    var analyzeResult: SaliencyResult?
    var shouldThrow: Bool = false

    func analyze(_ cgImage: CGImage) async throws -> SaliencyResult {
        if shouldThrow {
            throw SaliencyError.analysisFailed
        }
        return analyzeResult ?? SaliencyResult(center: CGPoint(x: 50, y: 50), radius: 20, confidence: 0.9)
    }

    func analyzeAll(_ cgImages: [CGImage]) async throws -> [SaliencyResult] {
        if shouldThrow {
            throw SaliencyError.analysisFailed
        }
        return cgImages.map { _ in
            analyzeResult ?? SaliencyResult(center: CGPoint(x: 50, y: 50), radius: 20, confidence: 0.9)
        }
    }
}

final class MockAssembler: CollageAssembly {
    var assembleData: Data? = Data()
    var assemblePreviewImage: NSImage? = NSImage(size: CanvasConfig.defaultPreviewSize)

    func assembleWithCGImages(config: AssemblyConfig, cgImages: [CGImage?], backgroundImage: CGImage?, quality: Double) async -> Data? {
        assembleData
    }

    func assemblePreviewWithCGImages(config: AssemblyConfig, cgImages: [CGImage?], backgroundImage: CGImage?, previewSize: CGSize) async -> NSImage? {
        assemblePreviewImage
    }

    func renderPanel(crop: CropInfo, cgImage: CGImage, panelSize: CGSize) async -> NSImage? {
        return NSImage(size: panelSize)
    }

    func renderBackground(config: BackgroundConfig, canvasSize: CGSize, backgroundImage: CGImage?, previewSize: CGSize) async -> NSImage? {
        return NSImage(size: previewSize)
    }

    func renderTitle(titleAttrString: NSAttributedString, titleStyle: TitleStyle, canvasSize: CGSize) async -> NSImage? {
        return nil
    }
}

// MARK: - Tests

@MainActor
@Suite(.serialized) struct CollageViewModelTests {

    private func makeViewModel(
        saliencyAnalyzer: SaliencyAnalysis = MockSaliencyAnalyzer(),
        assembler: CollageAssembly = MockAssembler()
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

    @Test func titleAttrStringAttributeChangeInvalidatesMetrics() {
        let vm = makeViewModel()
        let regularFont = NSFont.systemFont(ofSize: 48)
        let boldFont = NSFont.boldSystemFont(ofSize: 48)

        vm.titleAttrString = NSAttributedString(string: "Hello", attributes: [.font: regularFont])
        _ = vm.titleMetrics
        let firstPrepared = vm.titleMetrics?.preparedString

        vm.titleAttrString = NSAttributedString(string: "Hello", attributes: [.font: boldFont])
        let secondPrepared = vm.titleMetrics?.preparedString

        #expect(firstPrepared != secondPrepared)
    }

    @Test func titleColorChangeUpdatesPreview() async {
        let trackingAssembler = TrackingAssembler()
        let vm = makeViewModel(assembler: trackingAssembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.imageLibrary.images = images
        vm.regenerateLayout()

        await vm.awaitPendingTasks()
        let callsBefore = trackingAssembler.titleRenderCalls

        vm.titleStyle.fontColor = .red

        await vm.awaitPendingTasks()
        #expect(trackingAssembler.titleRenderCalls > callsBefore)
    }

    @Test func titleBackgroundColorChangeUpdatesPreview() async {
        let trackingAssembler = TrackingAssembler()
        let vm = makeViewModel(assembler: trackingAssembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.imageLibrary.images = images
        vm.regenerateLayout()

        await vm.awaitPendingTasks()
        let callsBefore = trackingAssembler.titleRenderCalls

        vm.titleStyle.backgroundColor = .white

        await vm.awaitPendingTasks()
        #expect(trackingAssembler.titleRenderCalls > callsBefore)
    }

    @Test func titleShowBackgroundChangeUpdatesPreview() async {
        let trackingAssembler = TrackingAssembler()
        let vm = makeViewModel(assembler: trackingAssembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.imageLibrary.images = images
        vm.regenerateLayout()

        await vm.awaitPendingTasks()
        let callsBefore = trackingAssembler.titleRenderCalls

        vm.titleStyle.showBackground = false

        await vm.awaitPendingTasks()
        #expect(trackingAssembler.titleRenderCalls > callsBefore)
    }

    // MARK: - Title setter side effects (Phase 2)

    @Test func titleAttrStringSetterCallsUpdatePreview() async {
        let trackingAssembler = TrackingAssembler()
        let vm = makeViewModel(assembler: trackingAssembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.imageLibrary.images = images
        vm.regenerateLayout()

        await vm.awaitPendingTasks()
        let callsBefore = trackingAssembler.titleRenderCalls

        vm.titleAttrString = NSAttributedString(string: "Hello World")

        await vm.awaitPendingTasks()
        #expect(trackingAssembler.titleRenderCalls > callsBefore)
    }

    @Test func titleStyleSetterNotDraggingCallsUpdatePreview() async {
        let trackingAssembler = TrackingAssembler()
        let vm = makeViewModel(assembler: trackingAssembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.imageLibrary.images = images
        vm.regenerateLayout()

        await vm.awaitPendingTasks()
        let callsBefore = trackingAssembler.titleRenderCalls

        vm.isDraggingTitle = false
        vm.titleStyle.fontSize = 56

        await vm.awaitPendingTasks()
        #expect(trackingAssembler.titleRenderCalls > callsBefore)
    }

    @Test func titleStyleSetterDraggingCallsUpdateTitleImageLive() async {
        let trackingAssembler = TrackingAssembler()
        let vm = makeViewModel(assembler: trackingAssembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.imageLibrary.images = images
        vm.titleAttrString = NSAttributedString(string: "Drag Me")
        vm.regenerateLayout()

        await vm.awaitPendingTasks()
        let renderCallsBefore = trackingAssembler.titleRenderCalls

        vm.isDraggingTitle = true
        vm.titleStyle.positionX = 0.75

        await vm.awaitPendingTasks()
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(trackingAssembler.titleRenderCalls > renderCallsBefore)
    }

    @Test func titleStyleSetterDraggingSkipsUndo() async {
        let trackingAssembler = TrackingAssembler()
        let vm = makeViewModel(assembler: trackingAssembler)

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
        let trackingAssembler = TrackingAssembler()
        let vm = makeViewModel(assembler: trackingAssembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.imageLibrary.images = images
        vm.titleAttrString = NSAttributedString(string: "Drag Me")
        vm.regenerateLayout()

        await vm.awaitPendingTasks()
        let renderCallsBefore = trackingAssembler.titleRenderCalls

        vm.finishTitleDrag()

        await vm.awaitPendingTasks()
        #expect(trackingAssembler.titleRenderCalls > renderCallsBefore)
    }

    @Test func setTitleFontFamilyCallsUpdateTitleImageLive() async {
        let trackingAssembler = TrackingAssembler()
        let vm = makeViewModel(assembler: trackingAssembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.imageLibrary.images = images
        vm.titleAttrString = NSAttributedString(string: "Font Test")
        vm.regenerateLayout()

        await vm.awaitPendingTasks()
        let renderCallsBefore = trackingAssembler.titleRenderCalls

        vm.setTitleFontFamily("Helvetica")

        await vm.awaitPendingTasks()
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(trackingAssembler.titleRenderCalls > renderCallsBefore)
    }

    @Test func setTitleFontSizeCallsUpdateTitleImageDebounced() async {
        let trackingAssembler = TrackingAssembler()
        let vm = makeViewModel(assembler: trackingAssembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.imageLibrary.images = images
        vm.titleAttrString = NSAttributedString(string: "Size Test")
        vm.regenerateLayout()

        await vm.awaitPendingTasks()
        let renderCallsBefore = trackingAssembler.titleRenderCalls

        vm.setTitleFontSize(60)

        await vm.awaitPendingTasks()
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(trackingAssembler.titleRenderCalls > renderCallsBefore)
    }
}
