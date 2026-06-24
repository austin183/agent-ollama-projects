import AppKit
import Foundation
import OSLog

private let logger = Logger(
    subsystem: "austin183.indie.CollageMaker",
    category: "TitleManager"
)

@MainActor
@Observable
final class TitleManager {
    var titleAttrString: NSAttributedString = NSAttributedString(string: "")
    var titleStyle: TitleStyle = .defaultStyle()
    var isDraggingTitle: Bool = false

    private var cachedBounds: TitleBoundsCache?
    private var cachedLayoutKey: TitleStyle.LayoutKey?
    private var cachedString: NSAttributedString?
    private var boundsVersion: Int = 0

    var title: String { titleAttrString.string }

    /// Test-only override for canvasFrame. When set, interaction methods use this
    /// instead of computing from title bounds.
    internal var testCanvasFrameOverride: CGRect? = nil

    /// Test-only override for minWidth. When set, resize methods use this value.
    internal var testMinWidthOverride: CGFloat? = nil

    var canvasFrame: CGRect? {
        if let override = testCanvasFrameOverride {
            return override
        }
        let _ = boundsVersion
        guard let cache = ensureTitleBounds() else { return nil }
        let bounds = cache.bounds
        let canvasSize = SizeConstants.defaultCanvasSize
        let boundingBox = bounds.boundingBox(canvasWidth: canvasSize.width)
        let drawWidth = titleStyle.effectiveWidth(canvasWidth: canvasSize.width)
        let anchorX = titleStyle.positionX * canvasSize.width
        let drawX = anchorX - drawWidth / 2
        let anchorYcg = canvasSize.height - titleStyle.positionY * canvasSize.height
        let baselineY = anchorYcg - boundingBox.height
        let textTop = baselineY + boundingBox.origin.y
        return CGRect(x: drawX, y: textTop - 12, width: drawWidth, height: boundingBox.height + 24)
    }

    var minWidth: CGFloat {
        if let override = testMinWidthOverride {
            return override
        }
        let _ = boundsVersion
        guard let cache = ensureTitleBounds() else { return 0 }
        let bounds = cache.bounds
        let canvasSize = SizeConstants.defaultCanvasSize
        return bounds.minNaturalWidth(canvasWidth: canvasSize.width)
    }

    private func ensureTitleBounds() -> TitleBoundsCache? {
        guard !titleAttrString.string.isEmpty else {
            cachedBounds = nil
            cachedString = nil
            cachedLayoutKey = nil
            return nil
        }
        let currentKey = titleStyle.layoutKey
        if let cachedBounds = cachedBounds,
           let cachedStr = cachedString, cachedStr.isEqual(titleAttrString),
           cachedLayoutKey == currentKey {
            return cachedBounds
        }
        cachedString = titleAttrString
        let textData = TitleTextData.extract(from: titleAttrString)
        let bounds = TitleBoundsCT.compute(textData: textData, style: titleStyle)
        cachedBounds = TitleBoundsCache(bounds)
        cachedLayoutKey = currentKey
        boundsVersion += 1
        return cachedBounds
    }

    func updateImage(updater: PreviewUpdatable) {
        updater.incrementTitleVersion()
        updater.updateTitleImage(
            attrString: titleAttrString,
            style: titleStyle,
            canvasSize: SizeConstants.defaultCanvasSize
        )
    }

    func finishDrag(updater: PreviewUpdatable) {
        updater.cancelDebouncer(id: "titleImage")
        updateImage(updater: updater)
    }

    // MARK: - Title Interaction Methods

    static let resizeHandleWidth: CGFloat = 8
    static let handleThreshold: CGFloat = 10  // resizeHandleWidth + 2

    /// Hit-tests a screen location against the title's canvas frame.
    func hitTestTitle(location: CGPoint, previewSize: CGSize) -> TitleHitResult {
        guard let canvas = canvasFrame else { return .none }
        let tf = CoordinateConverter.canvasToPreviewFrame(canvas, in: previewSize, canvasSize: SizeConstants.defaultCanvasSize)
        let threshold = Self.handleThreshold

        if tf.minX - threshold <= location.x,
           location.x <= tf.minX + threshold,
           tf.minY <= location.y, location.y <= tf.maxY {
            return .resize(.left)
        }
        if tf.maxX - threshold <= location.x,
           location.x <= tf.maxX + threshold,
           tf.minY <= location.y, location.y <= tf.maxY {
            return .resize(.right)
        }
        if tf.contains(location) {
            return .drag
        }
        return .none
    }

    /// Computes the offset from the title center to the drag start point (in canvas coordinates).
    func computeTitleDragOffset(startLocation: CGPoint, previewSize: CGSize) -> CGPoint {
        guard let canvas = canvasFrame else { return .zero }
        let canvasSize = SizeConstants.defaultCanvasSize
        let startCanvas = CoordinateConverter.screenToCanvasPoint(startLocation, in: previewSize, canvasSize: canvasSize)
        let titleCenterCanvasY = canvas.minY + canvas.height / 2
        return CGPoint(
            x: canvas.midX - startCanvas.x,
            y: titleCenterCanvasY - startCanvas.y
        )
    }

    /// Computes the normalized title position from a screen location and drag offset.
    func computeTitleDragPosition(
        screenLocation: CGPoint,
        offset: CGPoint,
        previewSize: CGSize
    ) -> (positionX: CGFloat, positionY: CGFloat) {
        let canvasSize = SizeConstants.defaultCanvasSize
        let canvasPoint = CoordinateConverter.screenToCanvasPoint(screenLocation, in: previewSize, canvasSize: canvasSize)
        let positionX = (canvasPoint.x + offset.x) / canvasSize.width
        let positionY = 1.0 - (canvasPoint.y + offset.y) / canvasSize.height
        return (positionX, positionY)
    }

    /// Computes the new title width and position delta for a resize drag.
    func computeTitleResize(
        screenLocation: CGPoint,
        edge: TitleResizeEdge,
        previewSize: CGSize
    ) -> (newWidth: CGFloat, positionDelta: CGFloat) {
        guard let canvas = canvasFrame else { return (0, 0) }
        let canvasSize = SizeConstants.defaultCanvasSize
        let canvasPoint = CoordinateConverter.screenToCanvasPoint(screenLocation, in: previewSize, canvasSize: canvasSize)
        let canvasX = canvasPoint.x
        let minW = minWidth

        switch edge {
        case .right:
            let newWidth = max(minW, canvasX - canvas.minX)
            return (newWidth, 0)
        case .left:
            let newWidth = max(minW, canvas.maxX - canvasX)
            let dx = (canvas.width - newWidth) / 2
            return (newWidth, dx / canvasSize.width)
        case .none:
            return (0, 0)
        }
    }

    func reset() {
        titleAttrString = NSAttributedString(string: "")
        titleStyle = .defaultStyle()
        isDraggingTitle = false
        cachedBounds = nil
        cachedLayoutKey = nil
        cachedString = nil
        boundsVersion += 1
    }
}

final class TitleBoundsCache {
    let bounds: TitleBoundsCT
    init(_ bounds: TitleBoundsCT) { self.bounds = bounds }
}
