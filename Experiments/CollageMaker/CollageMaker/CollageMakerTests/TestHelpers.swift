import AppKit
import CoreGraphics
import Testing
import UniformTypeIdentifiers
@testable import CollageMaker

@Suite struct AppKitInit {
    init() {
        _ = NSApplication.shared
    }
}

func createTestCGImage(color: NSColor, size: CGSize = CGSize(width: 100, height: 100)) -> CGImage {
    let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    )!
    bitmapRep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setFillColor(color.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
    NSGraphicsContext.restoreGraphicsState()
    return bitmapRep.cgImage!
}

func createTestNSImage(color: NSColor, size: CGSize = CGSize(width: 100, height: 100)) -> NSImage {
    let cgImage = createTestCGImage(color: color, size: size)
    return NSImage(cgImage: cgImage, size: size)
}

func createTestImageItem(color: NSColor = .systemBlue, size: CGSize = CGSize(width: 100, height: 100), id: UUID = UUID(), filename: String = "test.jpg") -> ImageItem {
    let cgImage = createTestCGImage(color: color, size: size)
    let thumbnail = NSImage(cgImage: cgImage, size: CGSize(width: 64, height: 64))
    return ImageItem(id: id, cgImage: cgImage, thumbnail: thumbnail, filename: filename, size: size)
}

// MARK: - Mock Saliency Analyzer

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

// MARK: - Consolidated Test Assembler

/// Unified mock for `CollageAssembly` combining tracking, configurable returns,
/// delays, and error injection.
final class TestAssembler: CollageAssembly {
    // Configuration
    var trackCalls = false
    var assembleData: Data? = Data([0xFF, 0xD8, 0xFF, 0xE0])
    var assemblePreviewImage: NSImage?
    var panelImage: NSImage?
    var backgroundImage: NSImage?
    var titleImage: NSImage?
    var previewDelayMs: UInt64 = 0
    var panelDelayMs: UInt64 = 0
    var shouldThrow = false
    var titleReturnsNilForEmpty = true

    // Call counters (only incremented when trackCalls = true)
    var assembleCalls = 0
    var previewCalls = 0
    var renderPanelCalls = 0
    var renderBackgroundCalls = 0
    var titleRenderCalls = 0

    // Last call data
    var lastAssembleConfig: AssemblyConfig?
    var lastAssembleCgImages: [CGImage?]?
    var lastAssembleQuality: Double = 0
    var lastAssemblePanels: [ImagePanel] = []
    var lastAssembleCrops: [UUID: CropInfo] = [:]
    var lastAssembleAssignments: [UUID: Int] = [:]
    var lastAssembleTitle: String = ""
    var lastAssembleTitleStyle: TitleStyle = .defaultStyle()
    var lastAssembleCanvasSize: CGSize = .zero
    var lastPreviewConfig: AssemblyConfig?
    var lastPreviewSize: CGSize = .zero
    var lastPreviewPreviewSize: CGSize = .zero
    var lastPreviewPanels: [ImagePanel] = []
    var lastPreviewTitle: String = ""
    var lastPanelCrop: CropInfo?
    var lastPanelSize: CGSize = .zero
    var lastTitleConfig: TitleConfig?
    var lastTitleCanvasSize: CGSize = .zero

    func assembleWithCGImages(config: AssemblyConfig, cgImages: [CGImage?], backgroundImage: CGImage?, quality: Double) async -> Data? {
        if trackCalls {
            assembleCalls += 1
            lastAssembleConfig = config
            lastAssembleCgImages = cgImages
            lastAssembleQuality = quality
            lastAssemblePanels = config.layout.panels
            lastAssembleCrops = config.layout.crops
            lastAssembleAssignments = config.layout.panelAssignments
            lastAssembleTitle = config.title.textData.text
            lastAssembleTitleStyle = config.title.style
            lastAssembleCanvasSize = config.canvasSize
        }
        return assembleData
    }

    func assemblePreviewWithCGImages(config: AssemblyConfig, cgImages: [CGImage?], backgroundImage: CGImage?, previewSize: CGSize) async -> NSImage? {
        if trackCalls {
            previewCalls += 1
            lastPreviewConfig = config
            lastPreviewSize = previewSize
            lastPreviewPreviewSize = previewSize
            lastPreviewPanels = config.layout.panels
            lastPreviewTitle = config.title.textData.text
        }
        if previewDelayMs > 0 {
            try? await Task.sleep(for: .milliseconds(previewDelayMs))
        }
        return assemblePreviewImage ?? NSImage(size: previewSize)
    }

    func renderPanel(crop: CropInfo, cgImage: CGImage, panelSize: CGSize, geometry: PanelGeometry) async -> NSImage? {
        if trackCalls {
            renderPanelCalls += 1
            lastPanelCrop = crop
            lastPanelSize = panelSize
        }
        if panelDelayMs > 0 {
            try? await Task.sleep(for: .milliseconds(panelDelayMs))
        }
        return panelImage ?? NSImage(size: panelSize)
    }

    func renderBackground(config: BackgroundConfig, canvasSize: CGSize, backgroundImage: CGImage?, previewSize: CGSize) async -> NSImage? {
        if trackCalls {
            renderBackgroundCalls += 1
        }
        if let bg = backgroundImage {
            return NSImage(cgImage: bg, size: previewSize)
        }
        return NSImage(size: previewSize)
    }

    func renderTitle(titleConfig: TitleConfig, canvasSize: CGSize) async -> NSImage? {
        if trackCalls {
            titleRenderCalls += 1
            lastTitleConfig = titleConfig
            lastTitleCanvasSize = canvasSize
        }
        if titleReturnsNilForEmpty, titleConfig.textData.text.isEmpty {
            return nil
        }
        return titleImage ?? NSImage(size: canvasSize)
    }

    func renderOverlay(overlay: OverlayConfig, canvasSize: CGSize) async -> NSImage? {
        NSImage(size: canvasSize)
    }
}

@MainActor
func makeAssemblyConfig(
    panels: [ImagePanel] = [],
    crops: [UUID: CropInfo] = [:],
    panelAssignments: [UUID: Int] = [:],
    titleText: String = "",
    titleStyle: TitleStyle = .defaultStyle(),
    backgroundColor: NSColor = .black,
    backgroundStyle: BackgroundStyle = .solid,
    gradientStartColor: NSColor = .black,
    gradientEndColor: NSColor = .darkGray,
    gradientAngle: Double = 135,
    backgroundOpacity: Double = 1.0,
    canvasSize: CGSize = SizeConstants.defaultCanvasSize
) -> AssemblyConfig {
    let attrString = NSAttributedString(string: titleText)
    let textData = TitleTextData.extract(from: attrString)
    return AssemblyConfig(
        layout: LayoutConfig(
            panels: panels,
            crops: crops,
            panelAssignments: panelAssignments
        ),
        title: TitleConfig(
            textData: textData,
            style: titleStyle,
            fontColor: titleStyle.fontColor.cgColor,
            backgroundColor: titleStyle.backgroundColor.cgColor
        ),
        background: BackgroundConfig(
            style: backgroundStyle,
            color: backgroundColor,
            gradientStartColor: gradientStartColor,
            gradientEndColor: gradientEndColor,
            gradientAngle: gradientAngle,
            opacity: backgroundOpacity
        ),
        canvasSize: canvasSize
    )
}

// MARK: - Mock Image Picker

final class MockImagePicker: ImagePicker, @unchecked Sendable {
    var pickResult: (image: NSImage?, path: String?) = (nil, nil)

    func pickImage(allowedTypes: [UTType]) async -> (image: NSImage?, path: String?) {
        pickResult
    }
}

// MARK: - Mock ImageCoordinationTarget

@MainActor
final class MockCoordinationTarget: ImageCoordinationTarget {
    var isProcessing = false
    var selectedPanelId: UUID?
    var errorMessage: String?
    var customImageOrder: [Int] = []

    var beginProcessingCalls = 0
    var endProcessingCalls = 0
    var updatePreviewCalls = 0
    var updateAllPanelPreviewsCalls = 0
    var updatePanelPreviewCalls: [UUID] = []
    var resetCropCalls: [UUID] = []
    var regenerateLayoutCalls = 0
    var cancelDebouncerCalls: [String] = []

    func beginProcessing() {
        beginProcessingCalls += 1
        isProcessing = true
    }

    func endProcessing() {
        endProcessingCalls += 1
        isProcessing = false
    }

    func updatePreview() {
        updatePreviewCalls += 1
    }

    func updateAllPanelPreviews() {
        updateAllPanelPreviewsCalls += 1
    }

    func updatePanelPreview(panelId: UUID) {
        updatePanelPreviewCalls.append(panelId)
    }

    func resetCrop(panelId: UUID) {
        resetCropCalls.append(panelId)
    }

    func regenerateLayout() {
        regenerateLayoutCalls += 1
    }

    func cancelDebouncer(id: String) {
        cancelDebouncerCalls.append(id)
    }
}
