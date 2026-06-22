import AppKit
import CoreGraphics
import Foundation

/// Minimal surface managers need to update title/background previews
/// and trigger saves, without importing CollageViewModel.
protocol PreviewUpdatable {
    func updateTitleImage(attrString: NSAttributedString, style: TitleStyle, canvasSize: CGSize)
    func incrementTitleVersion()
    func updateBackground(config: BackgroundConfig, canvasSize: CGSize, backgroundImage: CGImage?, previewSize: CGSize)
    func cancelDebouncer(id: String)
}
