import AppKit
import CoreGraphics

struct LayoutConfig {
    let panels: [ImagePanel]
    let crops: [UUID: CropInfo]
    let panelAssignments: [UUID: Int]
}

// Safety: Contains [ImagePanel] (struct with UUID + CGRect + Int),
// [CropInfo] (struct with CGRect), and [UUID: Int]. All Sendable.
extension LayoutConfig: @unchecked Sendable {}

struct TitleConfig {
    let textData: TitleTextData
    let style: TitleStyle
    let fontColor: CGColor
    let backgroundColor: CGColor
}

// Safety: Contains TitleTextData (Sendable), TitleStyle (@unchecked Sendable
// due to NSColor), and CGColor (Sendable).
extension TitleConfig: @unchecked Sendable {}

// Safety: NSColor is MainActor-only, but ColorPair is only ever
// constructed on the main actor. CGColor values are captured at init time
// on the main actor and then accessed safely on background threads.
struct ColorPair: @unchecked Sendable {
    let nsColor: NSColor
    let cgColor: CGColor

    init(_ nsColor: NSColor) {
        self.nsColor = nsColor
        self.cgColor = nsColor.cgColor
    }
}

struct BackgroundConfig: @unchecked Sendable {
    let style: BackgroundStyle
    let color: ColorPair
    let gradientStartColor: ColorPair
    let gradientEndColor: ColorPair
    let gradientAngle: Double
    let opacity: Double

    init(
        style: BackgroundStyle,
        color: NSColor,
        gradientStartColor: NSColor,
        gradientEndColor: NSColor,
        gradientAngle: Double,
        opacity: Double
    ) {
        self.style = style
        self.color = ColorPair(color)
        self.gradientStartColor = ColorPair(gradientStartColor)
        self.gradientEndColor = ColorPair(gradientEndColor)
        self.gradientAngle = gradientAngle
        self.opacity = opacity
    }
}

struct OverlayConfig: @unchecked Sendable {
    let maskImage: CGImage
    let opacity: CGFloat
    let blendMode: CGBlendMode

    init(maskImage: CGImage, opacity: CGFloat = 0.5, blendMode: CGBlendMode = .multiply) {
        self.maskImage = maskImage
        self.opacity = opacity
        self.blendMode = blendMode
    }
}

struct AssemblyConfig {
    let layout: LayoutConfig
    let title: TitleConfig
    let background: BackgroundConfig
    let canvasSize: CGSize
    let overlay: OverlayConfig?

    init(
        layout: LayoutConfig,
        title: TitleConfig,
        background: BackgroundConfig,
        canvasSize: CGSize,
        overlay: OverlayConfig? = nil
    ) {
        self.layout = layout
        self.title = title
        self.background = background
        self.canvasSize = canvasSize
        self.overlay = overlay
    }

    @available(*, deprecated, renamed: "init(layout:title:background:canvasSize:overlay:)")
    init(
        panels: [ImagePanel],
        crops: [UUID: CropInfo],
        panelAssignments: [UUID: Int],
        titleTextData: TitleTextData,
        titleStyle: TitleStyle,
        titleFontColor: CGColor,
        titleBackgroundColor: CGColor,
        backgroundColor: NSColor,
        backgroundStyle: BackgroundStyle,
        gradientStartColor: NSColor,
        gradientEndColor: NSColor,
        gradientAngle: Double,
        backgroundOpacity: Double,
        canvasSize: CGSize,
        overlay: OverlayConfig? = nil
    ) {
        self.init(
            layout: LayoutConfig(
                panels: panels,
                crops: crops,
                panelAssignments: panelAssignments
            ),
            title: TitleConfig(
                textData: titleTextData,
                style: titleStyle,
                fontColor: titleFontColor,
                backgroundColor: titleBackgroundColor
            ),
            background: BackgroundConfig(
                style: backgroundStyle,
                color: backgroundColor,
                gradientStartColor: gradientStartColor,
                gradientEndColor: gradientEndColor,
                gradientAngle: gradientAngle,
                opacity: backgroundOpacity
            ),
            canvasSize: canvasSize,
            overlay: overlay
        )
    }
}

// Safety: Contains LayoutConfig, TitleConfig, BackgroundConfig (all
// @unchecked Sendable) and CGSize (Sendable).
extension AssemblyConfig: @unchecked Sendable {}
