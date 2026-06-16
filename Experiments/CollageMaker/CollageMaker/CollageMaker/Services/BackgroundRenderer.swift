import AppKit
import CoreGraphics
import Foundation

/// Pure struct — CoreGraphics background rendering logic.
struct BackgroundRenderer {
    static func drawSolidBackground(into context: CGContext, size: CGSize, color: CGColor) {
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
    }

    static func drawGradient(
        into context: CGContext,
        size: CGSize,
        startColor: CGColor,
        endColor: CGColor,
        angle: Double
    ) {
        let colors: [CGColor] = [startColor, endColor]
        let locations: [CGFloat] = [0.0, 1.0]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations) else { return }

        let radians = angle * .pi / 180.0
        let cx = size.width / 2
        let cy = size.height / 2
        let halfDiag = CGFloat(sqrt(size.width * size.width + size.height * size.height)) / 2
        let startX = cx - cos(radians) * halfDiag
        let startY = cy - sin(radians) * halfDiag
        let endX = cx + cos(radians) * halfDiag
        let endY = cy + sin(radians) * halfDiag

        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: startX, y: startY),
            end: CGPoint(x: endX, y: endY),
            options: []
        )
    }

    static func drawImageBackground(
        into context: CGContext,
        size: CGSize,
        backgroundColor: CGColor,
        backgroundImage: CGImage?,
        opacity: Double
    ) {
        context.setFillColor(backgroundColor)
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))

        guard let bgImage = backgroundImage else { return }
        context.saveGState()
        context.setAlpha(opacity)
        context.draw(bgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        context.restoreGState()
    }

    static func renderBackground(
        config: BackgroundConfig,
        canvasSize: CGSize,
        backgroundImage: CGImage?,
        previewSize: CGSize
    ) -> NSImage? {
        guard let context = createContext(size: canvasSize) else { return nil }

        switch config.style {
        case .solid:
            context.setFillColor(config.backgroundColor)
            context.fill(CGRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height))

        case .gradient:
            drawGradient(
                into: context,
                size: canvasSize,
                startColor: config.gradientStartCGColor,
                endColor: config.gradientEndCGColor,
                angle: config.gradientAngle
            )

        case .image:
            drawImageBackground(
                into: context,
                size: canvasSize,
                backgroundColor: config.backgroundColor,
                backgroundImage: backgroundImage,
                opacity: config.opacity
            )
        }

        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: canvasSize)
    }

    private static func createContext(size: CGSize) -> CGContext? {
        ContextFactory.createBitmap(size: size)
    }
}
