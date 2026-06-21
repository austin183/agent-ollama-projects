import CoreGraphics
import Testing
@testable import CollageMaker

@Suite struct SaliencyResultTests {

    @Test func cropOriginCentersOnImageCenter() {
        let result = SaliencyResult(center: CGPoint(x: 100, y: 100), radius: 30, confidence: 0.9)
        let origin = result.cropOrigin(for: CGSize(width: 200, height: 200), cropSize: CGSize(width: 100, height: 100))
        #expect(origin.x == 50)
        #expect(origin.y == 50)
    }

    @Test func cropOriginClampsToImageBounds() {
        let result = SaliencyResult(center: CGPoint(x: 10, y: 10), radius: 5, confidence: 0.8)
        let origin = result.cropOrigin(for: CGSize(width: 100, height: 100), cropSize: CGSize(width: 80, height: 80))
        #expect(origin.x >= 0)
        #expect(origin.y >= 0)
        #expect(origin.x <= 20)
        #expect(origin.y <= 20)
    }

    @Test func cropOriginClampsRightEdge() {
        let result = SaliencyResult(center: CGPoint(x: 190, y: 190), radius: 5, confidence: 0.8)
        let origin = result.cropOrigin(for: CGSize(width: 200, height: 200), cropSize: CGSize(width: 80, height: 80))
        #expect(origin.x <= 120)
        #expect(origin.y <= 120)
    }

    @Test func cropOriginPortraitNoSwap() {
        let result = SaliencyResult(center: CGPoint(x: 30, y: 100), radius: 30, confidence: 0.9)
        let origin = result.cropOrigin(for: CGSize(width: 100, height: 200), cropSize: CGSize(width: 80, height: 80))
        #expect(origin.x == 0)
        #expect(origin.y == 60)
    }

    @Test func cropOriginWithLandscapeImage() {
        let result = SaliencyResult(center: CGPoint(x: 200, y: 100), radius: 20, confidence: 0.95)
        let origin = result.cropOrigin(for: CGSize(width: 400, height: 200), cropSize: CGSize(width: 100, height: 100))
        #expect(origin.x == 150)
        #expect(origin.y == 50)
    }

    @Test func cropOriginExactCenter() {
        let result = SaliencyResult(center: CGPoint(x: 50, y: 50), radius: 10, confidence: 1.0)
        let origin = result.cropOrigin(for: CGSize(width: 100, height: 100), cropSize: CGSize(width: 50, height: 50))
        #expect(origin.x == 25)
        #expect(origin.y == 25)
    }

    @Test func cropOriginZeroSizedCrop() {
        let result = SaliencyResult(center: CGPoint(x: 50, y: 50), radius: 10, confidence: 1.0)
        let origin = result.cropOrigin(for: CGSize(width: 100, height: 100), cropSize: CGSize(width: 0, height: 0))
        #expect(origin.x == 50)
        #expect(origin.y == 50)
    }
}
