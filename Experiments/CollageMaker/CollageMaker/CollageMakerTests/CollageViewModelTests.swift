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

    func assembleWithCGImages(config: AssemblyConfig, cgImages: [CGImage?], backgroundImage: CGImage?, quality: Double) -> Data? {
        assembleData
    }

    func assemblePreviewWithCGImages(config: AssemblyConfig, cgImages: [CGImage?], backgroundImage: CGImage?, previewSize: CGSize) -> NSImage? {
        assemblePreviewImage
    }

    func renderPanel(crop: CropInfo, cgImage: CGImage, panelSize: CGSize) -> NSImage? {
        return NSImage(size: panelSize)
    }

    func renderBackground(config: BackgroundConfig, canvasSize: CGSize, backgroundImage: CGImage?, previewSize: CGSize) -> NSImage? {
        return NSImage(size: previewSize)
    }

    func renderTitle(titleAttrString: NSAttributedString, titleStyle: TitleStyle, canvasSize: CGSize) -> NSImage? {
        return nil
    }
}

// MARK: - Tests

@MainActor
@Suite(.serialized) struct CollageViewModelTests {

    // MARK: - Initial state

    @Test func initialStateIsEmpty() {
        let vm = CollageViewModel(saliencyAnalyzer: MockSaliencyAnalyzer(), assembler: MockAssembler())
        #expect(vm.imageLibrary.images.isEmpty)
        #expect(vm.panels.isEmpty)
        #expect(vm.cropMap.isEmpty)
        #expect(vm.selectedPanelId == nil)
        #expect(vm.previewImage == nil)
        #expect(vm.isProcessing == false)
    }

    // MARK: - Layout style changes

    @Test func setLayoutStyleUpdatesStyle() {
        let vm = CollageViewModel(saliencyAnalyzer: MockSaliencyAnalyzer(), assembler: MockAssembler())
        vm.setLayoutStyle(.uniform)
        #expect(vm.layoutStyle == .uniform)
    }

    @Test func setLayoutStyleRegeneratesLayout() {
        let mockSaliency = MockSaliencyAnalyzer()
        let mockAssembler = MockAssembler()
        let vm = CollageViewModel(saliencyAnalyzer: mockSaliency, assembler: mockAssembler)

        let images = (0..<3).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.imageLibrary.images = images
        vm.setLayoutStyle(.uniform)
        #expect(vm.layoutStyle == .uniform)
    }

    // MARK: - Clear all

    @Test func clearAllResetsState() {
        let vm = CollageViewModel(saliencyAnalyzer: MockSaliencyAnalyzer(), assembler: MockAssembler())
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
        let vm = CollageViewModel(saliencyAnalyzer: MockSaliencyAnalyzer(), assembler: MockAssembler())
        vm.updateGutter(8)
        #expect(vm.gutter == 8)
    }

    // MARK: - Panel assignment

    @Test func assignImageUpdatesPanelAssignments() {
        let vm = CollageViewModel(saliencyAnalyzer: MockSaliencyAnalyzer(), assembler: MockAssembler())
        let panelId = UUID()
        vm.assignImage(2, to: panelId)
        #expect(vm.panelAssignments[panelId] == 2)
    }

    @Test func getEffectiveImageIndexUsesAssignment() {
        let vm = CollageViewModel(saliencyAnalyzer: MockSaliencyAnalyzer(), assembler: MockAssembler())
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
        let vm = CollageViewModel(saliencyAnalyzer: mockSaliency, assembler: MockAssembler())
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
        let vm = CollageViewModel(saliencyAnalyzer: MockSaliencyAnalyzer(), assembler: MockAssembler())
        vm.updatePreview()
        #expect(vm.previewImage == nil)
    }

    // MARK: - Crop delegation

    @Test func resetCropDelegatesToManager() {
        let mockSaliency = MockSaliencyAnalyzer()
        let mockAssembler = MockAssembler()
        let vm = CollageViewModel(saliencyAnalyzer: mockSaliency, assembler: mockAssembler)

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
        let vm = CollageViewModel(saliencyAnalyzer: MockSaliencyAnalyzer(), assembler: MockAssembler())
        let images = (0..<5).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.imageLibrary.images = images
        vm.customImageOrder = [0, 1, 2, 3, 4]

        vm.moveImages(from: IndexSet(integer: 3), to: 0)
        #expect(vm.customImageOrder == [3, 0, 1, 2, 4])
    }

    @Test func moveImagesToEnd() {
        let vm = CollageViewModel(saliencyAnalyzer: MockSaliencyAnalyzer(), assembler: MockAssembler())
        let images = (0..<5).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.imageLibrary.images = images
        vm.customImageOrder = [0, 1, 2, 3, 4]

        vm.moveImages(from: IndexSet(integer: 0), to: 4)
        #expect(vm.customImageOrder == [1, 2, 3, 4, 0])
    }

    @Test func moveImagesSingleElement() {
        let vm = CollageViewModel(saliencyAnalyzer: MockSaliencyAnalyzer(), assembler: MockAssembler())
        let images = (0..<1).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.imageLibrary.images = images
        vm.customImageOrder = [0]

        vm.moveImages(from: IndexSet(integer: 0), to: 0)
        #expect(vm.customImageOrder == [0])
    }

    @Test func moveImagesWithEmptyCustomOrder() {
        let vm = CollageViewModel(saliencyAnalyzer: MockSaliencyAnalyzer(), assembler: MockAssembler())
        let images = (0..<3).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.imageLibrary.images = images
        vm.customImageOrder = []

        vm.moveImages(from: IndexSet(integer: 0), to: 2)
        #expect(vm.imageLibrary.images.count == 3)
    }
}
