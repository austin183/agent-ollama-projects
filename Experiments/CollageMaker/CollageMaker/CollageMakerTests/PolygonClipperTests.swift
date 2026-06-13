import CoreGraphics
import Testing
@testable import CollageMaker

@Suite struct PolygonClipperTests {

    @Test func clipRectangleFullyInside() {
        let rect: [CGPoint] = [
            CGPoint(x: 10, y: 10),
            CGPoint(x: 90, y: 10),
            CGPoint(x: 90, y: 90),
            CGPoint(x: 10, y: 90)
        ]
        let clipRect = CGRect(x: 0, y: 0, width: 100, height: 100)

        let result = PolygonClipper.clip(rect, to: clipRect)

        #expect(result.count == 4)
        #expect(result[0] == rect[0])
        #expect(result[1] == rect[1])
        #expect(result[2] == rect[2])
        #expect(result[3] == rect[3])
    }

    @Test func clipRectanglePartiallyOutside() {
        let rect: [CGPoint] = [
            CGPoint(x: -10, y: 10),
            CGPoint(x: 90, y: 10),
            CGPoint(x: 90, y: 90),
            CGPoint(x: -10, y: 90)
        ]
        let clipRect = CGRect(x: 0, y: 0, width: 100, height: 100)

        let result = PolygonClipper.clip(rect, to: clipRect)

        #expect(result.count == 4)
        #expect(result[0].x >= clipRect.minX)
        #expect(result[0].y >= clipRect.minY)
        #expect(result[0].x <= clipRect.maxX)
        #expect(result[0].y <= clipRect.maxY)
    }

    @Test func clipRectangleFullyOutside() {
        let rect: [CGPoint] = [
            CGPoint(x: 110, y: 110),
            CGPoint(x: 200, y: 110),
            CGPoint(x: 200, y: 200),
            CGPoint(x: 110, y: 200)
        ]
        let clipRect = CGRect(x: 0, y: 0, width: 100, height: 100)

        let result = PolygonClipper.clip(rect, to: clipRect)

        #expect(result.isEmpty)
    }

    @Test func clipEmptyInput() {
        let rect: [CGPoint] = []
        let clipRect = CGRect(x: 0, y: 0, width: 100, height: 100)

        let result = PolygonClipper.clip(rect, to: clipRect)

        #expect(result.isEmpty)
    }

    @Test func clipPointOnEdge() {
        let rect: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 50, y: 0),
            CGPoint(x: 50, y: 50),
            CGPoint(x: 0, y: 50)
        ]
        let clipRect = CGRect(x: 0, y: 0, width: 100, height: 100)

        let result = PolygonClipper.clip(rect, to: clipRect)

        #expect(result.count == 4)
    }

    @Test func clipTriangle() {
        let triangle: [CGPoint] = [
            CGPoint(x: 50, y: 10),
            CGPoint(x: 90, y: 90),
            CGPoint(x: 10, y: 90)
        ]
        let clipRect = CGRect(x: 0, y: 0, width: 100, height: 100)

        let result = PolygonClipper.clip(triangle, to: clipRect)

        #expect(result.count >= 3)
        for point in result {
            #expect(point.x >= clipRect.minX)
            #expect(point.x <= clipRect.maxX)
            #expect(point.y >= clipRect.minY)
            #expect(point.y <= clipRect.maxY)
        }
    }
}
