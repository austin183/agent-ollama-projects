import AppKit
import CoreGraphics
import Testing
@testable import CollageMaker

@MainActor
@Suite(.serialized) struct CollagePerformanceTests {

    @Test func scrollPreviewUpdatesAssembler() async {
        let trackingAssembler = TrackingAssembler()
        let mockSaliency = MockSaliencyAnalyzer()
        let vm = CollageViewModel(saliencyAnalyzer: mockSaliency, assembler: trackingAssembler)

        let image = createTestImageItem(size: CGSize(width: 200, height: 200))
        vm.images = [image]
        vm.regenerateLayout()

        let initialPreviewCalls = trackingAssembler.previewCalls

        for _ in 0..<20 {
            vm.scrollPanDelta(CGSize(width: 5, height: 3))
        }

        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(trackingAssembler.previewCalls > initialPreviewCalls)
    }

    @Test func scrollPanMultipleIterations() async {
        let trackingAssembler = TrackingAssembler()
        let mockSaliency = MockSaliencyAnalyzer()
        let vm = CollageViewModel(saliencyAnalyzer: mockSaliency, assembler: trackingAssembler)

        let images = (0..<5).map { _ in createTestImageItem(size: CGSize(width: 200, height: 200)) }
        vm.images = images
        vm.regenerateLayout()

        for iteration in 0..<10 {
            for delta in 1...5 {
                vm.scrollPanDelta(CGSize(width: CGFloat(delta), height: CGFloat(delta)))
            }
        }

        try? await Task.sleep(nanoseconds: 200_000_000)

        #expect(trackingAssembler.previewCalls > 0)
        #expect(vm.panels.count == 5)
    }
}
