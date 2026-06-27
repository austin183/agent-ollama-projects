import AppKit
import Foundation

@MainActor
@Observable
final class BackgroundManager {
    var backgroundColor: NSColor = .black
    var backgroundStyle: BackgroundStyle = .solid
    var gradientStartColor: NSColor = .black
    var gradientEndColor: NSColor = .darkGray
    var gradientAngle: Double = 0
    var backgroundImage: NSImage? {
        didSet {
            if backgroundImage !== oldValue {
                _cachedBackgroundCGImage = nil
            }
        }
    }
    var backgroundImagePath: String?
    var backgroundOpacity: Double = 1.0
    private var _cachedBackgroundCGImage: CGImage?

    func getCachedBackgroundCGImage() -> CGImage? {
        guard let image = backgroundImage else { return nil }
        if let cached = _cachedBackgroundCGImage { return cached }
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        _cachedBackgroundCGImage = cg
        return cg
    }

    func buildConfig() -> BackgroundConfig {
        BackgroundConfig(
            style: backgroundStyle,
            color: backgroundColor,
            gradientStartColor: gradientStartColor,
            gradientEndColor: gradientEndColor,
            gradientAngle: gradientAngle,
            opacity: backgroundOpacity
        )
    }

    func setBackgroundImage(_ image: NSImage?, path: String?) -> (NSImage?, String?) {
        let oldImage = backgroundImage
        let oldPath = backgroundImagePath
        backgroundImagePath = path
        backgroundImage = image
        return (oldImage, oldPath)
    }

    func updateBackground(updater: PreviewUpdatable) {
        let bgConfig = buildConfig()
        let backgroundImageCG = getCachedBackgroundCGImage()

        updater.updateBackground(
            config: bgConfig,
            canvasSize: SizeConstants.defaultCanvasSize,
            backgroundImage: backgroundImageCG,
            previewSize: SizeConstants.defaultPreviewSize
        )
    }

    func reset() {
        backgroundColor = .black
        backgroundStyle = .solid
        gradientStartColor = .black
        gradientEndColor = .darkGray
        gradientAngle = 0
        backgroundImage = nil
        backgroundImagePath = nil
        backgroundOpacity = 1.0
    }

    // MARK: - Deferred Undo State

    var interacting: Bool = false
    var preInteractionGradientAngle: Double = 0
    var preInteractionGradientStartColor: NSColor = .black
    var preInteractionGradientEndColor: NSColor = .darkGray
    var preInteractionBackgroundColor: NSColor = .black
    var preInteractionBackgroundOpacity: Double = 1.0

    var deferredUndoTask: Task<Void, Never>?

    func beginInteraction() -> Bool {
        if interacting { return false }
        interacting = true
        preInteractionGradientAngle = gradientAngle
        preInteractionGradientStartColor = gradientStartColor
        preInteractionGradientEndColor = gradientEndColor
        preInteractionBackgroundColor = backgroundColor
        preInteractionBackgroundOpacity = backgroundOpacity
        return true
    }

    func endInteraction() {
        interacting = false
    }

    func registerDeferredUndo(actionName: String, finalize: @escaping () -> Void) {
        deferredUndoTask?.cancel()
        deferredUndoTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: FrameTempo.backgroundUndoDebounce)
            guard !Task.isCancelled else { return }
            finalize()
            self.endInteraction()
            self.deferredUndoTask = nil
        }
    }

    func cancelDeferredUndo() {
        deferredUndoTask?.cancel()
        deferredUndoTask = nil
        if interacting { endInteraction() }
    }
}
