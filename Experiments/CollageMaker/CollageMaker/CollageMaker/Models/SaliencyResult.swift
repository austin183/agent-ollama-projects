import CoreGraphics
import Foundation

struct SaliencyResult {
    let center: CGPoint
    let radius: CGFloat
    let confidence: Float

    init(center: CGPoint, radius: CGFloat, confidence: Float) {
        self.center = center
        self.radius = radius
        self.confidence = confidence
    }

    func cropOrigin(for imageSize: CGSize, cropSize: CGSize) -> CGPoint {
        let halfW = cropSize.width / 2
        let halfH = cropSize.height / 2

        var originX = center.x - halfW
        var originY = center.y - halfH

        if imageSize.width < imageSize.height {
            originX = center.y - halfW
            originY = center.x - halfH
        }

        originX = max(0, min(originX, imageSize.width - cropSize.width))
        originY = max(0, min(originY, imageSize.height - cropSize.height))

        return CGPoint(x: originX, y: originY)
    }
}
