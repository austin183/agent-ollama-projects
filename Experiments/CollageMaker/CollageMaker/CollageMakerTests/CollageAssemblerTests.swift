import AppKit
import CoreGraphics
import Testing
@testable import CollageMaker

@MainActor
@Suite(.serialized) struct CollageAssemblerTests {

    private let assembler = CollageAssembler()

    @Test func assemblePreviewReturnsImage() {
        let image = createTestImageItem(color: .systemBlue, size: CGSize(width: 200, height: 200))
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)
        let crops: [UUID: CropInfo] = [panels[0].id: CropInfo(
            panelId: panels[0].id,
            sourceRect: CGRect(origin: .zero, size: image.size),
            destinationRect: panels[0].frame
        )]

        let config = AssemblyConfig(
            panels: panels,
            crops: crops,
            panelAssignments: [:],
            titleAttrString: NSAttributedString(string: ""),
            titleStyle: .default,
            backgroundColor: .black,
            backgroundStyle: .solid,
            gradientStartColor: .black,
            gradientEndColor: .darkGray,
            gradientAngle: 135,
            backgroundOpacity: 1.0,
            canvasSize: CanvasConfig.defaultCanvasSize
        )

        let preview = assembler.assemblePreview(
            config: config,
            images: [image.nsImage],
            backgroundImage: nil,
            previewSize: CanvasConfig.defaultPreviewSize
        )

        #expect(preview != nil)
    }

    @Test func assemblePreviewWithCGImagesReturnsImage() {
        let cgImage = createTestCGImage(color: .systemBlue, size: CGSize(width: 200, height: 200))
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)
        let crops: [UUID: CropInfo] = [panels[0].id: CropInfo(
            panelId: panels[0].id,
            sourceRect: CGRect(origin: .zero, size: CGSize(width: 200, height: 200)),
            destinationRect: panels[0].frame
        )]

        let config = AssemblyConfig(
            panels: panels,
            crops: crops,
            panelAssignments: [:],
            titleAttrString: NSAttributedString(string: ""),
            titleStyle: .default,
            backgroundColor: .black,
            backgroundStyle: .solid,
            gradientStartColor: .black,
            gradientEndColor: .darkGray,
            gradientAngle: 135,
            backgroundOpacity: 1.0,
            canvasSize: CanvasConfig.defaultCanvasSize
        )

        let preview = assembler.assemblePreviewWithCGImages(
            config: config,
            cgImages: [cgImage],
            backgroundImage: nil,
            previewSize: CanvasConfig.defaultPreviewSize
        )

        #expect(preview != nil)
    }

    @Test func assembleWithCGImagesReturnsData() {
        let cgImage = createTestCGImage(color: .systemBlue, size: CGSize(width: 200, height: 200))
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)
        let crops: [UUID: CropInfo] = [panels[0].id: CropInfo(
            panelId: panels[0].id,
            sourceRect: CGRect(origin: .zero, size: CGSize(width: 200, height: 200)),
            destinationRect: panels[0].frame
        )]

        let config = AssemblyConfig(
            panels: panels,
            crops: crops,
            panelAssignments: [:],
            titleAttrString: NSAttributedString(string: ""),
            titleStyle: .default,
            backgroundColor: .black,
            backgroundStyle: .solid,
            gradientStartColor: .black,
            gradientEndColor: .darkGray,
            gradientAngle: 135,
            backgroundOpacity: 1.0,
            canvasSize: CanvasConfig.defaultCanvasSize
        )

        let data = assembler.assembleWithCGImages(
            config: config,
            cgImages: [cgImage],
            backgroundImage: nil,
            quality: 0.9
        )

        #expect(data != nil)
        #expect(data!.count > 0)
    }

    @Test func assembleWithTitleReturnsData() {
        let cgImage = createTestCGImage(color: .systemBlue, size: CGSize(width: 200, height: 200))
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)
        let crops: [UUID: CropInfo] = [panels[0].id: CropInfo(
            panelId: panels[0].id,
            sourceRect: CGRect(origin: .zero, size: CGSize(width: 200, height: 200)),
            destinationRect: panels[0].frame
        )]

        let config = AssemblyConfig(
            panels: panels,
            crops: crops,
            panelAssignments: [:],
            titleAttrString: NSAttributedString(string: "Test Collage"),
            titleStyle: .default,
            backgroundColor: .black,
            backgroundStyle: .solid,
            gradientStartColor: .black,
            gradientEndColor: .darkGray,
            gradientAngle: 135,
            backgroundOpacity: 1.0,
            canvasSize: CanvasConfig.defaultCanvasSize
        )

        let data = assembler.assembleWithCGImages(
            config: config,
            cgImages: [cgImage],
            backgroundImage: nil,
            quality: 0.9
        )

        #expect(data != nil)
    }

    @Test func assembleMultiplePanels() {
        let img1 = createTestCGImage(color: .systemBlue, size: CGSize(width: 200, height: 200))
        let img2 = createTestCGImage(color: .systemGreen, size: CGSize(width: 200, height: 200))
        let img3 = createTestCGImage(color: .systemRed, size: CGSize(width: 200, height: 200))
        let panels = LayoutGenerator.generate(numImages: 3, style: .uniform)

        var crops: [UUID: CropInfo] = [:]
        for panel in panels {
            crops[panel.id] = CropInfo(
                panelId: panel.id,
                sourceRect: CGRect(origin: .zero, size: CGSize(width: 200, height: 200)),
                destinationRect: panel.frame
            )
        }

        let config = AssemblyConfig(
            panels: panels,
            crops: crops,
            panelAssignments: [:],
            titleAttrString: NSAttributedString(string: ""),
            titleStyle: .default,
            backgroundColor: .black,
            backgroundStyle: .solid,
            gradientStartColor: .black,
            gradientEndColor: .darkGray,
            gradientAngle: 135,
            backgroundOpacity: 1.0,
            canvasSize: CanvasConfig.defaultCanvasSize
        )

        let data = assembler.assembleWithCGImages(
            config: config,
            cgImages: [img1, img2, img3],
            backgroundImage: nil,
            quality: 0.9
        )

        #expect(data != nil)
    }

    @Test func assembleWithMissingCropsSkipsPanel() {
        let cgImage = createTestCGImage(color: .systemBlue, size: CGSize(width: 200, height: 200))
        let panels = LayoutGenerator.generate(numImages: 2, style: .uniform)
        var crops: [UUID: CropInfo] = [:]
        crops[panels[0].id] = CropInfo(
            panelId: panels[0].id,
            sourceRect: CGRect(origin: .zero, size: CGSize(width: 200, height: 200)),
            destinationRect: panels[0].frame
        )

        let config = AssemblyConfig(
            panels: panels,
            crops: crops,
            panelAssignments: [:],
            titleAttrString: NSAttributedString(string: ""),
            titleStyle: .default,
            backgroundColor: .black,
            backgroundStyle: .solid,
            gradientStartColor: .black,
            gradientEndColor: .darkGray,
            gradientAngle: 135,
            backgroundOpacity: 1.0,
            canvasSize: CanvasConfig.defaultCanvasSize
        )

        let data = assembler.assembleWithCGImages(
            config: config,
            cgImages: [cgImage, cgImage],
            backgroundImage: nil,
            quality: 0.9
        )

        #expect(data != nil)
    }

    @Test func assembleEmptyCanvasReturnsData() {
        let config = AssemblyConfig(
            panels: [],
            crops: [:],
            panelAssignments: [:],
            titleAttrString: NSAttributedString(string: ""),
            titleStyle: .default,
            backgroundColor: .black,
            backgroundStyle: .solid,
            gradientStartColor: .black,
            gradientEndColor: .darkGray,
            gradientAngle: 135,
            backgroundOpacity: 1.0,
            canvasSize: CanvasConfig.defaultCanvasSize
        )

        let data = assembler.assembleWithCGImages(
            config: config,
            cgImages: [],
            backgroundImage: nil,
            quality: 0.9
        )

        #expect(data != nil)
    }

    @Test func assemblePreviewSize() {
        let cgImage = createTestCGImage(color: .systemBlue, size: CGSize(width: 200, height: 200))
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)
        let crops: [UUID: CropInfo] = [panels[0].id: CropInfo(
            panelId: panels[0].id,
            sourceRect: CGRect(origin: .zero, size: CGSize(width: 200, height: 200)),
            destinationRect: panels[0].frame
        )]

        let config = AssemblyConfig(
            panels: panels,
            crops: crops,
            panelAssignments: [:],
            titleAttrString: NSAttributedString(string: ""),
            titleStyle: .default,
            backgroundColor: .black,
            backgroundStyle: .solid,
            gradientStartColor: .black,
            gradientEndColor: .darkGray,
            gradientAngle: 135,
            backgroundOpacity: 1.0,
            canvasSize: CanvasConfig.defaultCanvasSize
        )

        let preview = assembler.assemblePreviewWithCGImages(
            config: config,
            cgImages: [cgImage],
            backgroundImage: nil,
            previewSize: CanvasConfig.defaultPreviewSize
        )

        #expect(preview != nil)
        #expect(preview?.size == CanvasConfig.defaultPreviewSize)
    }

    @Test func assembleWithGradientBackground() {
        let cgImage = createTestCGImage(color: .systemBlue, size: CGSize(width: 200, height: 200))
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)
        let crops: [UUID: CropInfo] = [panels[0].id: CropInfo(
            panelId: panels[0].id,
            sourceRect: CGRect(origin: .zero, size: CGSize(width: 200, height: 200)),
            destinationRect: panels[0].frame
        )]

        let config = AssemblyConfig(
            panels: panels,
            crops: crops,
            panelAssignments: [:],
            titleAttrString: NSAttributedString(string: ""),
            titleStyle: .default,
            backgroundColor: .black,
            backgroundStyle: .gradient,
            gradientStartColor: .systemBlue,
            gradientEndColor: .systemPurple,
            gradientAngle: 45,
            backgroundOpacity: 1.0,
            canvasSize: CanvasConfig.defaultCanvasSize
        )

        let data = assembler.assembleWithCGImages(
            config: config,
            cgImages: [cgImage],
            backgroundImage: nil,
            quality: 0.9
        )

        #expect(data != nil)
        #expect(data!.count > 0)
    }

    @Test func assembleWithPanelAssignment() {
        let img1 = createTestCGImage(color: .systemBlue, size: CGSize(width: 200, height: 200))
        let img2 = createTestCGImage(color: .systemGreen, size: CGSize(width: 200, height: 200))
        let panels = LayoutGenerator.generate(numImages: 2, style: .uniform)

        var crops: [UUID: CropInfo] = [:]
        for panel in panels {
            crops[panel.id] = CropInfo(
                panelId: panel.id,
                sourceRect: CGRect(origin: .zero, size: CGSize(width: 200, height: 200)),
                destinationRect: panel.frame
            )
        }

        let assignments: [UUID: Int] = [panels[0].id: 1, panels[1].id: 0]

        let config = AssemblyConfig(
            panels: panels,
            crops: crops,
            panelAssignments: assignments,
            titleAttrString: NSAttributedString(string: ""),
            titleStyle: .default,
            backgroundColor: .black,
            backgroundStyle: .solid,
            gradientStartColor: .black,
            gradientEndColor: .darkGray,
            gradientAngle: 135,
            backgroundOpacity: 1.0,
            canvasSize: CanvasConfig.defaultCanvasSize
        )

        let data = assembler.assembleWithCGImages(
            config: config,
            cgImages: [img1, img2],
            backgroundImage: nil,
            quality: 0.9
        )

        #expect(data != nil)
    }

    // MARK: - Concurrent rendering (RenderQueue thread safety)

    @Test func concurrentAssemblePreviewCallsComplete() async {
        let cgImage = createTestCGImage(color: .systemBlue, size: CGSize(width: 200, height: 200))
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)
        let crops: [UUID: CropInfo] = [panels[0].id: CropInfo(
            panelId: panels[0].id,
            sourceRect: CGRect(origin: .zero, size: CGSize(width: 200, height: 200)),
            destinationRect: panels[0].frame
        )]

        let config = AssemblyConfig(
            panels: panels,
            crops: crops,
            panelAssignments: [:],
            titleAttrString: NSAttributedString(string: ""),
            titleStyle: .default,
            backgroundColor: .black,
            backgroundStyle: .solid,
            gradientStartColor: .black,
            gradientEndColor: .darkGray,
            gradientAngle: 135,
            backgroundOpacity: 1.0,
            canvasSize: CanvasConfig.defaultCanvasSize
        )

        let tasks = (0..<10).map { _ in
            Task.detached {
                self.assembler.assemblePreviewWithCGImages(
                    config: config,
                    cgImages: [cgImage],
                    backgroundImage: nil,
                    previewSize: CanvasConfig.defaultPreviewSize
                )
            }
        }

        let allResults = await withTaskGroup(of: NSImage?.self) { group in
            var results: [NSImage?] = []
            for task in tasks {
                group.addTask { await task.value }
            }
            for await result in group {
                results.append(result)
            }
            return results
        }

        #expect(allResults.allSatisfy { $0 != nil })
    }

    @Test func concurrentRenderPanelCallsComplete() async {
        let cgImage = createTestCGImage(color: .systemGreen, size: CGSize(width: 200, height: 200))
        let panelId = UUID()
        let crop = CropInfo(
            panelId: panelId,
            sourceRect: CGRect(x: 0, y: 0, width: 200, height: 200),
            destinationRect: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        let tasks = (0..<10).map { _ in
            Task.detached {
                self.assembler.renderPanel(
                    crop: crop,
                    cgImage: cgImage,
                    panelSize: CGSize(width: 100, height: 100)
                )
            }
        }

        let allResults = await withTaskGroup(of: NSImage?.self) { group in
            var results: [NSImage?] = []
            for task in tasks {
                group.addTask { await task.value }
            }
            for await result in group {
                results.append(result)
            }
            return results
        }

        #expect(allResults.allSatisfy { $0 != nil })
    }

    @Test func concurrentRenderBackgroundCallsComplete() async {
        let config = BackgroundConfig(
            style: .solid,
            color: .systemBlue,
            gradientStartColor: .black,
            gradientEndColor: .darkGray,
            gradientAngle: 0,
            opacity: 1.0
        )

        let tasks = (0..<10).map { _ in
            Task.detached {
                self.assembler.renderBackground(
                    config: config,
                    canvasSize: CanvasConfig.defaultCanvasSize,
                    backgroundImage: nil,
                    previewSize: CanvasConfig.defaultPreviewSize
                )
            }
        }

        let allResults = await withTaskGroup(of: NSImage?.self) { group in
            var results: [NSImage?] = []
            for task in tasks {
                group.addTask { await task.value }
            }
            for await result in group {
                results.append(result)
            }
            return results
        }

        #expect(allResults.allSatisfy { $0 != nil })
    }
}
