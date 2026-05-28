import AppKit
import Foundation
import Testing
@testable import CollageMaker

@MainActor
@Suite(.serialized) struct UserDefaultsPersistenceTests {

    private let suite: UserDefaults
    private let persistence: UserDefaultsPersistence

    init() {
        self.suite = UserDefaults(suiteName: "CollageMakerTests-\(UUID().uuidString)")!
        self.persistence = UserDefaultsPersistence(defaults: suite)
    }

    @Test func saveAndLoadLayoutStyle() {
        let viewModel = createViewModel()
        viewModel.layoutStyle = .mosaic
        persistence.save(viewModel)

        let bundle = persistence.load()
        #expect(bundle.layoutStyle == .mosaic)
    }

    @Test func saveAndLoadGutter() {
        let viewModel = createViewModel()
        viewModel.gutter = 15
        persistence.save(viewModel)

        let bundle = persistence.load()
        #expect(bundle.gutter == 15)
    }

    @Test func saveAndLoadExportQuality() {
        let viewModel = createViewModel()
        viewModel.exportQuality = 0.75
        persistence.save(viewModel)

        let bundle = persistence.load()
        #expect(bundle.exportQuality == 0.75)
    }

    @Test func saveAndLoadBackgroundStyle() {
        let viewModel = createViewModel()
        viewModel.backgroundStyle = .gradient
        persistence.save(viewModel)

        let bundle = persistence.load()
        #expect(bundle.backgroundStyle == .gradient)
    }

    @Test func saveAndLoadGradientAngle() {
        let viewModel = createViewModel()
        viewModel.gradientAngle = 135
        persistence.save(viewModel)

        let bundle = persistence.load()
        #expect(bundle.gradientAngle == 135)
    }

    @Test func saveAndLoadBackgroundOpacity() {
        let viewModel = createViewModel()
        viewModel.backgroundOpacity = 0.5
        persistence.save(viewModel)
        let saved = persistence.load()
        #expect(saved.backgroundOpacity == 0.5)
    }

    @Test func saveAndLoadTitle() {
        let viewModel = createViewModel()
        viewModel.titleAttrString = NSAttributedString(string: "Hello World")
        persistence.save(viewModel)

        let bundle = persistence.load()
        #expect(bundle.titleAttrString.string == "Hello World")
    }

    @Test func saveAndLoadCustomImageOrder() {
        let viewModel = createViewModel()
        viewModel.customImageOrder = [3, 1, 4, 0, 2]
        persistence.save(viewModel)

        let bundle = persistence.load()
        #expect(bundle.customImageOrder == [3, 1, 4, 0, 2])
    }

    @Test func loadDefaultsWhenNothingSaved() {
        let bundle = persistence.load()
        #expect(bundle.layoutStyle == .hero)
        #expect(bundle.gutter == 0)
        #expect(bundle.backgroundStyle == .solid)
        #expect(bundle.customImageOrder.isEmpty)
    }

    @Test func saveAndLoadBackgroundColor() {
        let viewModel = createViewModel()
        viewModel.backgroundColor = .systemRed
        persistence.save(viewModel)

        let bundle = persistence.load()
        #expect(bundle.backgroundColor == .systemRed)
    }

    @Test func saveAndLoadGradientColors() {
        let viewModel = createViewModel()
        viewModel.gradientStartColor = .systemBlue
        viewModel.gradientEndColor = .systemOrange
        persistence.save(viewModel)

        let bundle = persistence.load()
        #expect(bundle.gradientStartColor == .systemBlue)
        #expect(bundle.gradientEndColor == .systemOrange)
    }

    @Test func fullRoundTrip() {
        let viewModel = createViewModel()
        viewModel.layoutStyle = .uniform
        viewModel.gutter = 12
        viewModel.exportQuality = 0.85
        viewModel.backgroundStyle = .gradient
        viewModel.gradientAngle = 270
        viewModel.backgroundColor = .systemGreen
        viewModel.gradientStartColor = .purple
        viewModel.gradientEndColor = .systemMint
        viewModel.backgroundOpacity = 0.75
        viewModel.titleAttrString = NSAttributedString(string: "Full Test")
        viewModel.customImageOrder = [2, 0, 1]
        persistence.save(viewModel)

        let bundle = persistence.load()
        #expect(bundle.layoutStyle == .uniform)
        #expect(bundle.gutter == 12)
        #expect(bundle.exportQuality == 0.85)
        #expect(bundle.backgroundStyle == .gradient)
        #expect(bundle.gradientAngle == 270)
        #expect(bundle.backgroundColor == .systemGreen)
        #expect(bundle.gradientStartColor == .purple)
        #expect(bundle.gradientEndColor == .systemMint)
        #expect(bundle.backgroundOpacity == 0.75)
        #expect(bundle.titleAttrString.string == "Full Test")
        #expect(bundle.customImageOrder == [2, 0, 1])
    }

    private func createViewModel() -> CollageViewModel {
        CollageViewModel(
            saliencyAnalyzer: MockSaliencyAnalyzer(),
            assembler: MockAssembler(),
            persistence: persistence
        )
    }
}
