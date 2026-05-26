import AppKit
import CoreGraphics
import Foundation
import OSLog

private let logger = Logger(
    subsystem: "austin183.indie.CollageMaker",
    category: "Export"
)

protocol CollageAssembly {
    func assembleWithCGImages(
        config: AssemblyConfig,
        cgImages: [CGImage?],
        backgroundImage: CGImage?,
        quality: Double
    ) -> Data?

    func assemblePreviewWithCGImages(
        config: AssemblyConfig,
        cgImages: [CGImage?],
        backgroundImage: CGImage?,
        previewSize: CGSize
    ) -> NSImage?
}

extension CollageAssembly {
    func assemble(
        config: AssemblyConfig,
        images: [NSImage],
        backgroundImage: NSImage?,
        quality: Double
    ) -> Data? {
        let cgImages = images.compactMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
        let bgCGImage = backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        return assembleWithCGImages(
            config: config,
            cgImages: cgImages,
            backgroundImage: bgCGImage,
            quality: quality
        )
    }

    func assemblePreview(
        config: AssemblyConfig,
        images: [NSImage],
        backgroundImage: NSImage?,
        previewSize: CGSize
    ) -> NSImage? {
        let cgImages = images.compactMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
        let bgCGImage = backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        return assemblePreviewWithCGImages(
            config: config,
            cgImages: cgImages,
            backgroundImage: bgCGImage,
            previewSize: previewSize
        )
    }
}

final class CollageAssembler: CollageAssembly {
    func assembleWithCGImages(
        config: AssemblyConfig,
        cgImages: [CGImage?],
        backgroundImage: CGImage?,
        quality: Double
    ) -> Data? {
        logger.info("Assembling collage: \(config.layout.panels.count) panels, \(Int(config.canvasSize.width))x\(Int(config.canvasSize.height))")

        guard let (context, bitmapRep) = createBitmapContext(
            config: config,
            backgroundImage: backgroundImage
        ) else {
            logger.error("Failed to create bitmap context for collage: \(Int(config.canvasSize.width))x\(Int(config.canvasSize.height))")
            return nil
        }
        defer { NSGraphicsContext.restoreGraphicsState() }

        context.interpolationQuality = .high

        drawPanels(
            into: context,
            panels: config.layout.panels,
            cgImages: cgImages,
            crops: config.layout.crops,
            panelAssignments: config.layout.panelAssignments
        )

        if !config.title.attrString.string.isEmpty {
            drawTitle(
                into: context,
                titleAttrString: config.title.attrString,
                titleStyle: config.title.style,
                canvasWidth: config.canvasSize.width,
                canvasHeight: config.canvasSize.height
            )
        }

        guard let finalImage = bitmapRep.cgImage else {
            logger.error("Failed to extract CGImage from bitmap rep")
            return nil
        }
        let outRep = NSBitmapImageRep(cgImage: finalImage)
        return outRep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    func assemblePreviewWithCGImages(
        config: AssemblyConfig,
        cgImages: [CGImage?],
        backgroundImage: CGImage?,
        previewSize: CGSize
    ) -> NSImage? {
        guard let (context, bitmapRep) = createBitmapContext(
            config: config,
            backgroundImage: backgroundImage
        ) else {
            logger.error("Failed to create bitmap context for preview: \(Int(config.canvasSize.width))x\(Int(config.canvasSize.height))")
            return nil
        }
        defer { NSGraphicsContext.restoreGraphicsState() }

        context.interpolationQuality = .high

        drawPanels(
            into: context,
            panels: config.layout.panels,
            cgImages: cgImages,
            crops: config.layout.crops,
            panelAssignments: config.layout.panelAssignments
        )

        if !config.title.attrString.string.isEmpty {
            drawTitle(
                into: context,
                titleAttrString: config.title.attrString,
                titleStyle: config.title.style,
                canvasWidth: config.canvasSize.width,
                canvasHeight: config.canvasSize.height
            )
        }

        guard let finalImage = bitmapRep.cgImage else {
            logger.error("Failed to extract CGImage from bitmap rep for preview")
            return nil
        }
        return NSImage(cgImage: finalImage, size: previewSize)
    }

    private func createBitmapContext(
        config: AssemblyConfig,
        backgroundImage: CGImage?
    ) -> (CGContext, NSBitmapImageRep)? {
        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(config.canvasSize.width),
            pixelsHigh: Int(config.canvasSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        )
        guard let bitmapRep else { return nil }
        bitmapRep.size = config.canvasSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        let ctx = NSGraphicsContext.current!.cgContext

        switch config.background.style {
        case .solid:
            ctx.setFillColor(config.background.color.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: config.canvasSize.width, height: config.canvasSize.height))

        case .gradient:
            drawGradient(
                into: ctx,
                size: config.canvasSize,
                startColor: config.background.gradientStartColor,
                endColor: config.background.gradientEndColor,
                angle: config.background.gradientAngle
            )

        case .image:
            drawImageBackground(
                into: ctx,
                size: config.canvasSize,
                backgroundColor: config.background.color,
                backgroundImage: backgroundImage,
                opacity: config.background.opacity
            )
        }

        return (ctx, bitmapRep)
    }

    private func drawGradient(
        into context: CGContext,
        size: CGSize,
        startColor: NSColor,
        endColor: NSColor,
        angle: Double
    ) {
        let colors = [startColor.cgColor, endColor.cgColor]
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

    private func drawImageBackground(
        into context: CGContext,
        size: CGSize,
        backgroundColor: NSColor,
        backgroundImage: CGImage?,
        opacity: Double
    ) {
        context.setFillColor(backgroundColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))

        guard let bgImage = backgroundImage else { return }
        context.saveGState()
        context.setAlpha(opacity)
        context.draw(bgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        context.restoreGState()
    }

    private func drawPanels(
        into context: CGContext,
        panels: [ImagePanel],
        cgImages: [CGImage?],
        crops: [UUID: CropInfo],
        panelAssignments: [UUID: Int]
    ) {
        for panel in panels {
            let effectiveIndex = panelAssignments[panel.id] ?? panel.imageIndex
            guard
                effectiveIndex < cgImages.count,
                let cg = cgImages[effectiveIndex],
                let crop = crops[panel.id]
            else { continue }

            let sourceRect = crop.sourceRect
            let destRect = crop.destinationRect

            context.saveGState()
            context.clip(to: destRect)

            if let cropped = cg.cropping(to: sourceRect) {
                context.draw(cropped, in: destRect)
            } else {
                context.draw(cg, in: destRect)
            }

            context.restoreGState()
        }
    }

    private func drawTitle(into context: CGContext, titleAttrString: NSAttributedString, titleStyle: TitleStyle, canvasWidth: CGFloat, canvasHeight: CGFloat) {
        let metrics = TitleMetrics(
            preparedString: TitleMetrics.prepare(titleAttrString, style: titleStyle),
            style: titleStyle
        )

        let mutable = NSMutableAttributedString(attributedString: metrics.preparedString)
        mutable.addAttribute(.foregroundColor, value: titleStyle.fontColor, range: NSRange(location: 0, length: mutable.length))
        let attributedString = mutable

        let drawWidth = titleStyle.effectiveWidth(canvasWidth: canvasWidth)
        let boundingBox = metrics.boundingBox

        let anchorX = titleStyle.positionX * canvasWidth
        let anchorYcg = canvasHeight - titleStyle.positionY * canvasHeight

        let drawX = anchorX - drawWidth / 2
        let baselineY = anchorYcg - boundingBox.height

        if titleStyle.showBackground {
            context.saveGState()
            context.setFillColor(titleStyle.backgroundColor.cgColor)
            let textTop = baselineY + boundingBox.origin.y
            let bgPath = CGPath(
                roundedRect: CGRect(
                    x: drawX,
                    y: textTop - 12,
                    width: drawWidth,
                    height: boundingBox.height + 24
                ),
                cornerWidth: 8,
                cornerHeight: 8,
                transform: nil
            )
            context.addPath(bgPath)
            context.fillPath()
            context.restoreGState()
        }

        attributedString.draw(in: CGRect(x: drawX, y: baselineY, width: drawWidth, height: boundingBox.height))
    }
}
