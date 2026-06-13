import CoreGraphics
import SwiftUI

@MainActor
struct TitleDragHandler {
    let titleCanvasFrame: CGRect
    let previewSize: CGSize
    let resizeHandleWidth: CGFloat
    let handleThreshold: CGFloat

    init(titleCanvasFrame: CGRect, previewSize: CGSize) {
        self.titleCanvasFrame = titleCanvasFrame
        self.previewSize = previewSize
        self.resizeHandleWidth = 8
        self.handleThreshold = resizeHandleWidth + 2
    }

    func hitTest(at location: CGPoint) -> TitleHitResult {
        let tf = canvasToPreviewFrame(titleCanvasFrame, in: previewSize)

        if tf.minX - handleThreshold <= location.x,
           location.x <= tf.minX + handleThreshold,
           tf.minY <= location.y, location.y <= tf.maxY {
            return .resize(.left)
        }
        if tf.maxX - handleThreshold <= location.x,
           location.x <= tf.maxX + handleThreshold,
           tf.minY <= location.y, location.y <= tf.maxY {
            return .resize(.right)
        }
        if tf.contains(location) {
            return .drag
        }
        return .none
    }

    func computeDragOffset(startLocation: CGPoint) -> CGPoint {
        let startCanvas = CoordinateConverter.screenToCanvasPoint(startLocation, in: previewSize, canvasSize: SizeConstants.defaultCanvasSize)
        let titleCenterCanvasY = titleCanvasFrame.minY + titleCanvasFrame.height / 2
        return CGPoint(
            x: titleCanvasFrame.midX - startCanvas.x,
            y: titleCenterCanvasY - startCanvas.y
        )
    }

    func computeDragPosition(
        screenLocation: CGPoint,
        offset: CGPoint,
        canvasSize: CGSize
    ) -> (positionX: CGFloat, positionY: CGFloat) {
        let canvasPoint = CoordinateConverter.screenToCanvasPoint(screenLocation, in: previewSize, canvasSize: SizeConstants.defaultCanvasSize)
        let positionX = (canvasPoint.x + offset.x) / canvasSize.width
        let positionY = 1.0 - (canvasPoint.y + offset.y) / canvasSize.height
        return (positionX, positionY)
    }

    func computeResizeWidth(
        screenLocation: CGPoint,
        edge: TitleResizeEdge,
        currentFrame: CGRect,
        minWidth: CGFloat,
        canvasSize: CGSize
    ) -> (width: CGFloat, positionXDelta: CGFloat) {
        let canvasPoint = CoordinateConverter.screenToCanvasPoint(screenLocation, in: previewSize, canvasSize: SizeConstants.defaultCanvasSize)
        let canvasX = canvasPoint.x

        switch edge {
        case .right:
            let newWidth = max(minWidth, canvasX - currentFrame.minX)
            return (newWidth, 0)
        case .left:
            let newWidth = max(minWidth, currentFrame.maxX - canvasX)
            let dx = (currentFrame.width - newWidth) / 2
            return (newWidth, dx / canvasSize.width)
        case .none:
            return (0, 0)
        }
    }

    private func canvasToPreviewFrame(_ canvasRect: CGRect, in previewSize: CGSize) -> CGRect {
        CoordinateConverter.canvasToPreviewFrame(canvasRect, in: previewSize, canvasSize: SizeConstants.defaultCanvasSize)
    }
}

enum TitleHitResult: Equatable {
    case none, drag, resize(TitleResizeEdge)
}
