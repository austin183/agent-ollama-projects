import XCTest

final class CollageMakerTitleTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        let testImagesDir = Self.testImagesDirectory()
        app.launchArguments = ["COLLAGEMAKER_TEST_IMAGES_DIR=\(testImagesDir)"]
    }

    private static func testImagesDirectory() -> String {
        Bundle(for: CollageMakerTitleTests.self).url(forResource: "TestImages", withExtension: nil)!.path
    }

    private func waitForImagesLoaded(timeout: TimeInterval = 60) {
        let deadline = Date().addingTimeInterval(timeout)
        let exportButton = app.buttons["Export collage as JPEG"]

        while Date() < deadline {
            if exportButton.exists && exportButton.isEnabled {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }

        XCTFail("Timed out waiting for images to load and processing to complete")
    }

    func testAppLaunchesWithTestImages() throws {
        app.launch()
        waitForImagesLoaded()

        let imagesSection = app.outlines.element(boundBy: 0)
        XCTAssertTrue(imagesSection.exists, "Images section should exist in sidebar")
    }

    func testExportButtonEnabled() throws {
        app.launch()
        waitForImagesLoaded()

        let exportButton = app.buttons["Export collage as JPEG"]
        XCTAssertTrue(exportButton.exists, "Export button should exist")
        XCTAssertTrue(exportButton.isEnabled, "Export button should be enabled after images load")
    }

    func testTitleEditorExists() throws {
        app.launch()
        waitForImagesLoaded()

        let titleEditor = app.textViews["Title text editor"]
        XCTAssertTrue(titleEditor.exists, "Title text editor should exist in the detail panel")
    }

    func testTitleFontSizeSliderExists() throws {
        app.launch()
        waitForImagesLoaded()

        let fontSizeSlider = app.sliders["Title font size"]
        XCTAssertTrue(fontSizeSlider.exists, "Title font size slider should exist")
    }

    func testTitleColorWellExists() throws {
        app.launch()
        waitForImagesLoaded()

        let colorWell = app.buttons["Title text color"]
        XCTAssertTrue(colorWell.exists, "Title text color well should exist")
    }

    func testTitleAlignmentPickerExists() throws {
        app.launch()
        waitForImagesLoaded()

        let alignmentPicker = app.pickers["Title alignment"]
        XCTAssertTrue(alignmentPicker.exists, "Title alignment picker should exist")
    }

    func testBackgroundStylePickerExists() throws {
        app.launch()
        waitForImagesLoaded()

        let bgPicker = app.pickers["Background style"]
        XCTAssertTrue(bgPicker.exists, "Background style picker should exist")
    }

    func testLayoutMenuItemsPresent() throws {
        app.launch()
        waitForImagesLoaded()

        let uniformItem = app.menuItems["Uniform"]
        let heroItem = app.menuItems["Hero"]
        let mosaicItem = app.menuItems["Mosaic"]

        XCTAssertTrue(uniformItem.exists || heroItem.exists || mosaicItem.exists,
                      "Layout menu items should be present")
    }

    func testAddImagesButtonPresent() throws {
        app.launch()
        waitForImagesLoaded()

        let addButton = app.buttons["Add Images"]
        XCTAssertTrue(addButton.exists, "Add Images button should exist in toolbar or sidebar")
    }

    func testSidebarImageCount() throws {
        app.launch()
        waitForImagesLoaded()

        let imagesSection = app.outlines.element(boundBy: 0)
        let imageCount = imagesSection.cells.count
        XCTAssertEqual(imageCount, 5, "Sidebar should show exactly 5 test images")
    }
}
