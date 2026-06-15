import AppKit
import CoreGraphics
import Testing
@testable import CollageMaker

@MainActor
@Suite(.serialized) struct ExportFlowTests {

    private func makeViewModel(assembler: CollageAssembly = { let a = TestAssembler(); a.trackCalls = true; return a }()) -> CollageViewModel {
        let suiteName = "CollageMakerTests.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        let persistence = UserDefaultsPersistence(defaults: testDefaults)
        return CollageViewModel(
            saliencyAnalyzer: MockSaliencyAnalyzer(),
            assembler: assembler,
            persistence: persistence
        )
    }

    // MARK: - Preview Flow

    @Test func updatePreviewCallsAssembler() async {
        let assembler = TestAssembler()
        assembler.trackCalls = true
        let vm = makeViewModel(assembler: assembler)

        let images = (0..<2).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.imageLibrary.images = images
        vm.regenerateLayout()

        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(assembler.previewCalls >= 1)
    }

    @Test func updatePreviewUsesCorrectCanvasSize() async {
        let assembler = TestAssembler()
        assembler.trackCalls = true
        let vm = makeViewModel(assembler: assembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.imageLibrary.images = images
        vm.regenerateLayout()

        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(assembler.lastPreviewConfig?.canvasSize == SizeConstants.defaultCanvasSize)
    }

    @Test func updatePreviewUsesCorrectPreviewSize() async {
        let assembler = TestAssembler()
        assembler.trackCalls = true
        let vm = makeViewModel(assembler: assembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.imageLibrary.images = images
        vm.regenerateLayout()

        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(assembler.lastPreviewPreviewSize == SizeConstants.defaultPreviewSize)
    }

    @Test func updatePreviewPassesCorrectPanelCount() async {
        let assembler = TestAssembler()
        assembler.trackCalls = true
        let vm = makeViewModel(assembler: assembler)

        let images = (0..<4).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.imageLibrary.images = images
        vm.regenerateLayout()

        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(assembler.lastPreviewPanels.count == 4)
    }

    @Test func updatePreviewPassesTitle() async {
        let assembler = TestAssembler()
        assembler.trackCalls = true
        let vm = makeViewModel(assembler: assembler)

        let images = [createTestImageItem(size: CGSize(width: 200, height: 200))]
        vm.imageLibrary.images = images
        vm.regenerateLayout()
        vm.isLayeredMode = false
        vm.titleAttrString = NSAttributedString(string: "My Collage")

        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(assembler.lastPreviewTitle == "My Collage")
    }

    // MARK: - Panel Assignment Flow

    @Test func swapPanelImagesUpdatesAssignments() {
        let vm = makeViewModel()

        let images = (0..<3).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.imageLibrary.images = images
        vm.regenerateLayout()

        let panels = vm.layoutManager.panels
        let sourceId = panels[0].id
        let targetId = panels[1].id

        let sourceBefore = vm.imageCoordinator.getEffectiveImageIndex(for: sourceId)
        let targetBefore = vm.imageCoordinator.getEffectiveImageIndex(for: targetId)

        vm.imageCoordinator.swapPanelImages(sourceId: sourceId, targetId: targetId)

        let sourceAfter = vm.imageCoordinator.getEffectiveImageIndex(for: sourceId)
        let targetAfter = vm.imageCoordinator.getEffectiveImageIndex(for: targetId)

        #expect(sourceAfter == targetBefore)
        #expect(targetAfter == sourceBefore)
    }

    @Test func swapPanelImagesUpdatesCropMap() {
        let vm = makeViewModel()

        let images = (0..<2).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.imageLibrary.images = images
        vm.regenerateLayout()

        let panels = vm.layoutManager.panels
        let cropA = vm.cropMap[panels[0].id]?.sourceRect
        let cropB = vm.cropMap[panels[1].id]?.sourceRect

        vm.imageCoordinator.swapPanelImages(sourceId: panels[0].id, targetId: panels[1].id)

        #expect(vm.cropMap[panels[0].id]?.sourceRect == cropB)
        #expect(vm.cropMap[panels[1].id]?.sourceRect == cropA)
    }

    // MARK: - Crop Flow

    @Test func resetCropUpdatesCropMap() {
        let vm = makeViewModel()

        let image = createTestImageItem(size: CGSize(width: 4000, height: 4000))
        vm.imageLibrary.images = [image]
        vm.regenerateLayout()

        let panelId = vm.layoutManager.panels[0].id
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
        let vm = makeViewModel()

        let images = (0..<2).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.imageLibrary.images = images
        vm.regenerateLayout()

        vm.imageCoordinator.clearAll()

        #expect(vm.imageLibrary.images.isEmpty)
        #expect(vm.layoutManager.panels.isEmpty)
        #expect(vm.cropMap.isEmpty)
        #expect(vm.layoutManager.panelAssignments.isEmpty)
        #expect(vm.previewImage == nil)
    }

    // MARK: - Layout Regeneration

    @Test func regenerateLayoutUpdatesCrops() {
        let vm = makeViewModel()

        let image = createTestImageItem(size: CGSize(width: 200, height: 200))
        vm.imageLibrary.images = [image]
        vm.setLayoutStyle(.uniform)

        let uniformCrop = vm.cropMap[vm.layoutManager.panels[0].id]?.sourceRect

        vm.setLayoutStyle(.hero)
        let heroCrop = vm.cropMap[vm.layoutManager.panels[0].id]?.sourceRect

        #expect(uniformCrop != nil)
        #expect(heroCrop != nil)
    }

    @Test func regenerateLayoutUpdatesPanelAssignments() {
        let vm = makeViewModel()

        let images = (0..<3).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.imageLibrary.images = images
        vm.regenerateLayout()

        #expect(vm.layoutManager.panelAssignments.count == vm.layoutManager.panels.count)

        for panel in vm.layoutManager.panels {
            #expect(vm.layoutManager.panelAssignments[panel.id] != nil)
        }
    }

    @Test func gutterChangeRegeneratesLayout() async {
        let vm = makeViewModel()

        let images = (0..<4).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.imageLibrary.images = images
        vm.setGutter(0)

        try? await Task.sleep(nanoseconds: 200_000_000)

        let panelsNoGutter = vm.layoutManager.panels.map { $0.frame }

        vm.setGutter(20)

        try? await Task.sleep(nanoseconds: 200_000_000)

        let panelsWithGutter = vm.layoutManager.panels.map { $0.frame }

        #expect(panelsNoGutter != panelsWithGutter)
    }
}
