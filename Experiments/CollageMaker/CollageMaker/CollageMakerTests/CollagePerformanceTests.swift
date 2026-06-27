import AppKit
import CoreGraphics
import Testing
@testable import CollageMaker

@MainActor
@Suite(.serialized) struct CollagePerformanceTests {

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

    @Test func scrollPreviewUpdatesAssembler() async {
        let assembler = TestAssembler()
        assembler.trackCalls = true
        let vm = makeViewModel(assembler: assembler)

        let image = createTestImageItem(size: CGSize(width: 200, height: 200))
        vm.imageLibrary.images = [image]
        vm.regenerateLayout()

        let initialPanelCalls = assembler.renderPanelCalls

        for _ in 0..<20 {
            vm.scrollPanDelta(CGSize(width: 5, height: 3))
        }

        try? await Task.sleep(nanoseconds: 300_000_000)

        #expect(assembler.renderPanelCalls > initialPanelCalls)
        vm.previewManager.cancelAll()
    }

    @Test func scrollPanMultipleIterations() async {
        let assembler = TestAssembler()
        assembler.trackCalls = true
        let vm = makeViewModel(assembler: assembler)

        let images = (0..<5).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.imageLibrary.images = images
        vm.regenerateLayout()

        for _ in 0..<10 {
            for delta in 1...5 {
                vm.scrollPanDelta(CGSize(width: CGFloat(delta), height: CGFloat(delta)))
            }
        }

        try? await Task.sleep(nanoseconds: 200_000_000)

        #expect(assembler.renderPanelCalls > 0)
        #expect(vm.layoutManager.panels.count == 5)
        vm.previewManager.cancelAll()
    }
}
