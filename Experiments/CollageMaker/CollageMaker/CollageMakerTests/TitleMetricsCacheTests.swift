import AppKit
import Testing
@testable import CollageMaker

@MainActor
@Suite(.serialized) struct TitleMetricsCacheTests {

    private func makeViewModel() -> CollageViewModel {
        CollageViewModel(saliencyAnalyzer: MockSaliencyAnalyzer(), assembler: MockAssembler())
    }

    @Test func titleMetricsReturnsNilForEmptyString() {
        let vm = makeViewModel()
        vm.titleAttrString = NSAttributedString(string: "temp")
        vm.titleAttrString = NSAttributedString(string: "")
        #expect(vm.titleMetrics == nil)
    }

    @Test func titleMetricsCachesResultOnSecondAccess() {
        let vm = makeViewModel()
        vm.titleAttrString = NSAttributedString(string: "Hello")

        let first = vm.titleMetrics
        let second = vm.titleMetrics

        #expect(first != nil)
        #expect(first?.preparedString === second?.preparedString)
    }

    @Test func titleMetricsInvalidatedByTitleStringChange() {
        let vm = makeViewModel()
        vm.titleAttrString = NSAttributedString(string: "Hello")
        _ = vm.titleMetrics

        let firstPrepared = vm.titleMetrics?.preparedString

        vm.titleAttrString = NSAttributedString(string: "Goodbye")
        let secondPrepared = vm.titleMetrics?.preparedString

        #expect(firstPrepared != secondPrepared)
        #expect(secondPrepared?.string == "Goodbye")
    }

    @Test func titleMetricsInvalidatedByFontSizeChange() {
        let vm = makeViewModel()
        vm.titleAttrString = NSAttributedString(string: "Hello", attributes: [.font: NSFont.systemFont(ofSize: 48)])
        _ = vm.titleMetrics

        let firstPrepared = vm.titleMetrics?.preparedString

        vm.titleStyle.fontSize = 56
        let secondPrepared = vm.titleMetrics?.preparedString

        #expect(firstPrepared != secondPrepared)
    }

    @Test func titleMetricsInvalidatedByFontFamilyChange() {
        let vm = makeViewModel()
        vm.titleAttrString = NSAttributedString(string: "Hello", attributes: [.font: NSFont.systemFont(ofSize: 48)])
        _ = vm.titleMetrics

        let firstPrepared = vm.titleMetrics?.preparedString

        vm.titleStyle.fontFamily = "Helvetica"
        let secondPrepared = vm.titleMetrics?.preparedString

        #expect(firstPrepared != secondPrepared)
    }

    @Test func titleMetricsInvalidatedByWidthChange() {
        let vm = makeViewModel()
        vm.titleAttrString = NSAttributedString(string: "Hello", attributes: [.font: NSFont.systemFont(ofSize: 48)])
        _ = vm.titleMetrics

        let firstStyle = vm.titleMetrics?.style.width

        vm.titleStyle.width = 800
        let secondStyle = vm.titleMetrics?.style.width

        #expect(firstStyle != secondStyle)
        #expect(secondStyle == 800)
    }

    @Test func titleMetricsNOTInvalidatedByPositionXChange() {
        let vm = makeViewModel()
        vm.titleAttrString = NSAttributedString(string: "Hello", attributes: [.font: NSFont.systemFont(ofSize: 48)])
        _ = vm.titleMetrics

        let firstPrepared = vm.titleMetrics?.preparedString

        vm.titleStyle.positionX = 0.25
        let secondPrepared = vm.titleMetrics?.preparedString

        #expect(firstPrepared === secondPrepared)
    }

    @Test func titleMetricsNOTInvalidatedByPositionYChange() {
        let vm = makeViewModel()
        vm.titleAttrString = NSAttributedString(string: "Hello", attributes: [.font: NSFont.systemFont(ofSize: 48)])
        _ = vm.titleMetrics

        let firstPrepared = vm.titleMetrics?.preparedString

        vm.titleStyle.positionY = 0.5
        let secondPrepared = vm.titleMetrics?.preparedString

        #expect(firstPrepared === secondPrepared)
    }

    @Test func titleMetricsNOTInvalidatedByFontColorChange() {
        let vm = makeViewModel()
        vm.titleAttrString = NSAttributedString(string: "Hello", attributes: [.font: NSFont.systemFont(ofSize: 48)])
        _ = vm.titleMetrics

        let firstPrepared = vm.titleMetrics?.preparedString

        vm.titleStyle.fontColor = .red
        let secondPrepared = vm.titleMetrics?.preparedString

        #expect(firstPrepared === secondPrepared)
    }

    @Test func titleMetricsInvalidatedByAttributedStringChange() {
        let vm = makeViewModel()
        let regularFont = NSFont.systemFont(ofSize: 48)
        let boldFont = NSFont.boldSystemFont(ofSize: 48)
        vm.titleAttrString = NSAttributedString(string: "Hello", attributes: [.font: regularFont])
        _ = vm.titleMetrics

        let firstPrepared = vm.titleMetrics?.preparedString

        vm.titleAttrString = NSAttributedString(string: "Hello", attributes: [.font: boldFont])
        let secondPrepared = vm.titleMetrics?.preparedString

        #expect(firstPrepared != secondPrepared)
    }
}
