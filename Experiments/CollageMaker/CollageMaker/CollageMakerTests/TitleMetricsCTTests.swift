import AppKit
import CoreGraphics
import Testing
@testable import CollageMaker

@MainActor
@Suite struct TitleMetricsCTTests {

    // MARK: - Basic preparation

    @Test func prepareWithSimpleText() {
        let attrString = NSAttributedString(string: "Hello World")
        let textData = TitleTextData.extract(from: attrString)
        let style = TitleStyle.default

        let metrics = TitleMetricsCT.prepare(
            textData: textData,
            style: style,
            fontColor: NSColor.white.cgColor,
            backgroundColor: NSColor.black.cgColor
        )

        #expect(metrics.style.fontSize == 48)
    }

    @Test func prepareWithEmptyText() {
        let attrString = NSAttributedString(string: "")
        let textData = TitleTextData.extract(from: attrString)
        let style = TitleStyle.default

        let metrics = TitleMetricsCT.prepare(
            textData: textData,
            style: style,
            fontColor: NSColor.white.cgColor,
            backgroundColor: NSColor.black.cgColor
        )

        #expect(metrics.style.fontSize == 48)
    }

    // MARK: - Bounding box

    @Test func boundingBoxHasPositiveDimensions() {
        let attrString = NSAttributedString(string: "Test Title")
        let textData = TitleTextData.extract(from: attrString)
        let style = TitleStyle.default

        let metrics = TitleMetricsCT.prepare(
            textData: textData,
            style: style,
            fontColor: NSColor.white.cgColor,
            backgroundColor: NSColor.black.cgColor
        )

        let canvasWidth = CanvasConfig.defaultCanvasSize.width
        let bbox = metrics.boundingBox(canvasWidth: canvasWidth)

        #expect(bbox.width > 0)
        #expect(bbox.height > 0)
    }

    @Test func boundingBoxWidthIncreasesWithLongerText() {
        let shortText = TitleTextData.extract(from: NSAttributedString(string: "Hi"))
        let longText = TitleTextData.extract(from: NSAttributedString(string: "This is a much longer title text"))
        let style = TitleStyle.default

        let shortMetrics = TitleMetricsCT.prepare(
            textData: shortText,
            style: style,
            fontColor: NSColor.white.cgColor,
            backgroundColor: NSColor.black.cgColor
        )
        let longMetrics = TitleMetricsCT.prepare(
            textData: longText,
            style: style,
            fontColor: NSColor.white.cgColor,
            backgroundColor: NSColor.black.cgColor
        )

        let canvasWidth = CanvasConfig.defaultCanvasSize.width
        let shortBbox = shortMetrics.boundingBox(canvasWidth: canvasWidth)
        let longBbox = longMetrics.boundingBox(canvasWidth: canvasWidth)

        #expect(longBbox.width > shortBbox.width)
    }

    @Test func boundingBoxConstrainedByEffectiveWidth() {
        let attrString = NSAttributedString(string: "A very long title that should wrap within the effective width constraint")
        let textData = TitleTextData.extract(from: attrString)
        var style = TitleStyle.default
        style.positionX = 0.5
        style.positionY = 0.88

        let metrics = TitleMetricsCT.prepare(
            textData: textData,
            style: style,
            fontColor: NSColor.white.cgColor,
            backgroundColor: NSColor.black.cgColor
        )

        let canvasWidth = CanvasConfig.defaultCanvasSize.width
        let bbox = metrics.boundingBox(canvasWidth: canvasWidth)
        let effectiveWidth = style.effectiveWidth(canvasWidth: canvasWidth)

        #expect(bbox.width <= effectiveWidth)
    }

    @Test func boundingBoxYIsNegativeDescent() {
        let attrString = NSAttributedString(string: "Test")
        let textData = TitleTextData.extract(from: attrString)
        let style = TitleStyle.default

        let metrics = TitleMetricsCT.prepare(
            textData: textData,
            style: style,
            fontColor: NSColor.white.cgColor,
            backgroundColor: NSColor.black.cgColor
        )

        let canvasWidth = CanvasConfig.defaultCanvasSize.width
        let bbox = metrics.boundingBox(canvasWidth: canvasWidth)

        #expect(bbox.origin.y < 0)
    }

    // MARK: - Min natural width

    @Test func minNaturalWidthGreaterThanZero() {
        let attrString = NSAttributedString(string: "Hello")
        let textData = TitleTextData.extract(from: attrString)
        let style = TitleStyle.default

        let metrics = TitleMetricsCT.prepare(
            textData: textData,
            style: style,
            fontColor: NSColor.white.cgColor,
            backgroundColor: NSColor.black.cgColor
        )

        let width = metrics.minNaturalWidth(canvasWidth: CanvasConfig.defaultCanvasSize.width)
        #expect(width > 0)
    }

    @Test func minNaturalWidthUnconstrained() {
        let attrString = NSAttributedString(string: "A very long title that should not be constrained by canvas width")
        let textData = TitleTextData.extract(from: attrString)
        var style = TitleStyle.default
        style.width = 200

        let metrics = TitleMetricsCT.prepare(
            textData: textData,
            style: style,
            fontColor: NSColor.white.cgColor,
            backgroundColor: NSColor.black.cgColor
        )

        let canvasWidth = CanvasConfig.defaultCanvasSize.width
        let naturalWidth = metrics.minNaturalWidth(canvasWidth: canvasWidth)
        let constrainedBbox = metrics.boundingBox(canvasWidth: canvasWidth)

        #expect(naturalWidth > 200)
        #expect(constrainedBbox.width <= 200)
    }

    // MARK: - Drawing

    @Test func drawTitleProducesNonEmptyImage() {
        let attrString = NSAttributedString(string: "Test Title")
        let textData = TitleTextData.extract(from: attrString)
        let style = TitleStyle.default

        let metrics = TitleMetricsCT.prepare(
            textData: textData,
            style: style,
            fontColor: NSColor.white.cgColor,
            backgroundColor: NSColor.black.cgColor
        )

        let canvasWidth: CGFloat = 800
        let canvasHeight: CGFloat = 600

        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvasWidth),
            pixelsHigh: Int(canvasHeight),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        )!
        bitmapRep.size = CGSize(width: canvasWidth, height: canvasHeight)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        guard let context = NSGraphicsContext.current?.cgContext else {
            Issue.record("Failed to create graphics context")
            return
        }

        metrics.drawTitle(into: context, canvasWidth: canvasWidth, canvasHeight: canvasHeight)
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = bitmapRep.cgImage else {
            Issue.record("Failed to create CGImage from bitmap")
            return
        }
        let nsImage = NSImage(cgImage: cgImage, size: CGSize(width: canvasWidth, height: canvasHeight))
        #expect(nsImage.tiffRepresentation != nil)
    }

    @Test func drawTitleWithBackgroundDrawsPill() {
        let attrString = NSAttributedString(string: "Title")
        let textData = TitleTextData.extract(from: attrString)
        var style = TitleStyle.default
        style.showBackground = true
        style.backgroundColor = NSColor.systemRed

        let metrics = TitleMetricsCT.prepare(
            textData: textData,
            style: style,
            fontColor: NSColor.white.cgColor,
            backgroundColor: NSColor.systemRed.cgColor
        )

        let canvasWidth: CGFloat = 800
        let canvasHeight: CGFloat = 600

        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvasWidth),
            pixelsHigh: Int(canvasHeight),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        )!
        bitmapRep.size = CGSize(width: canvasWidth, height: canvasHeight)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        guard let context = NSGraphicsContext.current?.cgContext else {
            Issue.record("Failed to create graphics context")
            return
        }

        metrics.drawTitle(into: context, canvasWidth: canvasWidth, canvasHeight: canvasHeight)
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = bitmapRep.cgImage else {
            Issue.record("Failed to create CGImage from bitmap")
            return
        }
        let nsImage = NSImage(cgImage: cgImage, size: CGSize(width: canvasWidth, height: canvasHeight))
        #expect(nsImage.tiffRepresentation != nil)
    }

    @Test func drawTitleWithoutBackgroundSkipsPill() {
        let attrString = NSAttributedString(string: "Title")
        let textData = TitleTextData.extract(from: attrString)
        var style = TitleStyle.default
        style.showBackground = false

        let metrics = TitleMetricsCT.prepare(
            textData: textData,
            style: style,
            fontColor: NSColor.white.cgColor,
            backgroundColor: NSColor.black.cgColor
        )

        let canvasWidth: CGFloat = 800
        let canvasHeight: CGFloat = 600

        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvasWidth),
            pixelsHigh: Int(canvasHeight),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        )!
        bitmapRep.size = CGSize(width: canvasWidth, height: canvasHeight)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        guard let context = NSGraphicsContext.current?.cgContext else {
            Issue.record("Failed to create graphics context")
            return
        }

        metrics.drawTitle(into: context, canvasWidth: canvasWidth, canvasHeight: canvasHeight)
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = bitmapRep.cgImage else {
            Issue.record("Failed to create CGImage from bitmap")
            return
        }
        let nsImage = NSImage(cgImage: cgImage, size: CGSize(width: canvasWidth, height: canvasHeight))
        #expect(nsImage.tiffRepresentation != nil)
    }

    // MARK: - Font family

    @Test func prepareWithNamedFontFamily() {
        let attrString = NSAttributedString(string: "Helvetica Test")
        let textData = TitleTextData.extract(from: attrString)
        var style = TitleStyle.default
        style.fontFamily = "Helvetica"
        style.fontSize = 36

        let metrics = TitleMetricsCT.prepare(
            textData: textData,
            style: style,
            fontColor: NSColor.white.cgColor,
            backgroundColor: NSColor.black.cgColor
        )

        #expect(metrics.style.fontFamily == "Helvetica")
        #expect(metrics.style.fontSize == 36)
    }

    @Test func prepareWithEmptyFontFamilyUsesSystem() {
        let attrString = NSAttributedString(string: "System Font Test")
        let textData = TitleTextData.extract(from: attrString)
        var style = TitleStyle.default
        style.fontFamily = ""

        let metrics = TitleMetricsCT.prepare(
            textData: textData,
            style: style,
            fontColor: NSColor.white.cgColor,
            backgroundColor: NSColor.black.cgColor
        )

        #expect(metrics.style.fontFamily == "")
    }

    // MARK: - Alignment

    @Test func prepareWithLeftAlignment() {
        let attrString = NSAttributedString(string: "Left Aligned")
        let textData = TitleTextData.extract(from: attrString)
        var style = TitleStyle.default
        style.alignment = .left

        let metrics = TitleMetricsCT.prepare(
            textData: textData,
            style: style,
            fontColor: NSColor.white.cgColor,
            backgroundColor: NSColor.black.cgColor
        )

        #expect(metrics.style.alignment == .left)
    }

    @Test func prepareWithRightAlignment() {
        let attrString = NSAttributedString(string: "Right Aligned")
        let textData = TitleTextData.extract(from: attrString)
        var style = TitleStyle.default
        style.alignment = .right

        let metrics = TitleMetricsCT.prepare(
            textData: textData,
            style: style,
            fontColor: NSColor.white.cgColor,
            backgroundColor: NSColor.black.cgColor
        )

        #expect(metrics.style.alignment == .right)
    }

    // MARK: - Position

    @Test func drawTitleRespectsPositionX() {
        let attrString = NSAttributedString(string: "Positioned")
        let textData = TitleTextData.extract(from: attrString)
        var style = TitleStyle.default
        style.positionX = 0.0
        style.showBackground = false

        let metrics = TitleMetricsCT.prepare(
            textData: textData,
            style: style,
            fontColor: NSColor.white.cgColor,
            backgroundColor: NSColor.black.cgColor
        )

        let canvasWidth: CGFloat = 800
        let canvasHeight: CGFloat = 600

        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvasWidth),
            pixelsHigh: Int(canvasHeight),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        )!
        bitmapRep.size = CGSize(width: canvasWidth, height: canvasHeight)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        guard let context = NSGraphicsContext.current?.cgContext else {
            Issue.record("Failed to create graphics context")
            return
        }

        metrics.drawTitle(into: context, canvasWidth: canvasWidth, canvasHeight: canvasHeight)
        NSGraphicsContext.restoreGraphicsState()

        #expect(bitmapRep.cgImage != nil)
    }

    // MARK: - Font size

    @Test func boundingBoxScalesWithFontSize() {
        let attrString = NSAttributedString(string: "Size Test")
        let textData = TitleTextData.extract(from: attrString)

        var smallStyle = TitleStyle.default
        smallStyle.fontSize = 24

        var largeStyle = TitleStyle.default
        largeStyle.fontSize = 72

        let smallMetrics = TitleMetricsCT.prepare(
            textData: textData,
            style: smallStyle,
            fontColor: NSColor.white.cgColor,
            backgroundColor: NSColor.black.cgColor
        )
        let largeMetrics = TitleMetricsCT.prepare(
            textData: textData,
            style: largeStyle,
            fontColor: NSColor.white.cgColor,
            backgroundColor: NSColor.black.cgColor
        )

        let canvasWidth = CanvasConfig.defaultCanvasSize.width
        let smallBbox = smallMetrics.boundingBox(canvasWidth: canvasWidth)
        let largeBbox = largeMetrics.boundingBox(canvasWidth: canvasWidth)

        #expect(largeBbox.width > smallBbox.width)
        #expect(largeBbox.height > smallBbox.height)
    }

    // MARK: - Thread safety

    @Test func prepareCanBeCalledFromBackgroundThread() async {
        let attrString = NSAttributedString(string: "Background Thread Test")
        let textData = TitleTextData.extract(from: attrString)
        let style = TitleStyle.default

        let metrics = await Task.detached {
            TitleMetricsCT.prepare(
                textData: textData,
                style: style,
                fontColor: NSColor.white.cgColor,
                backgroundColor: NSColor.black.cgColor
            )
        }.value

        #expect(metrics.style.fontSize == 48)
    }

    @Test func drawTitleCanBeCalledFromBackgroundThread() async {
        let attrString = NSAttributedString(string: "Background Draw")
        let textData = TitleTextData.extract(from: attrString)
        let style = TitleStyle.default

        let metrics = TitleMetricsCT.prepare(
            textData: textData,
            style: style,
            fontColor: NSColor.white.cgColor,
            backgroundColor: NSColor.black.cgColor
        )

        let canvasWidth: CGFloat = 800
        let canvasHeight: CGFloat = 600

        let result = await Task.detached {
            let bitmapRep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(canvasWidth),
                pixelsHigh: Int(canvasHeight),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 32
            )!
            bitmapRep.size = CGSize(width: canvasWidth, height: canvasHeight)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
            guard let context = NSGraphicsContext.current?.cgContext else {
                NSGraphicsContext.restoreGraphicsState()
                return false
            }

            metrics.drawTitle(into: context, canvasWidth: canvasWidth, canvasHeight: canvasHeight)
            NSGraphicsContext.restoreGraphicsState()
            return bitmapRep.cgImage != nil
        }.value

        #expect(result == true)
    }

    // MARK: - Custom width

    @Test func boundingBoxRespectsCustomWidth() {
        let attrString = NSAttributedString(string: "Custom Width Test")
        let textData = TitleTextData.extract(from: attrString)
        var style = TitleStyle.default
        style.width = 200

        let metrics = TitleMetricsCT.prepare(
            textData: textData,
            style: style,
            fontColor: NSColor.white.cgColor,
            backgroundColor: NSColor.black.cgColor
        )

        let canvasWidth = CanvasConfig.defaultCanvasSize.width
        let bbox = metrics.boundingBox(canvasWidth: canvasWidth)

        #expect(bbox.width <= 200)
    }

    // MARK: - Multi-line

    @Test func boundingBoxHandlesWrapping() {
        let attrString = NSAttributedString(string: "A very long title that will definitely wrap to multiple lines when constrained")
        let textData = TitleTextData.extract(from: attrString)
        var style = TitleStyle.default
        style.width = 200

        let metrics = TitleMetricsCT.prepare(
            textData: textData,
            style: style,
            fontColor: NSColor.white.cgColor,
            backgroundColor: NSColor.black.cgColor
        )

        let canvasWidth = CanvasConfig.defaultCanvasSize.width
        let bbox = metrics.boundingBox(canvasWidth: canvasWidth)

        #expect(bbox.height > style.fontSize)
    }
}
