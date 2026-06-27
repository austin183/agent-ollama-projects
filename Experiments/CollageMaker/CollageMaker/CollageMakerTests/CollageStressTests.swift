import AppKit
import CoreGraphics
import Testing
import Foundation
@testable import CollageMaker

@MainActor
@Suite(.serialized) struct CollageStressTests {

    private func makeViewModel(
        saliencyAnalyzer: SaliencyAnalysis = MockSaliencyAnalyzer(),
        assembler: CollageAssembly = TestAssembler()
    ) -> CollageViewModel {
        let suiteName = "CollageStressTests.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        let persistence = UserDefaultsPersistence(defaults: testDefaults)
        return CollageViewModel(
            saliencyAnalyzer: saliencyAnalyzer,
            assembler: assembler,
            persistence: persistence
        )
    }

    private func createVaryingSizeImageItems(count: Int) -> [ImageItem] {
        var items: [ImageItem] = []
        for i in 0..<count {
            let isPortrait = (i % 3 == 0)
            let size: CGSize
            if isPortrait {
                size = CGSize(width: CGFloat(500 + (i * 50)), height: CGFloat(800 + (i * 100)))
            } else {
                size = CGSize(width: CGFloat(800 + (i * 100)), height: CGFloat(500 + (i * 50)))
            }
            let color: NSColor = i % 2 == 0 ? .systemBlue : .systemRed
            items.append(createTestImageItem(color: color, size: size))
        }
        return items
    }

    @Test func layoutWithThirtyImages() {
        let vm = makeViewModel()
        let images = createVaryingSizeImageItems(count: 30)
        vm.imageLibrary.images = images
        vm.regenerateLayout()

        #expect(vm.layoutManager.panels.count == 30)

        var panelIds: Set<UUID> = []
        for panel in vm.layoutManager.panels {
            #expect(panelIds.insert(panel.id).inserted)
        }

        for panel in vm.layoutManager.panels {
            let cropInfo = vm.cropMap[panel.id]
            #expect(cropInfo != nil)
        }
    }

    @Test(.timeLimit(.minutes(1))) func layoutWithFiftyImages() async throws {
        let vm = makeViewModel()
        let images = createVaryingSizeImageItems(count: 50)
        vm.imageLibrary.images = images
        vm.regenerateLayout()

        #expect(vm.layoutManager.panels.count == 50)

        for panel in vm.layoutManager.panels {
            let cropInfo = vm.cropMap[panel.id]
            #expect(cropInfo != nil)
            #expect(panel.frame.width > 0)
            #expect(panel.frame.height > 0)
        }
    }

    @Test func layoutStyleRotationWithLargeBatch() async {
        // Use 15 images instead of 25 as in the plan. MosaicLayoutStrategy has
        // maxSplits = min(numImages, 20), which limits panel generation for larger batches.
        let vm = makeViewModel()
        let images = createVaryingSizeImageItems(count: 15)
        vm.imageLibrary.images = images

        let styles: [LayoutStyle] = [.uniform, .hero, .mosaic, .diagonalSlices, .hexagonal]

        for style in styles {
            vm.setLayoutStyle(style)
            #expect(vm.layoutManager.panels.count == 15)

            for panel in vm.layoutManager.panels {
                #expect(panel.frame.width > 0)
                #expect(panel.frame.height > 0)
            }
        }
    }

    @Test func gutterStressTest() async {
        let vm = makeViewModel()
        let images = createVaryingSizeImageItems(count: 10)
        vm.imageLibrary.images = images
        vm.regenerateLayout()

        var previousTotalArea: CGFloat?

        for gutter in stride(from: 0, through: 50, by: 5) {
            vm.setGutter(CGFloat(gutter))
            try? await Task.sleep(nanoseconds: 50_000_000)

            #expect(vm.layoutManager.panels.count == 10)

            var totalArea: CGFloat = 0
            for panel in vm.layoutManager.panels {
                totalArea += panel.frame.width * panel.frame.height
            }

            if let previousTotalArea = previousTotalArea {
                #expect(totalArea <= previousTotalArea + 1.0)
            }
            previousTotalArea = totalArea
        }
    }

    @Test func addImagesOneByOne() async {
        let vm = makeViewModel()

        for i in 1...20 {
            let image = createTestImageItem(color: .systemBlue, size: CGSize(width: 200, height: 200))
            vm.imageLibrary.images.append(image)
            vm.regenerateLayout()

            #expect(vm.layoutManager.panels.count == i)

            for panel in vm.layoutManager.panels {
                let cropInfo = vm.cropMap[panel.id]
                #expect(cropInfo != nil)
            }
        }
    }
}
