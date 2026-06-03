import AppKit
import CoreGraphics
import CoreText
import Foundation

// MARK: - TitleTextData

/// A single font run extracted from an NSAttributedString on the main actor.
struct TitleTextRun: Sendable {
    let range: NSRange
    let fontFamily: String?
    let symbolicTraitsRawValue: UInt32
}

/// Sendable representation of attributed text for crossing concurrency boundaries.
struct TitleTextData: Sendable {
    let text: String
    let runs: [TitleTextRun]

    /// Extract text and font run information from an NSAttributedString.
    /// Must be called on the main actor.
    static func extract(from attrString: NSAttributedString) -> TitleTextData {
        var runs: [TitleTextRun] = []
        attrString.enumerateAttribute(.font, in: NSRange(location: 0, length: attrString.length), options: []) { value, range, _ in
            if let font = value as? NSFont {
                let rawValue = UInt32(font.fontDescriptor.symbolicTraits.rawValue)
                runs.append(TitleTextRun(
                    range: range,
                    fontFamily: font.familyName,
                    symbolicTraitsRawValue: rawValue
                ))
            } else {
                runs.append(TitleTextRun(
                    range: range,
                    fontFamily: nil,
                    symbolicTraitsRawValue: 0
                ))
            }
        }
        return TitleTextData(text: attrString.string, runs: runs)
    }
}

// MARK: - TitleBoundsCT

/// Lightweight CoreText-based title bounds calculator.
/// Produces identical bounding boxes to TitleMetricsCT for pixel-perfect outline alignment.
struct TitleBoundsCT {
    private let framesetter: CTFramesetter
    private let stringLength: CFIndex
    private let fontDescent: CGFloat
    private let styleWidth: CGFloat

    static func compute(
        textData: TitleTextData,
        style: TitleStyle
    ) -> TitleBoundsCT {
        let paragraphStyle = makeParagraphStyle(alignment: style.alignment)

        let cfAttrString = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0)!
        CFAttributedStringReplaceString(cfAttrString, CFRange(), textData.text as CFString)
        let stringLength = CFAttributedStringGetLength(cfAttrString)

        CFAttributedStringSetAttribute(
            cfAttrString,
            CFRange(location: 0, length: stringLength),
            kCTParagraphStyleAttributeName,
            paragraphStyle
        )

        var primaryFont: CTFont?
        for run in textData.runs {
            let traits = CTFontSymbolicTraits(rawValue: run.symbolicTraitsRawValue)
            let font = makeCTFont(
                existingFamily: run.fontFamily,
                existingTraits: traits,
                baseFamily: style.fontFamily,
                targetSize: style.fontSize
            )
            CFAttributedStringSetAttribute(
                cfAttrString,
                CFRange(location: run.range.location, length: run.range.length),
                kCTFontAttributeName,
                font
            )
            if primaryFont == nil {
                primaryFont = font
            }
        }

        let framesetter = CTFramesetterCreateWithAttributedString(cfAttrString)
        let pFont = primaryFont ?? CTFontCreateUIFontForLanguage(.system, style.fontSize, nil)!

        return TitleBoundsCT(
            framesetter: framesetter,
            stringLength: stringLength,
            fontDescent: CTFontGetDescent(pFont),
            styleWidth: style.width
        )
    }

    func boundingBox(canvasWidth: CGFloat) -> CGRect {
        let drawWidth = effectiveWidth(canvasWidth: canvasWidth)
        var fitRange = CFRange()
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: stringLength),
            nil,
            CGSize(width: drawWidth, height: CGFloat.greatestFiniteMagnitude),
            &fitRange
        )
        return CGRect(x: 0, y: -fontDescent, width: size.width, height: size.height)
    }

    func minNaturalWidth(canvasWidth: CGFloat) -> CGFloat {
        var fitRange = CFRange()
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: stringLength),
            nil,
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            &fitRange
        )
        return size.width
    }

    private func effectiveWidth(canvasWidth: CGFloat) -> CGFloat {
        if styleWidth > 0 {
            return styleWidth
        }
        return canvasWidth - 40
    }
}

// MARK: - TitleMetricsCT

/// Pure CoreText title metrics and renderer. Thread-safe, no AppKit mutation.
struct TitleMetricsCT {
    private let framesetter: CTFramesetter
    private let stringLength: CFIndex
    let style: TitleStyle
    private let fontColor: CGColor
    private let backgroundColor: CGColor
    private let fontAscent: CGFloat
    private let fontDescent: CGFloat

    static func prepare(
        textData: TitleTextData,
        style: TitleStyle,
        fontColor: CGColor,
        backgroundColor: CGColor
    ) -> TitleMetricsCT {
        let paragraphStyle = makeParagraphStyle(alignment: style.alignment)

        // Create mutable CFAttributedString using CoreFoundation C API
        let cfAttrString = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0)!
        CFAttributedStringReplaceString(cfAttrString, CFRange(), textData.text as CFString)
        let stringLength = CFAttributedStringGetLength(cfAttrString)

        // Apply paragraph style to entire string
        CFAttributedStringSetAttribute(
            cfAttrString,
            CFRange(location: 0, length: stringLength),
            kCTParagraphStyleAttributeName,
            paragraphStyle
        )

        // Apply font per run
        for run in textData.runs {
            let traits = CTFontSymbolicTraits(rawValue: run.symbolicTraitsRawValue)
            let font = makeCTFont(
                existingFamily: run.fontFamily,
                existingTraits: traits,
                baseFamily: style.fontFamily,
                targetSize: style.fontSize
            )
            CFAttributedStringSetAttribute(
                cfAttrString,
                CFRange(location: run.range.location, length: run.range.length),
                kCTFontAttributeName,
                font
            )
        }

        // Apply foreground color to entire string
        CFAttributedStringSetAttribute(
            cfAttrString,
            CFRange(location: 0, length: stringLength),
            kCTForegroundColorAttributeName,
            fontColor
        )

        let framesetter = CTFramesetterCreateWithAttributedString(cfAttrString)

        // Get metrics from primary font
        let primaryTraits = textData.runs.first.map {
            CTFontSymbolicTraits(rawValue: $0.symbolicTraitsRawValue)
        } ?? []
        let primaryFont = makeCTFont(
            existingFamily: textData.runs.first?.fontFamily,
            existingTraits: primaryTraits,
            baseFamily: style.fontFamily,
            targetSize: style.fontSize
        )

        return TitleMetricsCT(
            framesetter: framesetter,
            stringLength: stringLength,
            style: style,
            fontColor: fontColor,
            backgroundColor: backgroundColor,
            fontAscent: CTFontGetAscent(primaryFont),
            fontDescent: CTFontGetDescent(primaryFont)
        )
    }

    /// Bounding box relative to baseline origin, matching TitleMetrics.boundingBox semantics.
    func boundingBox(canvasWidth: CGFloat) -> CGRect {
        let drawWidth = style.effectiveWidth(canvasWidth: canvasWidth)
        var fitRange = CFRange()
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: stringLength),
            nil,
            CGSize(width: drawWidth, height: CGFloat.greatestFiniteMagnitude),
            &fitRange
        )
        return CGRect(x: 0, y: -fontDescent, width: size.width, height: size.height)
    }

    /// Minimum natural width of the text (no wrapping).
    func minNaturalWidth(canvasWidth: CGFloat) -> CGFloat {
        var fitRange = CFRange()
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: stringLength),
            nil,
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            &fitRange
        )
        return size.width
    }

    /// Draws the title into the given CGContext using CoreText.
    func drawTitle(into context: CGContext, canvasWidth: CGFloat, canvasHeight: CGFloat) {
        let drawWidth = style.effectiveWidth(canvasWidth: canvasWidth)
        let bbox = boundingBox(canvasWidth: canvasWidth)

        let anchorX = style.positionX * canvasWidth
        let anchorYcg = canvasHeight - style.positionY * canvasHeight

        let drawX = anchorX - drawWidth / 2
        let baselineY = anchorYcg - bbox.height

        if style.showBackground {
            context.saveGState()
            context.setFillColor(backgroundColor)
            let textTop = baselineY + bbox.origin.y
            let bgRect = CGRect(
                x: drawX,
                y: textTop - 12,
                width: drawWidth,
                height: bbox.height + 24
            )
            let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
            context.addPath(bgPath)
            context.fillPath()
            context.restoreGState()
        }

        let frameRect = CGRect(
            x: drawX,
            y: baselineY - fontDescent,
            width: drawWidth,
            height: bbox.height + fontDescent
        )
        let path = CGPath(rect: frameRect, transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: stringLength),
            path,
            nil
        )
        CTFrameDraw(frame, context)
    }
}

// MARK: - Private Helpers

private func makeParagraphStyle(alignment: NSTextAlignment) -> CTParagraphStyle {
    let ctAlignment: CTTextAlignment = {
        switch alignment {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        case .justified: return .justified
        case .natural: return .natural
        @unknown default: return .center
        }
    }()

    var settings = [CTParagraphStyleSetting]()
    var value = ctAlignment
    settings.append(CTParagraphStyleSetting(
        spec: CTParagraphStyleSpecifier.alignment,
        valueSize: MemoryLayout<CTTextAlignment>.size,
        value: withUnsafePointer(to: &value) { UnsafeRawPointer($0) }
    ))

    return CTParagraphStyleCreate(settings, settings.count)
}

private func makeCTFont(
    existingFamily: String?,
    existingTraits: CTFontSymbolicTraits,
    baseFamily: String,
    targetSize: CGFloat
) -> CTFont {
    let baseFont: CTFont

    if baseFamily.isEmpty {
        let systemFont = CTFontCreateUIFontForLanguage(.system, targetSize, nil)!
        let baseTraits = CTFontGetSymbolicTraits(systemFont)
        let mergedTraits = baseTraits.union(.traitBold)
        baseFont = CTFontCreateCopyWithSymbolicTraits(systemFont, 0, nil, mergedTraits, .traitBold)!
    } else {
        baseFont = CTFontCreateWithName(baseFamily as CFString, targetSize, nil)
    }

    if !existingTraits.isEmpty {
        let baseTraits = CTFontGetSymbolicTraits(baseFont)
        let mergedTraits = baseTraits.union(existingTraits)
        return CTFontCreateCopyWithSymbolicTraits(baseFont, 0, nil, mergedTraits, existingTraits)!
    }

    return baseFont
}
