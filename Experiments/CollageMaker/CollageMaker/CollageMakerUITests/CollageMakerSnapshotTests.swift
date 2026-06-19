import XCTest

final class CollageMakerSnapshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        let testImagesDir = Self.testImagesDirectory()
        app.launchArguments = ["COLLAGEMAKER_TEST_IMAGES_DIR=\(testImagesDir)"]
    }

    private static func testImagesDirectory() -> String {
        let testBundleURL = Bundle(for: CollageMakerSnapshotTests.self).bundleURL
        let candidates = [
            testBundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("TestImages").path,
            testBundleURL.deletingLastPathComponent().appendingPathComponent("TestImages").path,
        ]

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return testBundleURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("TestImages").path
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

    func testCanvasRendersScreenshot() throws {
        app.launch()
        waitForImagesLoaded()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Canvas Render"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCanvasRendersWithTitle() throws {
        app.launch()
        waitForImagesLoaded()

        let titleEditor = app.textViews["Title text editor"]
        if titleEditor.exists {
            titleEditor.typeText("Test Title")
            RunLoop.current.run(until: Date().addingTimeInterval(2))
        }

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Canvas With Title"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
