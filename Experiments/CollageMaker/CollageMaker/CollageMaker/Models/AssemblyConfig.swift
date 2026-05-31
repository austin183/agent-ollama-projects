import AppKit
import CoreGraphics

struct LayoutConfig {
    let panels: [ImagePanel]
    let crops: [UUID: CropInfo]
    let panelAssignments: [UUID: Int]
}

extension LayoutConfig: @unchecked Sendable {}

struct TitleConfig {
    let attrString: NSAttributedString
    let style: TitleStyle
}

extension TitleConfig: @unchecked Sendable {}

struct BackgroundConfig {
    let style: BackgroundStyle
    let color: NSColor
    let gradientStartColor: NSColor
    let gradientEndColor: NSColor
    let gradientAngle: Double
    let opacity: Double
}

extension BackgroundConfig: @unchecked Sendable {}

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

extension AssemblyConfig: @unchecked Sendable {}
