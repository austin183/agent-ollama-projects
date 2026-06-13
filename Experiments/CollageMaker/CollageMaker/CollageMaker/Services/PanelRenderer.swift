import AppKit
import CoreGraphics
import Foundation

/// Pure struct — CoreGraphics panel rendering logic.
struct PanelRenderer {
    static func drawPanels(
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
            let destRect = crop.destination.boundingRect

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
                drawClampedCrop(context: context, cgImage: cg, sourceRect: sourceRect, destRect: destRect)
            }

            context.restoreGState()
        }
    }

    static func drawClampedCrop(context: CGContext, cgImage: CGImage, sourceRect: CGRect, destRect: CGRect) {
        let imageBounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let clamped = sourceRect.intersection(imageBounds)
        guard clamped.width > 0, clamped.height > 0,
              let clippedCrop = cgImage.cropping(to: clamped) else { return }
        let drawX = destRect.origin.x + (clamped.origin.x - sourceRect.origin.x) / sourceRect.width * destRect.width
        let drawY = destRect.origin.y + (clamped.origin.y - sourceRect.origin.y) / sourceRect.height * destRect.height
        let drawW = clamped.width / sourceRect.width * destRect.width
        let drawH = clamped.height / sourceRect.height * destRect.height
        context.draw(clippedCrop, in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
    }

    static func renderPanel(
        crop: CropInfo,
        cgImage: CGImage,
        panelSize: CGSize,
        geometry: PanelGeometry
    ) -> NSImage? {
        guard let context = createContext(size: panelSize) else { return nil }
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
            drawClampedCrop(context: context, cgImage: cgImage, sourceRect: sourceRect, destRect: destRect)
        }

        context.restoreGState()

        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: panelSize)
    }

    private static func createContext(size: CGSize) -> CGContext? {
        ContextFactory.createBitmap(size: size)
    }
}
