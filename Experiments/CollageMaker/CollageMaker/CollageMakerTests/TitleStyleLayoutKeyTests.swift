import AppKit
import Testing
@testable import CollageMaker

@Suite(.serialized) struct TitleStyleLayoutKeyTests {

    @Test func layoutKeyEqualWhenOnlyPositionXDiffers() {
        var style1 = TitleStyle.default
        var style2 = TitleStyle.default
        style2.positionX = 0.25

        #expect(style1.layoutKey == style2.layoutKey)
    }

    @Test func layoutKeyEqualWhenOnlyPositionYDiffers() {
        var style1 = TitleStyle.default
        var style2 = TitleStyle.default
        style2.positionY = 0.5

        #expect(style1.layoutKey == style2.layoutKey)
    }

    @Test func layoutKeyEqualWhenOnlyFontColorDiffers() {
        var style1 = TitleStyle.default
        var style2 = TitleStyle.default
        style2.fontColor = .red

        #expect(style1.layoutKey == style2.layoutKey)
    }

    @Test func layoutKeyEqualWhenOnlyBackgroundColorDiffers() {
        var style1 = TitleStyle.default
        var style2 = TitleStyle.default
        style2.backgroundColor = .red

        #expect(style1.layoutKey == style2.layoutKey)
    }

    @Test func layoutKeyEqualWhenOnlyShowBackgroundDiffers() {
        var style1 = TitleStyle.default
        var style2 = TitleStyle.default
        style2.showBackground = false

        #expect(style1.layoutKey == style2.layoutKey)
    }

    @Test func layoutKeyDiffersWhenFontSizeChanges() {
        var style1 = TitleStyle.default
        var style2 = TitleStyle.default
        style2.fontSize = 56

        #expect(style1.layoutKey != style2.layoutKey)
    }

    @Test func layoutKeyDiffersWhenFontFamilyChanges() {
        var style1 = TitleStyle.default
        var style2 = TitleStyle.default
        style2.fontFamily = "Helvetica"

        #expect(style1.layoutKey != style2.layoutKey)
    }

    @Test func layoutKeyDiffersWhenWidthChanges() {
        var style1 = TitleStyle.default
        var style2 = TitleStyle.default
        style2.width = 800

        #expect(style1.layoutKey != style2.layoutKey)
    }

    @Test func layoutKeyDiffersWhenAlignmentChanges() {
        var style1 = TitleStyle.default
        var style2 = TitleStyle.default
        style2.alignment = .left

        #expect(style1.layoutKey != style2.layoutKey)
    }
}
