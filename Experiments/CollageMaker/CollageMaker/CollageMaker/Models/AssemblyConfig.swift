import AppKit
import CoreGraphics

struct AssemblyConfig {
    let panels: [ImagePanel]
    let crops: [UUID: CropInfo]
    let panelAssignments: [UUID: Int]
    let titleAttrString: NSAttributedString
    let titleStyle: TitleStyle
    let backgroundColor: NSColor
    let backgroundStyle: BackgroundStyle
    let gradientStartColor: NSColor
    let gradientEndColor: NSColor
    let gradientAngle: Double
    let backgroundOpacity: Double
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
        self.panels = panels
        self.crops = crops
        self.panelAssignments = panelAssignments
        self.titleAttrString = titleAttrString
        self.titleStyle = titleStyle
        self.backgroundColor = backgroundColor
        self.backgroundStyle = backgroundStyle
        self.gradientStartColor = gradientStartColor
        self.gradientEndColor = gradientEndColor
        self.gradientAngle = gradientAngle
        self.backgroundOpacity = backgroundOpacity
        self.canvasSize = canvasSize
    }
}
