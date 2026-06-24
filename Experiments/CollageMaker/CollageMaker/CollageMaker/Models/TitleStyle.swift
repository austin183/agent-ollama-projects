import AppKit
import CoreGraphics
import Foundation

enum TitleResizeEdge: Equatable {
    case none, left, right
}

enum TitleHitResult: Equatable {
    case none, drag, resize(TitleResizeEdge)
}

struct TitleStyle: Codable, Equatable, @unchecked Sendable {

    /// Value type containing only the properties that affect text layout.
    /// Position, color, and background properties are intentionally excluded.
    struct LayoutKey: Hashable {
        let fontFamily: String
        let fontSize: CGFloat
        let width: CGFloat
        let alignment: NSTextAlignment
    }

    var fontFamily: String
    var fontSize: CGFloat
    var fontColor: NSColor
    var backgroundColor: NSColor
    var alignment: NSTextAlignment
    var showBackground: Bool
    var positionX: CGFloat
    var positionY: CGFloat
    var width: CGFloat

    /// Returns a key that changes only when text layout would change.
    var layoutKey: LayoutKey {
        LayoutKey(
            fontFamily: fontFamily,
            fontSize: fontSize,
            width: width,
            alignment: alignment
        )
    }

    static func defaultStyle() -> TitleStyle {
        TitleStyle(
            fontFamily: "",
            fontSize: 48,
            fontColor: NSColor.white.withAlphaComponent(0.8),
            backgroundColor: NSColor.black.withAlphaComponent(0.4),
            alignment: .center,
            showBackground: true,
            positionX: 0.5,
            positionY: 0.88,
            width: 0
        )
    }

    func effectiveWidth(canvasWidth: CGFloat) -> CGFloat {
        if width > 0 {
            return width
        }
        return canvasWidth - 40
    }
}

extension TitleStyle {
    private enum CodingKeys: String, CodingKey {
        case fontFamily, fontSize, fontColorHex, backgroundColorHex, alignment, showBackground, positionX, positionY, width
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fontFamily, forKey: .fontFamily)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(fontColor.rgbaHex, forKey: .fontColorHex)
        try container.encode(backgroundColor.rgbaHex, forKey: .backgroundColorHex)
        try container.encode(alignment.rawValue, forKey: .alignment)
        try container.encode(showBackground, forKey: .showBackground)
        try container.encode(positionX, forKey: .positionX)
        try container.encode(positionY, forKey: .positionY)
        try container.encode(width, forKey: .width)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontFamily = try container.decode(String.self, forKey: .fontFamily)
        fontSize = try container.decode(CGFloat.self, forKey: .fontSize)
        alignment = NSTextAlignment(rawValue: try container.decode(Int.self, forKey: .alignment)) ?? .center
        showBackground = try container.decode(Bool.self, forKey: .showBackground)
        let defaults = Self.defaultStyle()
        positionX = try container.decodeIfPresent(CGFloat.self, forKey: .positionX) ?? defaults.positionX
        positionY = try container.decodeIfPresent(CGFloat.self, forKey: .positionY) ?? defaults.positionY
        width = try container.decodeIfPresent(CGFloat.self, forKey: .width) ?? defaults.width

        if let hex = try? container.decode(String.self, forKey: .fontColorHex),
           let color = NSColor(rgbaHex: hex) {
            fontColor = color
        } else {
            fontColor = defaults.fontColor
        }

        if let hex = try? container.decode(String.self, forKey: .backgroundColorHex),
           let color = NSColor(rgbaHex: hex) {
            backgroundColor = color
        } else {
            backgroundColor = defaults.backgroundColor
        }
    }
}
