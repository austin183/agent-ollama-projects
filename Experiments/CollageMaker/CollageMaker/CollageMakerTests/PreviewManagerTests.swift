import AppKit
import CoreGraphics
import Testing
@testable import CollageMaker

@MainActor
@Suite(.serialized) struct PreviewManagerTests {
    private let assembler = TestAssembler()
    private var manager: PreviewManager {
        PreviewManager(assembler: assembler)
    }

    // MARK: - Initial state

    @Test func initialStateIsEmpty() {
        let mgr = manager
        #expect(mgr.previewImage == nil)
        #expect(mgr.previewBackgroundImage == nil)
        #expect(mgr.panelRenderedImages.isEmpty)
        #expect(mgr.titleImage == nil)
    }

    // MARK: - Preview rendering

    @Test func updatePreviewRendersImage() async {
        let mgr = manager
        let image = createTestImageItem(color: .systemBlue, size: CGSize(width: 200, height: 200))
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)
        let crops: [UUID: CropInfo] = [panels[0].id: CropInfo(
            panelId: panels[0].id,
            sourceRect: CGRect(origin: .zero, size: image.size),
            destinationRect: panels[0].frame
        )]

        let config = makeAssemblyConfig(panels: panels, crops: crops)

        mgr.updatePreview(
            config: config,
            cgImages: [image.cgImage],
            backgroundImage: nil,
            previewSize: SizeConstants.defaultPreviewSize
        )

        try? await Task.sleep(for: .milliseconds(200))
        #expect(mgr.previewImage != nil)
    }

    // MARK: - Background rendering

    @Test func updateBackgroundRendersImage() async {
        let mgr = manager
        let config = BackgroundConfig(
            style: .solid,
            color: .systemBlue,
            gradientStartColor: .black,
            gradientEndColor: .darkGray,
            gradientAngle: 0,
            opacity: 1.0
        )

        mgr.updateBackground(
            config: config,
            canvasSize: SizeConstants.defaultCanvasSize,
            backgroundImage: nil,
            previewSize: SizeConstants.defaultPreviewSize
        )

        try? await Task.sleep(for: .milliseconds(200))
        #expect(mgr.previewBackgroundImage != nil)
    }

    // MARK: - Panel preview rendering

    @Test func updatePanelPreviewRendersImage() async {
        let mgr = manager
        let cgImage = createTestCGImage(color: .systemGreen, size: CGSize(width: 200, height: 200))
        let panelId = UUID()
        let crop = CropInfo(
            panelId: panelId,
            sourceRect: CGRect(x: 0, y: 0, width: 200, height: 200),
            destinationRect: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        mgr.updatePanelPreview(
            crop: crop,
            cgImage: cgImage,
            panelSize: CGSize(width: 100, height: 100),
            geometry: .rect(CGRect(x: 0, y: 0, width: 100, height: 100)),
            panelId: panelId
        )

        try? await Task.sleep(for: .milliseconds(200))
        #expect(mgr.panelRenderedImages[panelId] != nil)
    }

    // MARK: - Title rendering

    @Test func updateTitleImageRendersImage() async {
        let mgr = manager

        mgr.updateTitleImage(
            titleAttrString: NSAttributedString(string: "Test Title"),
            titleStyle: TitleStyle.default,
            canvasSize: SizeConstants.defaultCanvasSize
        )

        try? await Task.sleep(for: .milliseconds(200))
        #expect(mgr.titleImage != nil)
    }

    @Test func updateTitleImageEmptyReturnsNil() async {
        let mgr = manager

        mgr.updateTitleImage(
            titleAttrString: NSAttributedString(string: ""),
            titleStyle: TitleStyle.default,
            canvasSize: SizeConstants.defaultCanvasSize
        )

        try? await Task.sleep(for: .milliseconds(200))
        #expect(mgr.titleImage == nil)
    }

    // MARK: - Cancel previous task on rapid calls

    @Test func rapidPreviewUpdatesCancelPrevious() async {
        let mgr = manager
        let image = createTestImageItem(color: .systemBlue, size: CGSize(width: 200, height: 200))
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)
        let crops: [UUID: CropInfo] = [panels[0].id: CropInfo(
            panelId: panels[0].id,
            sourceRect: CGRect(origin: .zero, size: image.size),
            destinationRect: panels[0].frame
        )]

        let config = makeAssemblyConfig(panels: panels, crops: crops)

        // Fire multiple rapid updates
        for _ in 0..<5 {
            mgr.updatePreview(
                config: config,
                cgImages: [image.cgImage],
                backgroundImage: nil,
                previewSize: SizeConstants.defaultPreviewSize
            )
        }

        try? await Task.sleep(for: .milliseconds(300))
        #expect(mgr.previewImage != nil)
    }

    // MARK: - clearAll

    @Test func clearAllResetsState() {
        let mgr = manager
        mgr.previewImage = NSImage(size: CGSize(width: 100, height: 100))
        mgr.previewBackgroundImage = NSImage(size: CGSize(width: 100, height: 100))
        mgr.panelRenderedImages[UUID()] = NSImage(size: CGSize(width: 100, height: 100))
        mgr.titleImage = NSImage(size: CGSize(width: 100, height: 100))

        mgr.clearAll()

        #expect(mgr.previewImage == nil)
        #expect(mgr.previewBackgroundImage == nil)
        #expect(mgr.panelRenderedImages.isEmpty)
        #expect(mgr.titleImage == nil)
    }

    // MARK: - Concurrent panel rendering

    @Test func multiplePanelsRenderConcurrently() async {
        let mgr = manager
        let panelIds = [UUID(), UUID(), UUID()]
        let cgImage = createTestCGImage(color: .systemGreen, size: CGSize(width: 200, height: 200))

        for panelId in panelIds {
            let crop = CropInfo(
                panelId: panelId,
                sourceRect: CGRect(x: 0, y: 0, width: 200, height: 200),
                destinationRect: CGRect(x: 0, y: 0, width: 100, height: 100)
            )
            mgr.updatePanelPreview(
                crop: crop,
                cgImage: cgImage,
                panelSize: CGSize(width: 100, height: 100),
                geometry: .rect(CGRect(x: 0, y: 0, width: 100, height: 100)),
                panelId: panelId
            )
        }

        try? await Task.sleep(for: .milliseconds(300))
        #expect(mgr.panelRenderedImages[panelIds[0]] != nil)
        #expect(mgr.panelRenderedImages[panelIds[1]] != nil)
        #expect(mgr.panelRenderedImages[panelIds[2]] != nil)
    }

    @Test func updateAllPanelPreviewsRendersAllConcurrently() async {
        let mgr = manager
        let images = (0..<3).map { _ in
            createTestImageItem(color: .systemBlue, size: CGSize(width: 200, height: 200))
        }
        let panels = LayoutGenerator.generate(numImages: 3, style: .uniform)
        let crops: [UUID: CropInfo] = Dictionary(
            panels.map {
                ($0.id, CropInfo(
                    panelId: $0.id,
                    sourceRect: CGRect(origin: .zero, size: CGSize(width: 200, height: 200)),
                    destinationRect: $0.frame
                ))
            },
            uniquingKeysWith: { first, _ in first }
        )
        let assignments: [UUID: Int] = Dictionary(
            panels.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )

        mgr.updateAllPanelPreviews(
            panels: panels,
            crops: crops,
            images: images,
            panelAssignments: assignments
        )

        try? await Task.sleep(for: .milliseconds(300))
        for panel in panels {
            #expect(mgr.panelRenderedImages[panel.id] != nil,
                    "Panel \(panel.id) should have a rendered preview")
        }
    }

    // MARK: - Generation-based stale discard

    @Test func stalePreviewRenderIsDiscarded() async {
        let slowAssembler = TestAssembler()
        slowAssembler.previewDelayMs = 100
        let mgr = PreviewManager(assembler: slowAssembler)

        let image = createTestImageItem(color: .systemBlue, size: CGSize(width: 200, height: 200))
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)
        let crops: [UUID: CropInfo] = [panels[0].id: CropInfo(
            panelId: panels[0].id,
            sourceRect: CGRect(origin: .zero, size: image.size),
            destinationRect: panels[0].frame
        )]

        let config = makeAssemblyConfig(panels: panels, crops: crops)

        // First update – will be slow (100ms)
        mgr.updatePreview(
            config: config,
            cgImages: [image.cgImage],
            backgroundImage: nil,
            previewSize: SizeConstants.defaultPreviewSize
        )

        // Second update – will be fast (10ms), should win
        try? await Task.sleep(for: .milliseconds(5))
        slowAssembler.previewDelayMs = 10
        mgr.updatePreview(
            config: config,
            cgImages: [image.cgImage],
            backgroundImage: nil,
            previewSize: SizeConstants.defaultPreviewSize
        )

        try? await Task.sleep(for: .milliseconds(200))

        // The second (faster) render should have completed first,
        // and the first (slower) render should be discarded as stale.
        #expect(mgr.previewImage != nil)
    }
}
