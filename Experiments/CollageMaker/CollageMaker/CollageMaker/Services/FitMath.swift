import CoreGraphics

/// Aspect-ratio-aware fit calculations.
/// Computes the largest fitted size within a container and the centering offset.
enum FitMath {

    /// Fits `sourceSize` inside `containerSize` while preserving aspect ratio.
    /// Returns the fitted size and the offset to center it within the container.
    static func fit(_ sourceSize: CGSize, into containerSize: CGSize) -> (fittedSize: CGSize, offset: CGPoint) {
        let sourceAspect = sourceSize.width / sourceSize.height
        let containerAspect = containerSize.width / containerSize.height

        let fittedSize: CGSize
        if sourceAspect >= containerAspect {
            fittedSize = CGSize(width: containerSize.width, height: containerSize.width / sourceAspect)
        } else {
            fittedSize = CGSize(width: containerSize.height * sourceAspect, height: containerSize.height)
        }

        let offset = CGPoint(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2
        )

        return (fittedSize, offset)
    }

    /// Convenience: computes the centered source rectangle of `panelSize` aspect ratio
    /// that should be cropped from an image of `imageSize`.
    static func sourceRect(imageSize: CGSize, panelSize: CGSize) -> CGRect {
        let imageAspect = imageSize.width / imageSize.height
        let panelAspect = panelSize.width / panelSize.height

        let sourceW: CGFloat
        let sourceH: CGFloat

        if imageAspect > panelAspect {
            sourceH = imageSize.height
            sourceW = sourceH * panelAspect
        } else {
            sourceW = imageSize.width
            sourceH = sourceW / panelAspect
        }

        let originX = (imageSize.width - sourceW) / 2
        let originY = (imageSize.height - sourceH) / 2

        return CGRect(x: originX, y: originY, width: sourceW, height: sourceH)
    }
}
