import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import CollageMaker

@Suite(.serialized) struct TitleMetricsTests {

    // MARK: - prepare() with various font sizes

    @Test func prepareAppliesFontSize() {
        let attrString = NSAttributedString(string: "Title", attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let style = TitleStyle(
            fontFamily: "",
            fontSize: 48,
            fontColor: .white,
            backgroundColor: .black,
            alignment: .center,
            showBackground: true,
            positionX: 0.5,
            positionY: 0.88,
            width: 0
        )

        let prepared = TitleMetrics.prepare(attrString, style: style)

        prepared.enumerateAttribute(.font, in: NSRange(location: 0, length: prepared.length), options: []) { value, _, _ in
            let font = value as! NSFont
            #expect(font.pointSize == 48)
        }
    }

    @Test func prepareWithSmallFontSize() {
        let attrString = NSAttributedString(string: "Title", attributes: [.font: NSFont.systemFont(ofSize: 24)])
        var style = TitleStyle.default
        style.fontSize = 14

        let prepared = TitleMetrics.prepare(attrString, style: style)

        prepared.enumerateAttribute(.font, in: NSRange(location: 0, length: prepared.length), options: []) { value, _, _ in
            let font = value as! NSFont
            #expect(font.pointSize == 14)
        }
    }

    @Test func prepareWithLargeFontSize() {
        let attrString = NSAttributedString(string: "Title", attributes: [.font: NSFont.systemFont(ofSize: 16)])
        var style = TitleStyle.default
        style.fontSize = 96

        let prepared = TitleMetrics.prepare(attrString, style: style)

        prepared.enumerateAttribute(.font, in: NSRange(location: 0, length: prepared.length), options: []) { value, _, _ in
            let font = value as! NSFont
            #expect(font.pointSize == 96)
        }
    }

    // MARK: - prepare() with various text lengths

    @Test func prepareWithShortText() {
        let attrString = NSAttributedString(string: "Hi", attributes: [.font: NSFont.systemFont(ofSize: 24)])
        let prepared = TitleMetrics.prepare(attrString, style: .default)

        #expect(prepared.length == 2)
    }

    @Test func prepareWithLongText() {
        let longString = String(repeating: "A", count: 200)
        let attrString = NSAttributedString(string: longString, attributes: [.font: NSFont.systemFont(ofSize: 24)])
        let prepared = TitleMetrics.prepare(attrString, style: .default)

        #expect(prepared.length == 200)
    }

    @Test func prepareWithEmptyText() {
        let attrString = NSAttributedString(string: "", attributes: [.font: NSFont.systemFont(ofSize: 24)])
        let prepared = TitleMetrics.prepare(attrString, style: .default)

        #expect(prepared.length == 0)
    }

    // MARK: - prepare() preserves text content

    @Test func preparePreservesTextContent() {
        let attrString = NSAttributedString(string: "Hello World", attributes: [.font: NSFont.systemFont(ofSize: 24)])
        let prepared = TitleMetrics.prepare(attrString, style: .default)

        #expect(prepared.string == "Hello World")
    }

    // MARK: - prepare() applies alignment

    @Test func prepareAppliesLeftAlignment() {
        var style = TitleStyle.default
        style.alignment = .left
        let attrString = NSAttributedString(string: "Title", attributes: [.font: NSFont.systemFont(ofSize: 24)])
        let prepared = TitleMetrics.prepare(attrString, style: style)

        var foundAlignment: NSTextAlignment?
        prepared.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: prepared.length), options: []) { value, _, _ in
            if let ps = value as? NSParagraphStyle {
                foundAlignment = ps.alignment
            }
        }
        #expect(foundAlignment == .left)
    }

    @Test func prepareAppliesRightAlignment() {
        var style = TitleStyle.default
        style.alignment = .right
        let attrString = NSAttributedString(string: "Title", attributes: [.font: NSFont.systemFont(ofSize: 24)])
        let prepared = TitleMetrics.prepare(attrString, style: style)

        var foundAlignment: NSTextAlignment?
        prepared.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: prepared.length), options: []) { value, _, _ in
            if let ps = value as? NSParagraphStyle {
                foundAlignment = ps.alignment
            }
        }
        #expect(foundAlignment == .right)
    }

    // MARK: - bounding box

    @Test func boundingBoxHasPositiveDimensions() {
        let attrString = NSAttributedString(string: "Test Title", attributes: [.font: NSFont.systemFont(ofSize: 48)])
        let metrics = TitleMetrics(preparedString: attrString, style: .default)
        let box = metrics.boundingBox

        #expect(box.width > 0)
        #expect(box.height > 0)
    }

    @Test func boundingBoxWidthIncreasesWithTextLength() {
        let short = NSAttributedString(string: "Hi", attributes: [.font: NSFont.systemFont(ofSize: 48)])
        let long = NSAttributedString(string: "A Very Long Title Text", attributes: [.font: NSFont.systemFont(ofSize: 48)])

        let shortMetrics = TitleMetrics(preparedString: short, style: .default)
        let longMetrics = TitleMetrics(preparedString: long, style: .default)

        #expect(longMetrics.boundingBox.width > shortMetrics.boundingBox.width)
    }

    @Test func boundingBoxHeightIncreasesWithFontSize() {
        let small = NSAttributedString(string: "Title", attributes: [.font: NSFont.systemFont(ofSize: 16)])
        let large = NSAttributedString(string: "Title", attributes: [.font: NSFont.systemFont(ofSize: 72)])

        var smallStyle = TitleStyle.default
        smallStyle.fontSize = 16
        var largeStyle = TitleStyle.default
        largeStyle.fontSize = 72

        let smallMetrics = TitleMetrics(preparedString: small, style: smallStyle)
        let largeMetrics = TitleMetrics(preparedString: large, style: largeStyle)

        #expect(largeMetrics.boundingBox.height > smallMetrics.boundingBox.height)
    }

    // MARK: - effective width (canvas width interaction)

    @Test func effectiveWidthUsesCanvasWidthWhenZero() {
        var style = TitleStyle.default
        style.width = 0

        #expect(style.effectiveWidth(canvasWidth: 1920) == 1880)
    }

    @Test func effectiveWidthUsesCustomWidth() {
        var style = TitleStyle.default
        style.width = 500

        #expect(style.effectiveWidth(canvasWidth: 1920) == 500)
    }

    // MARK: - minNaturalWidth

    @Test func minNaturalWidthIsPositive() {
        let attrString = NSAttributedString(string: "Title", attributes: [.font: NSFont.systemFont(ofSize: 48)])
        let metrics = TitleMetrics(preparedString: attrString, style: .default)

        #expect(metrics.minNaturalWidth > 0)
    }

    @Test func minNaturalWidthIncreasesWithFontSize() {
        let small = NSAttributedString(string: "Title", attributes: [.font: NSFont.systemFont(ofSize: 16)])
        let large = NSAttributedString(string: "Title", attributes: [.font: NSFont.systemFont(ofSize: 72)])

        var smallStyle = TitleStyle.default
        smallStyle.fontSize = 16
        var largeStyle = TitleStyle.default
        largeStyle.fontSize = 72

        let smallMetrics = TitleMetrics(preparedString: small, style: smallStyle)
        let largeMetrics = TitleMetrics(preparedString: large, style: largeStyle)

        #expect(largeMetrics.minNaturalWidth > smallMetrics.minNaturalWidth)
    }
}
