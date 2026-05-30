import CoreGraphics
import Testing
@testable import CollageMaker

@Suite struct FitMathTests {

    // MARK: - fit()

    @Test func fitSquareIntoSquare() {
        let (fitted, offset) = FitMath.fit(CGSize(width: 400, height: 400), into: CGSize(width: 400, height: 400))
        #expect(fitted.width == 400)
        #expect(fitted.height == 400)
        #expect(offset.x == 0)
        #expect(offset.y == 0)
    }

    @Test func fitWideImageIntoSquareContainer() {
        // 2:1 image into 1:1 container — width fills, height shrinks
        let (fitted, offset) = FitMath.fit(CGSize(width: 800, height: 400), into: CGSize(width: 400, height: 400))
        #expect(fitted.width == 400)
        #expect(fitted.height == 200)
        #expect(offset.x == 0)
        #expect(offset.y == 100)
    }

    @Test func fitTallImageIntoSquareContainer() {
        // 1:2 image into 1:1 container — height fills, width shrinks
        let (fitted, offset) = FitMath.fit(CGSize(width: 400, height: 800), into: CGSize(width: 400, height: 400))
        #expect(fitted.width == 200)
        #expect(fitted.height == 400)
        #expect(offset.x == 100)
        #expect(offset.y == 0)
    }

    @Test func fitSquareIntoWideContainer() {
        // 1:1 image into 2:1 container — height fills, width shrinks, centered
        let (fitted, offset) = FitMath.fit(CGSize(width: 400, height: 400), into: CGSize(width: 800, height: 400))
        #expect(fitted.width == 400)
        #expect(fitted.height == 400)
        #expect(offset.x == 200)
        #expect(offset.y == 0)
    }

    @Test func fitSquareIntoTallContainer() {
        // 1:1 image into 1:2 container — width fills, height shrinks, centered
        let (fitted, offset) = FitMath.fit(CGSize(width: 400, height: 400), into: CGSize(width: 400, height: 800))
        #expect(fitted.width == 400)
        #expect(fitted.height == 400)
        #expect(offset.x == 0)
        #expect(offset.y == 200)
    }

    @Test func fitPreservesAspectRatio() {
        let source = CGSize(width: 1920, height: 1080)
        let container = CGSize(width: 500, height: 500)
        let (fitted, _) = FitMath.fit(source, into: container)
        let sourceAspect = source.width / source.height
        let fittedAspect = fitted.width / fitted.height
        #expect(fittedAspect == sourceAspect, "Aspect ratio should be preserved")
    }

    @Test func fitNeverExceedsContainer() {
        let source = CGSize(width: 4000, height: 3000)
        let container = CGSize(width: 800, height: 600)
        let (fitted, _) = FitMath.fit(source, into: container)
        #expect(fitted.width <= container.width)
        #expect(fitted.height <= container.height)
    }

    @Test func fitZeroSourceHeight() {
        let (fitted, offset) = FitMath.fit(CGSize(width: 100, height: 0), into: CGSize(width: 400, height: 400))
        #expect(fitted == .zero)
        #expect(offset == .zero)
    }

    @Test func fitZeroContainerHeight() {
        let (fitted, offset) = FitMath.fit(CGSize(width: 400, height: 400), into: CGSize(width: 400, height: 0))
        #expect(fitted == .zero)
        #expect(offset == .zero)
    }

    @Test func fitZeroBothHeights() {
        let (fitted, offset) = FitMath.fit(CGSize(width: 100, height: 0), into: CGSize(width: 100, height: 0))
        #expect(fitted == .zero)
        #expect(offset == .zero)
    }

    // MARK: - sourceRect()

    @Test func sourceRectSquareImageSquarePanel() {
        let rect = FitMath.sourceRect(imageSize: CGSize(width: 1000, height: 1000), panelSize: CGSize(width: 400, height: 400))
        #expect(rect.origin.x == 0)
        #expect(rect.origin.y == 0)
        #expect(rect.width == 1000)
        #expect(rect.height == 1000)
    }

    @Test func sourceRectWideImageTallPanel() {
        // 2:1 image, 1:2 panel — imageAspect > panelAspect → use full image height, compute width
        let rect = FitMath.sourceRect(imageSize: CGSize(width: 2000, height: 1000), panelSize: CGSize(width: 400, height: 800))
        #expect(rect.height == 1000)
        #expect(rect.width == 500)  // 1000 * 0.5
        #expect(rect.origin.x == 750)  // (2000 - 500) / 2
        #expect(rect.origin.y == 0)  // (1000 - 1000) / 2
    }

    @Test func sourceRectTallImageWidePanel() {
        // 1:2 image, 2:1 panel — use full width, crop height to match panel aspect
        let rect = FitMath.sourceRect(imageSize: CGSize(width: 1000, height: 2000), panelSize: CGSize(width: 800, height: 400))
        #expect(rect.width == 1000)
        #expect(rect.height == 500)
        #expect(rect.origin.x == 0)
        #expect(rect.origin.y == 750) // centered: (2000 - 500) / 2
    }

    @Test func sourceRectPreservesPanelAspect() {
        let image = CGSize(width: 3000, height: 2000)
        let panel = CGSize(width: 16, height: 9)
        let rect = FitMath.sourceRect(imageSize: image, panelSize: panel)
        let imageAspect = image.width / image.height
        let rectAspect = rect.width / rect.height
        let panelAspect = panel.width / panel.height
        #expect(rectAspect == panelAspect, "Source rect should match panel aspect ratio")
        #expect(rect.maxX <= image.width)
        #expect(rect.maxY <= image.height)
    }

    @Test func sourceRectCentered() {
        let image = CGSize(width: 1000, height: 800)
        let panel = CGSize(width: 400, height: 400)
        let rect = FitMath.sourceRect(imageSize: image, panelSize: panel)
        // imageAspect = 1.25 > panelAspect = 1.0 → sourceH = 800, sourceW = 800 * 1.0 = 800
        #expect(rect.width == 800)
        #expect(rect.height == 800)
        #expect(rect.origin.x == 100)  // (1000 - 800) / 2
        #expect(rect.origin.y == 0)    // (800 - 800) / 2
    }

    @Test func sourceRectZeroImageHeight() {
        let rect = FitMath.sourceRect(imageSize: CGSize(width: 100, height: 0), panelSize: CGSize(width: 400, height: 400))
        #expect(rect == .zero)
    }

    @Test func sourceRectZeroPanelHeight() {
        let rect = FitMath.sourceRect(imageSize: CGSize(width: 1000, height: 800), panelSize: CGSize(width: 400, height: 0))
        #expect(rect == .zero)
    }

    @Test func sourceRectZeroBothHeights() {
        let rect = FitMath.sourceRect(imageSize: .zero, panelSize: .zero)
        #expect(rect == .zero)
    }
}
