import AppKit
import CoreGraphics
import Testing
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
    let nsImage = NSImage(cgImage: cgImage, size: size)
    let thumbnail = NSImage(cgImage: cgImage, size: CGSize(width: 64, height: 64))
    return ImageItem(id: id, nsImage: nsImage, cgImage: cgImage, thumbnail: thumbnail, filename: filename, size: size)
}

// MARK: - Tracking Assembler

final class TrackingAssembler: CollageAssembly {
    var assembleCalls = 0
    var previewCalls = 0
    var renderPanelCalls = 0
    var renderBackgroundCalls = 0
    var titleRenderCalls = 0
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

    func assembleWithCGImages(config: AssemblyConfig, cgImages: [CGImage?], backgroundImage: CGImage?, quality: Double) async -> Data? {
        assembleCalls += 1
        lastAssemblePanels = config.layout.panels
        lastAssembleCgImages = cgImages
        lastAssembleCrops = config.layout.crops
        lastAssembleAssignments = config.layout.panelAssignments
        lastAssembleTitle = config.title.textData.text
        lastAssembleTitleStyle = config.title.style
        lastAssembleCanvasSize = config.canvasSize
        lastAssembleQuality = quality
        return Data([0xFF, 0xD8, 0xFF, 0xE0])
    }

    func assemblePreviewWithCGImages(config: AssemblyConfig, cgImages: [CGImage?], backgroundImage: CGImage?, previewSize: CGSize) async -> NSImage? {
        previewCalls += 1
        lastPreviewCanvasSize = config.canvasSize
        lastPreviewPreviewSize = previewSize
        lastPreviewPanels = config.layout.panels
        lastPreviewTitle = config.title.textData.text
        return NSImage(size: previewSize)
    }

    func renderPanel(crop: CropInfo, cgImage: CGImage, panelSize: CGSize) async -> NSImage? {
        renderPanelCalls += 1
        return NSImage(size: panelSize)
    }

    func renderBackground(config: BackgroundConfig, canvasSize: CGSize, backgroundImage: CGImage?, previewSize: CGSize) async -> NSImage? {
        renderBackgroundCalls += 1
        return NSImage(size: previewSize)
    }

    func renderTitle(titleConfig: TitleConfig, canvasSize: CGSize) async -> NSImage? {
        titleRenderCalls += 1
        return nil
    }
}

@MainActor
func makeAssemblyConfig(
    panels: [ImagePanel] = [],
    crops: [UUID: CropInfo] = [:],
    panelAssignments: [UUID: Int] = [:],
    titleText: String = "",
    titleStyle: TitleStyle = .default,
    backgroundColor: NSColor = .black,
    backgroundStyle: BackgroundStyle = .solid,
    gradientStartColor: NSColor = .black,
    gradientEndColor: NSColor = .darkGray,
    gradientAngle: Double = 135,
    backgroundOpacity: Double = 1.0,
    canvasSize: CGSize = CanvasConfig.defaultCanvasSize
) -> AssemblyConfig {
    let attrString = NSAttributedString(string: titleText)
    let textData = TitleTextData.extract(from: attrString)
    return AssemblyConfig(
        panels: panels,
        crops: crops,
        panelAssignments: panelAssignments,
        titleTextData: textData,
        titleStyle: titleStyle,
        titleFontColor: titleStyle.fontColor.cgColor,
        titleBackgroundColor: titleStyle.backgroundColor.cgColor,
        backgroundColor: backgroundColor,
        backgroundStyle: backgroundStyle,
        gradientStartColor: gradientStartColor,
        gradientEndColor: gradientEndColor,
        gradientAngle: gradientAngle,
        backgroundOpacity: backgroundOpacity,
        canvasSize: canvasSize
    )
}
