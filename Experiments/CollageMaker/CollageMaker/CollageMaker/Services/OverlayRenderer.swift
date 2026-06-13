import AppKit
import CoreGraphics
import Foundation

/// Pure struct — CoreGraphics overlay rendering logic.
struct OverlayRenderer {
    static func drawOverlay(into context: CGContext, overlay: OverlayConfig, canvasSize: CGSize) {
        context.saveGState()
        context.setBlendMode(overlay.blendMode)
        context.setAlpha(overlay.opacity)
        context.draw(overlay.maskImage, in: CGRect(origin: .zero, size: canvasSize))
        context.restoreGState()
    }

    static func renderOverlay(overlay: OverlayConfig, canvasSize: CGSize) -> NSImage? {
        guard let context = ContextFactory.createBitmap(size: canvasSize) else { return nil }
        drawOverlay(into: context, overlay: overlay, canvasSize: canvasSize)
        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: canvasSize)
    }

}
