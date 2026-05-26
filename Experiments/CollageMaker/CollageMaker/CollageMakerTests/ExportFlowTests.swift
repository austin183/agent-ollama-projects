import AppKit
import CoreGraphics
import Testing
@testable import CollageMaker

// MARK: - Tracking Assembler

final class TrackingAssembler: CollageAssembly {
    var assembleCalls = 0
    var previewCalls = 0
    var lastAssemblePanels: [ImagePanel] = []
    var lastAssembleCgImages: [CGImage?] = []
    var lastAssembleCrops: [UUID: CropInfo] = [:]
    var lastAssembleAssignments: [UUID: Int] = [:]
    var lastAssembleTitle: String = ""
    var lastAssembleTitleStyle: TitleStyle = .default
    var lastAssembleCanvasSize: CGSize = .zero
    var lastAssembleQuality: Double = 0
    var lastPreviewCanvasSize: CGSize = .zero
    var lastPreviewPreviewSize: CGSize = .zero
    var lastPreviewPanels: [ImagePanel] = []
    var lastPreviewTitle: String = ""

    func assembleWithCGImages(config: AssemblyConfig, cgImages: [CGImage?], backgroundImage: CGImage?, quality: Double) -> Data? {
        assembleCalls += 1
        lastAssemblePanels = config.layout.panels
        lastAssembleCgImages = cgImages
        lastAssembleCrops = config.layout.crops
        lastAssembleAssignments = config.layout.panelAssignments
        lastAssembleTitle = config.title.attrString.string
        lastAssembleTitleStyle = config.title.style
        lastAssembleCanvasSize = config.canvasSize
        lastAssembleQuality = quality
        return Data([0xFF, 0xD8, 0xFF, 0xE0])
    }

    func assemblePreviewWithCGImages(config: AssemblyConfig, cgImages: [CGImage?], backgroundImage: CGImage?, previewSize: CGSize) -> NSImage? {
        previewCalls += 1
        lastPreviewCanvasSize = config.canvasSize
        lastPreviewPreviewSize = previewSize
        lastPreviewPanels = config.layout.panels
        lastPreviewTitle = config.title.attrString.string
        return NSImage(size: previewSize)
    }
}

// MARK: - Tests

@MainActor
@Suite(.serialized) struct ExportFlowTests {

    // MARK: - Preview Flow

    @Test func updatePreviewCallsAssembler() async {
        let trackingAssembler = TrackingAssembler()
        let vm = CollageViewModel(saliencyAnalyzer: MockSaliencyAnalyzer(), assembler: trackingAssembler)

        let images = (0..<2).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.images = images
        vm.regenerateLayout()

        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(trackingAssembler.previewCalls >= 1)
    }

    @Test func updatePreviewUsesCorrectCanvasSize() async {
        let trackingAssembler = TrackingAssembler()
        let vm = CollageViewModel(saliencyAnalyzer: MockSaliencyAnalyzer(), assembler: trackingAssembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.images = images
        vm.regenerateLayout()

        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(trackingAssembler.lastPreviewCanvasSize == CanvasConfig.defaultCanvasSize)
    }

    @Test func updatePreviewUsesCorrectPreviewSize() async {
        let trackingAssembler = TrackingAssembler()
        let vm = CollageViewModel(saliencyAnalyzer: MockSaliencyAnalyzer(), assembler: trackingAssembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.images = images
        vm.regenerateLayout()

        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(trackingAssembler.lastPreviewPreviewSize == CanvasConfig.defaultPreviewSize)
    }

    @Test func updatePreviewPassesCorrectPanelCount() async {
        let trackingAssembler = TrackingAssembler()
        let vm = CollageViewModel(saliencyAnalyzer: MockSaliencyAnalyzer(), assembler: trackingAssembler)

        let images = (0..<4).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.images = images
        vm.regenerateLayout()

        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(trackingAssembler.lastPreviewPanels.count == 4)
    }

    @Test func updatePreviewPassesTitle() async {
        let trackingAssembler = TrackingAssembler()
        let vm = CollageViewModel(saliencyAnalyzer: MockSaliencyAnalyzer(), assembler: trackingAssembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.images = images
        vm.regenerateLayout()
        vm.titleAttrString = NSAttributedString(string: "My Collage")

        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(trackingAssembler.lastPreviewTitle == "My Collage")
    }

    // MARK: - Panel Assignment Flow

    @Test func swapPanelImagesUpdatesAssignments() {
        let vm = CollageViewModel(saliencyAnalyzer: MockSaliencyAnalyzer(), assembler: TrackingAssembler())

        let images = (0..<3).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.images = images
        vm.regenerateLayout()

        let panels = vm.panels
        let sourceId = panels[0].id
        let targetId = panels[1].id

        let sourceBefore = vm.getEffectiveImageIndex(for: sourceId)
        let targetBefore = vm.getEffectiveImageIndex(for: targetId)

        vm.swapPanelImages(sourceId: sourceId, targetId: targetId)

        let sourceAfter = vm.getEffectiveImageIndex(for: sourceId)
        let targetAfter = vm.getEffectiveImageIndex(for: targetId)

        #expect(sourceAfter == targetBefore)
        #expect(targetAfter == sourceBefore)
    }

    @Test func swapPanelImagesUpdatesCropMap() {
        let vm = CollageViewModel(saliencyAnalyzer: MockSaliencyAnalyzer(), assembler: TrackingAssembler())

        let images = (0..<2).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.images = images
        vm.regenerateLayout()

        let panels = vm.panels
        let cropA = vm.cropMap[panels[0].id]?.sourceRect
        let cropB = vm.cropMap[panels[1].id]?.sourceRect

        vm.swapPanelImages(sourceId: panels[0].id, targetId: panels[1].id)

        #expect(vm.cropMap[panels[0].id]?.sourceRect == cropB)
        #expect(vm.cropMap[panels[1].id]?.sourceRect == cropA)
    }

    // MARK: - Crop Flow

    @Test func resetCropUpdatesCropMap() {
        let vm = CollageViewModel(saliencyAnalyzer: MockSaliencyAnalyzer(), assembler: TrackingAssembler())

        let image = createTestImageItem(size: CGSize(width: 4000, height: 4000))
        vm.images = [image]
        vm.regenerateLayout()

        let panelId = vm.panels[0].id
        let initialCrop = vm.cropMap[panelId]?.sourceRect

        vm.beginPan(panelId: panelId)
        vm.pan(by: CGSize(width: 500, height: 500))
        vm.applyPan(panelId: panelId)

        let afterPan = vm.cropMap[panelId]?.sourceRect
        #expect(afterPan != initialCrop)

        vm.resetCrop(panelId: panelId)
        let afterReset = vm.cropMap[panelId]?.sourceRect
        #expect(afterReset == initialCrop)
    }

    @Test func clearAllResetsExportState() {
        let vm = CollageViewModel(saliencyAnalyzer: MockSaliencyAnalyzer(), assembler: TrackingAssembler())

        let images = (0..<2).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.images = images
        vm.regenerateLayout()

        vm.clearAll()

        #expect(vm.images.isEmpty)
        #expect(vm.panels.isEmpty)
        #expect(vm.cropMap.isEmpty)
        #expect(vm.panelAssignments.isEmpty)
        #expect(vm.previewImage == nil)
    }

    // MARK: - Layout Regeneration

    @Test func regenerateLayoutUpdatesCrops() {
        let vm = CollageViewModel(saliencyAnalyzer: MockSaliencyAnalyzer(), assembler: TrackingAssembler())

        let image = createTestImageItem(size: CGSize(width: 200, height: 200))
        vm.images = [image]
        vm.setLayoutStyle(.uniform)

        let uniformCrop = vm.cropMap[vm.panels[0].id]?.sourceRect

        vm.setLayoutStyle(.hero)
        let heroCrop = vm.cropMap[vm.panels[0].id]?.sourceRect

        #expect(uniformCrop != nil)
        #expect(heroCrop != nil)
    }

    @Test func regenerateLayoutUpdatesPanelAssignments() {
        let vm = CollageViewModel(saliencyAnalyzer: MockSaliencyAnalyzer(), assembler: TrackingAssembler())

        let images = (0..<3).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.images = images
        vm.regenerateLayout()

        #expect(vm.panelAssignments.count == vm.panels.count)

        for panel in vm.panels {
            #expect(vm.panelAssignments[panel.id] != nil)
        }
    }

    @Test func gutterChangeRegeneratesLayout() {
        let vm = CollageViewModel(saliencyAnalyzer: MockSaliencyAnalyzer(), assembler: TrackingAssembler())

        let images = (0..<4).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.images = images
        vm.gutter = 0

        let panelsNoGutter = vm.panels.map { $0.frame }

        vm.gutter = 20

        let panelsWithGutter = vm.panels.map { $0.frame }

        #expect(panelsNoGutter != panelsWithGutter)
    }
}
