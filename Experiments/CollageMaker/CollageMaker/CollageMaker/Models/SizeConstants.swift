import CoreGraphics

enum SizeConstants {
    static let defaultCanvasSize = CGSize(width: 1920, height: 1080)
    static let defaultPreviewSize = CGSize(width: 960, height: 540)
    static var canvasAspect: CGFloat { defaultCanvasSize.width / defaultCanvasSize.height }
    static var canvasToPreviewScale: CGFloat { defaultPreviewSize.width / defaultCanvasSize.width }
}
