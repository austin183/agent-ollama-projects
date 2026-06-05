import AppKit

extension NSColor {
    var rgbaHex: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#00000000" }
        return String(format: "#%02lX%02lX%02lX%02lX",
                      Int(rgb.redComponent * 255),
                      Int(rgb.greenComponent * 255),
                      Int(rgb.blueComponent * 255),
                      Int(rgb.alphaComponent * 255))
    }

    convenience init?(rgbaHex: String) {
        guard rgbaHex.hasPrefix("#"), rgbaHex.count == 9 else { return nil }
        let hexStr = String(rgbaHex.dropFirst())
        guard let hexValue = UInt32(hexStr, radix: 16) else { return nil }
        let r = CGFloat((hexValue >> 24) & 0xFF) / 255.0
        let g = CGFloat((hexValue >> 16) & 0xFF) / 255.0
        let b = CGFloat((hexValue >> 8) & 0xFF) / 255.0
        let a = CGFloat(hexValue & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
