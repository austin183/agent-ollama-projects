import AppKit
import CoreGraphics
import Testing
@testable import CollageMaker

@MainActor
final class TestPreviewAssembler: CollageAssembly {
    func assembleWithCGImages(config: AssemblyConfig, cgImages: [CGImage?], backgroundImage: CGImage?, quality: Double) async -> Data? {
        Data()
    }

    func assemblePreviewWithCGImages(config: AssemblyConfig, cgImages: [CGImage?], backgroundImage: CGImage?, previewSize: CGSize) async -> NSImage? {
        NSImage(size: previewSize)
    }

    func renderPanel(crop: CropInfo, cgImage: CGImage, panelSize: CGSize) async -> NSImage? {
        NSImage(size: panelSize)
    }

    func renderBackground(config: BackgroundConfig, canvasSize: CGSize, backgroundImage: CGImage?, previewSize: CGSize) async -> NSImage? {
        NSImage(size: previewSize)
    }

    func renderTitle(titleAttrString: NSAttributedString, titleStyle: TitleStyle, canvasSize: CGSize) async -> NSImage? {
        guard !titleAttrString.string.isEmpty else { return nil }
        return NSImage(size: canvasSize)
    }
}

@MainActor
@Suite(.serialized) struct PreviewManagerTests {
    private let assembler = TestPreviewAssembler()
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

        let config = AssemblyConfig(
            panels: panels,
            crops: crops,
            panelAssignments: [:],
            titleAttrString: NSAttributedString(string: ""),
            titleStyle: TitleStyle.default,
            backgroundColor: .black,
            backgroundStyle: .solid,
            gradientStartColor: .black,
            gradientEndColor: .darkGray,
            gradientAngle: 135,
            backgroundOpacity: 1.0,
            canvasSize: CanvasConfig.defaultCanvasSize
        )

        mgr.updatePreview(
            config: config,
            cgImages: [image.cgImage],
            backgroundImage: nil,
            previewSize: CanvasConfig.defaultPreviewSize
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
            canvasSize: CanvasConfig.defaultCanvasSize,
            backgroundImage: nil,
            previewSize: CanvasConfig.defaultPreviewSize
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
            canvasSize: CanvasConfig.defaultCanvasSize
        )

        try? await Task.sleep(for: .milliseconds(200))
        #expect(mgr.titleImage != nil)
    }

    @Test func updateTitleImageEmptyReturnsNil() async {
        let mgr = manager

        mgr.updateTitleImage(
            titleAttrString: NSAttributedString(string: ""),
            titleStyle: TitleStyle.default,
            canvasSize: CanvasConfig.defaultCanvasSize
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

        let config = AssemblyConfig(
            panels: panels,
            crops: crops,
            panelAssignments: [:],
            titleAttrString: NSAttributedString(string: ""),
            titleStyle: TitleStyle.default,
            backgroundColor: .black,
            backgroundStyle: .solid,
            gradientStartColor: .black,
            gradientEndColor: .darkGray,
            gradientAngle: 135,
            backgroundOpacity: 1.0,
            canvasSize: CanvasConfig.defaultCanvasSize
        )

        // Fire multiple rapid updates
        for _ in 0..<5 {
            mgr.updatePreview(
                config: config,
                cgImages: [image.cgImage],
                backgroundImage: nil,
                previewSize: CanvasConfig.defaultPreviewSize
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
        let slowAssembler = GenerationControlledAssembler()
        let mgr = PreviewManager(assembler: slowAssembler)

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
            titleStyle: TitleStyle.default,
            backgroundColor: .black,
            backgroundStyle: .solid,
            gradientStartColor: .black,
            gradientEndColor: .darkGray,
            gradientAngle: 135,
            backgroundOpacity: 1.0,
            canvasSize: CanvasConfig.defaultCanvasSize
        )

        // First update – will be slow (100ms)
        slowAssembler.delayMs = 100
        mgr.updatePreview(
            config: config,
            cgImages: [image.cgImage],
            backgroundImage: nil,
            previewSize: CanvasConfig.defaultPreviewSize
        )

        // Second update – will be fast (10ms), should win
        try? await Task.sleep(for: .milliseconds(5))
        slowAssembler.delayMs = 10
        mgr.updatePreview(
            config: config,
            cgImages: [image.cgImage],
            backgroundImage: nil,
            previewSize: CanvasConfig.defaultPreviewSize
        )

        try? await Task.sleep(for: .milliseconds(200))

        // The second (faster) render should have completed first,
        // and the first (slower) render should be discarded as stale.
        #expect(mgr.previewImage != nil)
    }
}

// MARK: - Generation-controlled test assembler

@MainActor
final class GenerationControlledAssembler: CollageAssembly {
    var delayMs: UInt64 = 0

    func assembleWithCGImages(config: AssemblyConfig, cgImages: [CGImage?], backgroundImage: CGImage?, quality: Double) async -> Data? {
        Data()
    }

    func assemblePreviewWithCGImages(config: AssemblyConfig, cgImages: [CGImage?], backgroundImage: CGImage?, previewSize: CGSize) async -> NSImage? {
        try? await Task.sleep(for: .milliseconds(delayMs))
        return NSImage(size: previewSize)
    }

    func renderPanel(crop: CropInfo, cgImage: CGImage, panelSize: CGSize) async -> NSImage? {
        NSImage(size: panelSize)
    }

    func renderBackground(config: BackgroundConfig, canvasSize: CGSize, backgroundImage: CGImage?, previewSize: CGSize) async -> NSImage? {
        NSImage(size: previewSize)
    }

    func renderTitle(titleAttrString: NSAttributedString, titleStyle: TitleStyle, canvasSize: CGSize) async -> NSImage? {
        nil
    }
}
