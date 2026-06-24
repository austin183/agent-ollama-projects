import AppKit
import CoreGraphics
import Foundation
import OSLog

private let logger = Logger(
    subsystem: "austin183.indie.CollageMaker",
    category: "Export"
)

// MARK: - Protocols

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

protocol PanelRendering {
    func renderPanel(
        crop: CropInfo,
        cgImage: CGImage,
        panelSize: CGSize,
        geometry: PanelGeometry
    ) async -> NSImage?
}

protocol BackgroundRendering {
    func renderBackground(
        config: BackgroundConfig,
        canvasSize: CGSize,
        backgroundImage: CGImage?,
        previewSize: CGSize
    ) async -> NSImage?
}

protocol TitleRendering {
    func renderTitle(
        titleConfig: TitleConfig,
        canvasSize: CGSize
    ) async -> NSImage?
}

protocol OverlayRendering {
    func renderOverlay(
        overlay: OverlayConfig,
        canvasSize: CGSize
    ) async -> NSImage?
}

protocol CollageAssembly: CollageRenderer, PanelRendering, BackgroundRendering, TitleRendering, OverlayRendering {}

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

// MARK: - Assembler

final class CollageAssembler: CollageAssembly, @unchecked Sendable {
    // SAFETY: All mutable state (scheduler, RenderScheduler's internal NSLock-protected
    // queues) is accessed exclusively on the rendering dispatch queue. The scheduler
    // serializes all render calls, preventing concurrent mutation. No AppKit types
    // escape the MainActor-isolated callers.
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

        PanelRenderer.drawPanels(
            into: context,
            panels: config.layout.panels,
            cgImages: cgImages,
            crops: config.layout.crops,
            panelAssignments: config.layout.panelAssignments
        )

        if let overlay = config.overlay {
            OverlayRenderer.drawOverlay(into: context, overlay: overlay, canvasSize: config.canvasSize)
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

        guard let context = ContextFactory.createBitmap(size: previewSize) else { return nil }
        context.interpolationQuality = .medium
        context.scaleBy(x: scale, y: scale)

        drawBackground(into: context, config: config.background, size: config.canvasSize, backgroundImage: backgroundImage)

        PanelRenderer.drawPanels(
            into: context,
            panels: config.layout.panels,
            cgImages: cgImages,
            crops: config.layout.crops,
            panelAssignments: config.layout.panelAssignments
        )

        if let overlay = config.overlay {
            OverlayRenderer.drawOverlay(into: context, overlay: overlay, canvasSize: config.canvasSize)
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
        guard let ctx = ContextFactory.createBitmap(size: config.canvasSize) else { return nil }
        drawBackground(into: ctx, config: config.background, size: config.canvasSize, backgroundImage: backgroundImage)
        return ctx
    }

    private func drawBackground(into context: CGContext, config: BackgroundConfig, size: CGSize, backgroundImage: CGImage?) {
        switch config.style {
        case .solid:
            BackgroundRenderer.drawSolidBackground(into: context, size: size, color: config.color.cgColor)

        case .gradient:
            BackgroundRenderer.drawGradient(
                into: context,
                size: size,
                startColor: config.gradientStartColor.cgColor,
                endColor: config.gradientEndColor.cgColor,
                angle: config.gradientAngle
            )

        case .image:
            BackgroundRenderer.drawImageBackground(
                into: context,
                size: size,
                backgroundColor: config.color.cgColor,
                backgroundImage: backgroundImage,
                opacity: config.opacity
            )
        }
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
            PanelRenderer.renderPanel(
                crop: crop,
                cgImage: cgImage,
                panelSize: panelSize,
                geometry: geometry
            )
        }
    }

    func renderBackground(
        config: BackgroundConfig,
        canvasSize: CGSize,
        backgroundImage: CGImage?,
        previewSize: CGSize
    ) async -> NSImage? {
        await scheduler.render {
            BackgroundRenderer.renderBackground(
                config: config,
                canvasSize: canvasSize,
                backgroundImage: backgroundImage,
                previewSize: previewSize
            )
        }
    }

    func renderTitle(
        titleConfig: TitleConfig,
        canvasSize: CGSize
    ) async -> NSImage? {
        guard !titleConfig.textData.text.isEmpty else { return nil }

        return await scheduler.render {
            guard let context = ContextFactory.createBitmap(size: canvasSize) else { return nil }

            let metrics = TitleMetricsCT.prepare(
                textData: titleConfig.textData,
                style: titleConfig.style,
                fontColor: titleConfig.fontColor,
                backgroundColor: titleConfig.backgroundColor
            )
            metrics.drawTitle(into: context, canvasWidth: canvasSize.width, canvasHeight: canvasSize.height)

            guard let cgImage = context.makeImage() else { return nil }
            return NSImage(cgImage: cgImage, size: canvasSize)
        }
    }

    func renderOverlay(
        overlay: OverlayConfig,
        canvasSize: CGSize
    ) async -> NSImage? {
        await scheduler.render {
            OverlayRenderer.renderOverlay(overlay: overlay, canvasSize: canvasSize)
        }
    }
}
