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
    var titleStyle: TitleStyle = .default
    var isDraggingTitle: Bool = false

    private var cachedBounds: TitleBoundsCache?
    private var cachedLayoutKey: TitleStyle.LayoutKey?
    private var cachedString: NSAttributedString?
    private var boundsVersion: Int = 0

    var title: String { titleAttrString.string }

    var canvasFrame: CGRect? {
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

    func updateImage(viewModel: CollageViewModel) {
        viewModel.titleImageVersion += 1
        viewModel.previewManager.updateTitleImage(
            titleAttrString: titleAttrString,
            titleStyle: titleStyle,
            canvasSize: SizeConstants.defaultCanvasSize
        )
    }

    func updateImageLive(viewModel: CollageViewModel) {
        updateImage(viewModel: viewModel)
    }

    func finishDrag(viewModel: CollageViewModel) {
        viewModel.debouncer.cancel(id: "titleImage")
        updateImage(viewModel: viewModel)
        viewModel.debouncedSave()
    }

    func reset() {
        titleAttrString = NSAttributedString(string: "")
        titleStyle = .default
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
