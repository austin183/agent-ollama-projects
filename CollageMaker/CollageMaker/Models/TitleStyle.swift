import AppKit
import Foundation

struct TitleStyle: Codable, Equatable {
    var fontFamily: String
    var fontSize: CGFloat
    var fontColor: NSColor
    var backgroundColor: NSColor
    var alignment: NSTextAlignment
    var showBackground: Bool
    var positionX: CGFloat
    var positionY: CGFloat
    var width: CGFloat

    static let `default` = TitleStyle(
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

    func effectiveWidth(canvasWidth: CGFloat) -> CGFloat {
        if width > 0 {
            return width
        }
        return canvasWidth - 40
    }
}

extension TitleStyle {
    static func fromUserDefaults() -> TitleStyle {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.titleStyle) else {
            return .default
        }
        return (try? JSONDecoder().decode(TitleStyle.self, from: data)) ?? .default
    }

    func saveToUserDefaults() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: UserDefaultsKeys.titleStyle)
        }
    }
}

private enum UserDefaultsKeys {
    static let titleStyle = "titleStyle"
}

extension TitleStyle {
    private enum CodingKeys: String, CodingKey {
        case fontFamily, fontSize, fontColorData, backgroundColorData, alignment, showBackground, positionX, positionY, width
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fontFamily, forKey: .fontFamily)
        try container.encode(fontSize, forKey: .fontSize)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: fontColor, requiringSecureCoding: false) {
            try container.encode(data, forKey: .fontColorData)
        }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: backgroundColor, requiringSecureCoding: false) {
            try container.encode(data, forKey: .backgroundColorData)
        }
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
        positionX = try container.decodeIfPresent(CGFloat.self, forKey: .positionX) ?? TitleStyle.default.positionX
        positionY = try container.decodeIfPresent(CGFloat.self, forKey: .positionY) ?? TitleStyle.default.positionY
        width = try container.decodeIfPresent(CGFloat.self, forKey: .width) ?? TitleStyle.default.width

        if let data = try? container.decode(Data.self, forKey: .fontColorData),
            let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            fontColor = color
        } else {
            fontColor = TitleStyle.default.fontColor
        }

        if let data = try? container.decode(Data.self, forKey: .backgroundColorData),
            let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            backgroundColor = color
        } else {
            backgroundColor = TitleStyle.default.backgroundColor
        }
    }
}
