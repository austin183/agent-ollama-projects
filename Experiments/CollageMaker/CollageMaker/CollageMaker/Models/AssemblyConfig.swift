import AppKit
import CoreGraphics

struct LayoutConfig {
    let panels: [ImagePanel]
    let crops: [UUID: CropInfo]
    let panelAssignments: [UUID: Int]
}

extension LayoutConfig: @unchecked Sendable {}

struct TitleConfig {
    let textData: TitleTextData
    let style: TitleStyle
    let fontColor: CGColor
    let backgroundColor: CGColor
}

extension TitleConfig: @unchecked Sendable {}

// Safety: NSColor is MainActor-only, but BackgroundConfig is only ever
// constructed on the main actor. CGColor values are captured at init time
// on the main actor and then accessed safely on background threads.
struct BackgroundConfig: @unchecked Sendable {
    let style: BackgroundStyle
    let color: NSColor
    let gradientStartColor: NSColor
    let gradientEndColor: NSColor
    let gradientAngle: Double
    let opacity: Double
    let backgroundColor: CGColor
    let gradientStartCGColor: CGColor
    let gradientEndCGColor: CGColor

    init(
        style: BackgroundStyle,
        color: NSColor,
        gradientStartColor: NSColor,
        gradientEndColor: NSColor,
        gradientAngle: Double,
        opacity: Double
    ) {
        self.style = style
        self.color = color
        self.gradientStartColor = gradientStartColor
        self.gradientEndColor = gradientEndColor
        self.gradientAngle = gradientAngle
        self.opacity = opacity
        self.backgroundColor = color.cgColor
        self.gradientStartCGColor = gradientStartColor.cgColor
        self.gradientEndCGColor = gradientEndColor.cgColor
    }
}

struct AssemblyConfig {
    let layout: LayoutConfig
    let title: TitleConfig
    let background: BackgroundConfig
    let canvasSize: CGSize

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
        canvasSize: CGSize
    ) {
        self.layout = LayoutConfig(
            panels: panels,
            crops: crops,
            panelAssignments: panelAssignments
        )
        self.title = TitleConfig(
            textData: titleTextData,
            style: titleStyle,
            fontColor: titleFontColor,
            backgroundColor: titleBackgroundColor
        )
        self.background = BackgroundConfig(
            style: backgroundStyle,
            color: backgroundColor,
            gradientStartColor: gradientStartColor,
            gradientEndColor: gradientEndColor,
            gradientAngle: gradientAngle,
            opacity: backgroundOpacity
        )
        self.canvasSize = canvasSize
    }
}

extension AssemblyConfig {
    init(
        layout: LayoutConfig,
        title: TitleConfig,
        background: BackgroundConfig,
        canvasSize: CGSize
    ) {
        self.layout = layout
        self.title = title
        self.background = background
        self.canvasSize = canvasSize
    }
}

extension AssemblyConfig: @unchecked Sendable {}
