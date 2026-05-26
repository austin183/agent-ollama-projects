import AppKit
import CoreGraphics

struct LayoutConfig {
    let panels: [ImagePanel]
    let crops: [UUID: CropInfo]
    let panelAssignments: [UUID: Int]
}

struct TitleConfig {
    let attrString: NSAttributedString
    let style: TitleStyle
}

struct BackgroundConfig {
    let style: BackgroundStyle
    let color: NSColor
    let gradientStartColor: NSColor
    let gradientEndColor: NSColor
    let gradientAngle: Double
    let opacity: Double
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
        titleAttrString: NSAttributedString,
        titleStyle: TitleStyle,
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
            attrString: titleAttrString,
            style: titleStyle
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
