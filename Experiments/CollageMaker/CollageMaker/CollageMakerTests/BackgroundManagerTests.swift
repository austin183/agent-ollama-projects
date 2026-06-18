import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import CollageMaker

@MainActor
@Suite(.serialized) struct BackgroundManagerTests {

    // MARK: - Helpers

    private final class TrackingPreviewUpdatable: PreviewUpdatable {
        var updateBackgroundCalls = 0
        var lastConfig: BackgroundConfig?
        var lastCanvasSize: CGSize = .zero
        var lastBackgroundImage: CGImage?
        var lastPreviewSize: CGSize = .zero
        var cancelDebouncerCalls: [String] = []
        var debouncedSaveCalls = 0

        func updateBackground(config: BackgroundConfig, canvasSize: CGSize, backgroundImage: CGImage?, previewSize: CGSize) {
            updateBackgroundCalls += 1
            lastConfig = config
            lastCanvasSize = canvasSize
            lastBackgroundImage = backgroundImage
            lastPreviewSize = previewSize
        }

        func updateTitleImage(attrString: NSAttributedString, style: TitleStyle, canvasSize: CGSize) {}
        func incrementTitleVersion() {}
        func cancelDebouncer(id: String) { cancelDebouncerCalls.append(id) }
        func debouncedSave() { debouncedSaveCalls += 1 }
    }

    // MARK: - Initial state

    @Test func initialStateHasDefaults() {
        let manager = BackgroundManager()

        #expect(manager.backgroundColor == .black)
        #expect(manager.backgroundStyle == .solid)
        #expect(manager.gradientStartColor == .black)
        #expect(manager.gradientEndColor == .darkGray)
        #expect(manager.gradientAngle == 0)
        #expect(manager.backgroundImage == nil)
        #expect(manager.backgroundImagePath == nil)
        #expect(manager.backgroundOpacity == 1.0)
    }

    // MARK: - buildConfig()

    @Test func buildConfigProducesCorrectConfig() {
        let manager = BackgroundManager()
        manager.backgroundColor = .systemBlue
        manager.backgroundStyle = .gradient
        manager.gradientStartColor = .red
        manager.gradientEndColor = .blue
        manager.gradientAngle = 45
        manager.backgroundOpacity = 0.8

        let config = manager.buildConfig()

        #expect(config.style == .gradient)
        #expect(config.color == .systemBlue)
        #expect(config.gradientStartColor == .red)
        #expect(config.gradientEndColor == .blue)
        #expect(config.gradientAngle == 45)
        #expect(config.opacity == 0.8)
    }

    @Test func buildConfigCapturesCGColorValues() {
        let manager = BackgroundManager()
        manager.backgroundColor = .systemGreen
        manager.gradientStartColor = .orange
        manager.gradientEndColor = .purple

        let config = manager.buildConfig()

        #expect(config.backgroundColor == manager.backgroundColor.cgColor)
        #expect(config.gradientStartCGColor == manager.gradientStartColor.cgColor)
        #expect(config.gradientEndCGColor == manager.gradientEndColor.cgColor)
    }

    @Test func buildConfigReflectsSolidStyle() {
        let manager = BackgroundManager()
        manager.backgroundStyle = .solid

        let config = manager.buildConfig()

        #expect(config.style == .solid)
    }

    @Test func buildConfigReflectsImageStyle() {
        let manager = BackgroundManager()
        manager.backgroundStyle = .image

        let config = manager.buildConfig()

        #expect(config.style == .image)
    }

    // MARK: - setBackgroundImage

    @Test func setBackgroundImageStoresImageAndPath() {
        let manager = BackgroundManager()
        let testImage = createTestNSImage(color: .systemYellow, size: CGSize(width: 640, height: 480))
        let testPath = "/path/to/background.jpg"

        manager.setBackgroundImage(testImage, path: testPath)

        #expect(manager.backgroundImage != nil)
        #expect(manager.backgroundImagePath == testPath)
    }

    @Test func setBackgroundImageWithNilClearsImage() {
        let manager = BackgroundManager()
        manager.backgroundImage = createTestNSImage(color: .red)
        manager.backgroundImagePath = "/old/path.jpg"

        manager.setBackgroundImage(nil, path: nil)

        #expect(manager.backgroundImage == nil)
        #expect(manager.backgroundImagePath == nil)
    }

    @Test func setBackgroundImageUpdatesExistingImage() {
        let manager = BackgroundManager()
        let firstImage = createTestNSImage(color: .red, size: CGSize(width: 100, height: 100))
        let secondImage = createTestNSImage(color: .blue, size: CGSize(width: 200, height: 200))

        manager.setBackgroundImage(firstImage, path: "/first.jpg")
        #expect(manager.backgroundImagePath == "/first.jpg")

        manager.setBackgroundImage(secondImage, path: "/second.jpg")
        #expect(manager.backgroundImagePath == "/second.jpg")
    }

    // MARK: - reset()

    @Test func resetRestoresDefaults() {
        let manager = BackgroundManager()
        manager.backgroundColor = .systemBlue
        manager.backgroundStyle = .gradient
        manager.gradientStartColor = .red
        manager.gradientEndColor = .blue
        manager.gradientAngle = 135
        manager.backgroundImage = createTestNSImage(color: .white)
        manager.backgroundImagePath = "/path/to/image.jpg"
        manager.backgroundOpacity = 0.5

        manager.reset()

        #expect(manager.backgroundColor == .black)
        #expect(manager.backgroundStyle == .solid)
        #expect(manager.gradientStartColor == .black)
        #expect(manager.gradientEndColor == .darkGray)
        #expect(manager.gradientAngle == 0)
        #expect(manager.backgroundImage == nil)
        #expect(manager.backgroundImagePath == nil)
        #expect(manager.backgroundOpacity == 1.0)
    }

    @Test func resetAllowsNewConfiguration() {
        let manager = BackgroundManager()
        manager.backgroundColor = .systemBlue
        manager.backgroundStyle = .gradient

        manager.reset()
        #expect(manager.backgroundStyle == .solid)

        manager.backgroundStyle = .image
        manager.backgroundOpacity = 0.7
        #expect(manager.backgroundStyle == .image)
        #expect(manager.backgroundOpacity == 0.7)
    }

    // MARK: - Protocol-based updateBackground

    @Test func updateBackgroundCallsUpdater() {
        let manager = BackgroundManager()
        let updater = TrackingPreviewUpdatable()

        manager.updateBackground(updater: updater)

        #expect(updater.updateBackgroundCalls == 1)
    }

    @Test func updateBackgroundPassesCurrentConfig() {
        let manager = BackgroundManager()
        manager.backgroundColor = .systemPurple
        manager.backgroundStyle = .gradient
        manager.gradientStartColor = .cyan
        manager.gradientEndColor = .magenta
        manager.gradientAngle = 90
        manager.backgroundOpacity = 0.6

        let updater = TrackingPreviewUpdatable()
        manager.updateBackground(updater: updater)

        #expect(updater.lastConfig?.style == .gradient)
        #expect(updater.lastConfig?.gradientAngle == 90)
        #expect(updater.lastConfig?.opacity == 0.6)
    }

    @Test func updateBackgroundPassesDefaultCanvasAndPreviewSize() {
        let manager = BackgroundManager()
        let updater = TrackingPreviewUpdatable()

        manager.updateBackground(updater: updater)

        #expect(updater.lastCanvasSize == SizeConstants.defaultCanvasSize)
        #expect(updater.lastPreviewSize == SizeConstants.defaultPreviewSize)
    }

    @Test func updateBackgroundPassesNilImageWhenNotSet() {
        let manager = BackgroundManager()
        let updater = TrackingPreviewUpdatable()

        manager.updateBackground(updater: updater)

        #expect(updater.lastBackgroundImage == nil)
    }

    @Test func updateBackgroundPassesCGImageWhenBackgroundImageSet() {
        let manager = BackgroundManager()
        let testImage = createTestNSImage(color: .systemYellow, size: CGSize(width: 640, height: 480))
        manager.setBackgroundImage(testImage, path: "/test.jpg")

        let updater = TrackingPreviewUpdatable()
        manager.updateBackground(updater: updater)

        #expect(updater.lastBackgroundImage != nil)
    }

    @Test func updateBackgroundUsesBuildConfigNotStaleValue() {
        let manager = BackgroundManager()
        let updater = TrackingPreviewUpdatable()

        manager.backgroundStyle = .solid
        manager.updateBackground(updater: updater)
        #expect(updater.lastConfig?.style == .solid)

        manager.backgroundStyle = .gradient
        manager.updateBackground(updater: updater)
        #expect(updater.lastConfig?.style == .gradient)
        #expect(updater.updateBackgroundCalls == 2)
    }
}
