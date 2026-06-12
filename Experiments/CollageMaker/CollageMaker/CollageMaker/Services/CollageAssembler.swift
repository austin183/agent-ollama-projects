import AppKit
import CoreGraphics
import Foundation
import OSLog

private let logger = Logger(
    subsystem: "austin183.indie.CollageMaker",
    category: "Export"
)

protocol CollageRenderer {
    func assembleWithCGImages(
        config: AssemblyConfig,
        cgImages: [CGImage?],
        backgroundImage: CGImage?,
        quality: Double
    ) async -> Data?

    func assemblePreviewWithCGImages(
        config: AssemblyConfig,
        cgImages: [CGImage?],
        backgroundImage: CGImage?,
        previewSize: CGSize
    ) async -> NSImage?
}

protocol PanelRenderer {
    func renderPanel(
        crop: CropInfo,
        cgImage: CGImage,
        panelSize: CGSize,
        geometry: PanelGeometry
    ) async -> NSImage?
}

protocol BackgroundRenderer {
    func renderBackground(
        config: BackgroundConfig,
        canvasSize: CGSize,
        backgroundImage: CGImage?,
        previewSize: CGSize
    ) async -> NSImage?
}

protocol TitleRenderer {
    func renderTitle(
        titleConfig: TitleConfig,
        canvasSize: CGSize
    ) async -> NSImage?
}

protocol OverlayRenderer {
    func renderOverlay(
        overlay: OverlayConfig,
        canvasSize: CGSize
    ) async -> NSImage?
}

protocol CollageAssembly: CollageRenderer, PanelRenderer, BackgroundRenderer, TitleRenderer, OverlayRenderer {}

extension CollageAssembly {
    func assemble(
        config: AssemblyConfig,
        images: [NSImage],
        backgroundImage: NSImage?,
        quality: Double
    ) async -> Data? {
        let cgImages = images.compactMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
        let bgCGImage = backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        return await assembleWithCGImages(
            config: config,
            cgImages: cgImages,
            backgroundImage: bgCGImage,
            quality: quality
        )
    }
}

final class CollageAssembler: CollageAssembly, @unchecked Sendable {
    private let scheduler = RenderScheduler()

    func assembleWithCGImages(
        config: AssemblyConfig,
        cgImages: [CGImage?],
        backgroundImage: CGImage?,
        quality: Double
    ) async -> Data? {
        await scheduler.render {
            guard let cgImage = self.renderIntoContext(
                config: config,
                cgImages: cgImages,
                backgroundImage: backgroundImage
            ) else {
                return nil
            }
            let outRep = NSBitmapImageRep(cgImage: cgImage)
            return outRep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        }
    }

    func assemblePreviewWithCGImages(
        config: AssemblyConfig,
        cgImages: [CGImage?],
        backgroundImage: CGImage?,
        previewSize: CGSize
    ) async -> NSImage? {
        await scheduler.render {
            guard let cgImage = self.renderPreviewIntoContext(
                config: config,
                cgImages: cgImages,
                backgroundImage: backgroundImage,
                previewSize: previewSize
            ) else {
                return nil
            }
            return NSImage(cgImage: cgImage, size: previewSize)
        }
    }

    private func renderIntoContext(
        config: AssemblyConfig,
        cgImages: [CGImage?],
        backgroundImage: CGImage?
    ) -> CGImage? {
        logger.info("Rendering collage: \(config.layout.panels.count) panels, \(Int(config.canvasSize.width))x\(Int(config.canvasSize.height))")

        guard let context = createBitmapContext(
            config: config,
            backgroundImage: backgroundImage
        ) else {
            logger.error("Failed to create bitmap context: \(Int(config.canvasSize.width))x\(Int(config.canvasSize.height))")
            return nil
        }

        context.interpolationQuality = .high

        drawPanels(
            into: context,
            panels: config.layout.panels,
            cgImages: cgImages,
            crops: config.layout.crops,
            panelAssignments: config.layout.panelAssignments
        )

        if let overlay = config.overlay {
            drawOverlay(into: context, overlay: overlay, canvasSize: config.canvasSize)
        }

        if !config.title.textData.text.isEmpty {
            drawTitle(
                into: context,
                titleConfig: config.title,
                canvasWidth: config.canvasSize.width,
                canvasHeight: config.canvasSize.height
            )
        }

        return context.makeImage()
    }

    private func renderPreviewIntoContext(
        config: AssemblyConfig,
        cgImages: [CGImage?],
        backgroundImage: CGImage?,
        previewSize: CGSize
    ) -> CGImage? {
        let scale = previewSize.width / config.canvasSize.width

        guard let context = createPureCGContext(size: previewSize) else { return nil }
        context.interpolationQuality = .medium
        context.scaleBy(x: scale, y: scale)

        switch config.background.style {
        case .solid:
            context.setFillColor(config.background.backgroundColor)
            context.fill(CGRect(x: 0, y: 0, width: config.canvasSize.width, height: config.canvasSize.height))

        case .gradient:
            drawGradient(
                into: context,
                size: config.canvasSize,
                startColor: config.background.gradientStartCGColor,
                endColor: config.background.gradientEndCGColor,
                angle: config.background.gradientAngle
            )

        case .image:
            drawImageBackground(
                into: context,
                size: config.canvasSize,
                backgroundColor: config.background.backgroundColor,
                backgroundImage: backgroundImage,
                opacity: config.background.opacity
            )
        }

        drawPanels(
            into: context,
            panels: config.layout.panels,
            cgImages: cgImages,
            crops: config.layout.crops,
            panelAssignments: config.layout.panelAssignments
        )

        if let overlay = config.overlay {
            drawOverlay(into: context, overlay: overlay, canvasSize: config.canvasSize)
        }

        if !config.title.textData.text.isEmpty {
            drawTitle(
                into: context,
                titleConfig: config.title,
                canvasWidth: config.canvasSize.width,
                canvasHeight: config.canvasSize.height
            )
        }

        return context.makeImage()
    }

    private func createBitmapContext(
        config: AssemblyConfig,
        backgroundImage: CGImage?
    ) -> CGContext? {
        guard let ctx = createPureCGContext(size: config.canvasSize) else { return nil }

        switch config.background.style {
        case .solid:
            ctx.setFillColor(config.background.backgroundColor)
            ctx.fill(CGRect(x: 0, y: 0, width: config.canvasSize.width, height: config.canvasSize.height))

        case .gradient:
            drawGradient(
                into: ctx,
                size: config.canvasSize,
                startColor: config.background.gradientStartCGColor,
                endColor: config.background.gradientEndCGColor,
                angle: config.background.gradientAngle
            )

        case .image:
            drawImageBackground(
                into: ctx,
                size: config.canvasSize,
                backgroundColor: config.background.backgroundColor,
                backgroundImage: backgroundImage,
                opacity: config.background.opacity
            )
        }

        return ctx
    }

    private func createPureCGContext(size: CGSize) -> CGContext? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = Int(size.width) * 4
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )
        return context
    }

    private func drawGradient(
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

    private func drawImageBackground(
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

            if let clipPath = panel.geometry.cgPath {
                context.addPath(clipPath)
                context.clip()
            } else {
                context.clip(to: destRect)
            }

            if let cropped = cg.cropping(to: sourceRect) {
                context.draw(cropped, in: destRect)
            } else {
                // sourceRect may extend beyond image bounds (e.g., parallelogram
                // extending off-canvas). Clamp and draw the overlapping portion.
                let imageBounds = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
                let clamped = sourceRect.intersection(imageBounds)
                if clamped.width > 0, clamped.height > 0,
                   let clippedCrop = cg.cropping(to: clamped) {
                    let drawX = destRect.origin.x + (clamped.origin.x - sourceRect.origin.x) / sourceRect.width * destRect.width
                    let drawY = destRect.origin.y + (clamped.origin.y - sourceRect.origin.y) / sourceRect.height * destRect.height
                    let drawW = clamped.width / sourceRect.width * destRect.width
                    let drawH = clamped.height / sourceRect.height * destRect.height
                    context.draw(clippedCrop, in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
                }
            }

            context.restoreGState()
        }
    }

    private func drawOverlay(into context: CGContext, overlay: OverlayConfig, canvasSize: CGSize) {
        context.saveGState()
        context.setBlendMode(overlay.blendMode)
        context.setAlpha(overlay.opacity)
        context.draw(overlay.maskImage, in: CGRect(origin: .zero, size: canvasSize))
        context.restoreGState()
    }

    private func drawTitle(into context: CGContext, titleConfig: TitleConfig, canvasWidth: CGFloat, canvasHeight: CGFloat) {
        let metrics = TitleMetricsCT.prepare(
            textData: titleConfig.textData,
            style: titleConfig.style,
            fontColor: titleConfig.fontColor,
            backgroundColor: titleConfig.backgroundColor
        )
        metrics.drawTitle(into: context, canvasWidth: canvasWidth, canvasHeight: canvasHeight)
    }

    // MARK: - Per-Panel Rendering

    func renderPanel(
        crop: CropInfo,
        cgImage: CGImage,
        panelSize: CGSize,
        geometry: PanelGeometry
    ) async -> NSImage? {
        await scheduler.render {
            guard let context = self.createPureCGContext(size: panelSize) else { return nil }
            context.interpolationQuality = .medium

            let sourceRect = crop.sourceRect
            let destRect = CGRect(origin: .zero, size: panelSize)

            context.saveGState()

            if case .path(let cgPath, let boundingRect) = geometry {
                var t = CGAffineTransform(translationX: -boundingRect.origin.x, y: -boundingRect.origin.y)
                if let translated = cgPath.copy(using: &t) {
                    context.addPath(translated)
                    context.clip()
                } else {
                    context.clip(to: destRect)
                }
            } else {
                context.clip(to: destRect)
            }

            if let cropped = cgImage.cropping(to: sourceRect) {
                context.draw(cropped, in: destRect)
            } else {
                let imageBounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
                let clamped = sourceRect.intersection(imageBounds)
                if clamped.width > 0, clamped.height > 0,
                   let clippedCrop = cgImage.cropping(to: clamped) {
                    let drawX = destRect.origin.x + (clamped.origin.x - sourceRect.origin.x) / sourceRect.width * destRect.width
                    let drawY = destRect.origin.y + (clamped.origin.y - sourceRect.origin.y) / sourceRect.height * destRect.height
                    let drawW = clamped.width / sourceRect.width * destRect.width
                    let drawH = clamped.height / sourceRect.height * destRect.height
                    context.draw(clippedCrop, in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
                }
            }

            context.restoreGState()

            guard let cgImage = context.makeImage() else { return nil }
            return NSImage(cgImage: cgImage, size: panelSize)
        }
    }

    func renderBackground(
        config: BackgroundConfig,
        canvasSize: CGSize,
        backgroundImage: CGImage?,
        previewSize: CGSize
    ) async -> NSImage? {
        await scheduler.render {
            guard let context = self.createPureCGContext(size: canvasSize) else { return nil }

            switch config.style {
            case .solid:
                context.setFillColor(config.backgroundColor)
                context.fill(CGRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height))

            case .gradient:
                self.drawGradient(
                    into: context,
                    size: canvasSize,
                    startColor: config.gradientStartCGColor,
                    endColor: config.gradientEndCGColor,
                    angle: config.gradientAngle
                )

            case .image:
                self.drawImageBackground(
                    into: context,
                    size: canvasSize,
                    backgroundColor: config.backgroundColor,
                    backgroundImage: backgroundImage,
                    opacity: config.opacity
                )
            }

            guard let cgImage = context.makeImage() else { return nil }
            return NSImage(cgImage: cgImage, size: previewSize)
        }
    }

    func renderTitle(
        titleConfig: TitleConfig,
        canvasSize: CGSize
    ) async -> NSImage? {
        guard !titleConfig.textData.text.isEmpty else { return nil }

        return await scheduler.render {
            guard let context = self.createPureCGContext(size: canvasSize) else { return nil }

            self.drawTitle(
                into: context,
                titleConfig: titleConfig,
                canvasWidth: canvasSize.width,
                canvasHeight: canvasSize.height
            )

            guard let cgImage = context.makeImage() else { return nil }
            return NSImage(cgImage: cgImage, size: canvasSize)
        }
    }

    func renderOverlay(
        overlay: OverlayConfig,
        canvasSize: CGSize
    ) async -> NSImage? {
        await scheduler.render {
            guard let context = self.createPureCGContext(size: canvasSize) else { return nil }
            context.saveGState()
            context.setAlpha(overlay.opacity)
            context.draw(overlay.maskImage, in: CGRect(origin: .zero, size: canvasSize))
            context.restoreGState()
            guard let cgImage = context.makeImage() else { return nil }
            return NSImage(cgImage: cgImage, size: canvasSize)
        }
    }
}
