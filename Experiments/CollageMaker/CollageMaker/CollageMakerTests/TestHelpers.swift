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
