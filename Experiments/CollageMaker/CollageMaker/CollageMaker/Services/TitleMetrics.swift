import AppKit
import CoreGraphics

struct TitleMetrics {
    let preparedString: NSAttributedString
    let style: TitleStyle

    static func prepare(_ attrString: NSAttributedString, style: TitleStyle) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = style.alignment

        let mutable = NSMutableAttributedString(attributedString: attrString)
        mutable.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: mutable.length))

        mutable.enumerateAttribute(.font, in: NSRange(location: 0, length: mutable.length), options: []) { value, range, _ in
            let mergedFont = FontMerger.merge(value as? NSFont, baseFamily: style.fontFamily, targetSize: style.fontSize)
            mutable.addAttribute(.font, value: mergedFont, range: range)
        }

        return mutable
    }

    var boundingBox: CGRect {
        preparedString.boundingRect(
            with: CGSize(width: style.effectiveWidth(canvasWidth: CanvasConfig.defaultCanvasSize.width), height: CanvasConfig.defaultCanvasSize.height / 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
    }

    var minNaturalWidth: CGFloat {
        preparedString.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).width
    }
}
