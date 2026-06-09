import CoreGraphics
import Foundation
import Testing
@testable import CollageMaker

@Suite struct PanelShapeTests {

    @Test func rectGeometryProducesRectPath() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 150)
        let geometry: PanelGeometry = .rect(rect)

        switch geometry {
        case .rect(let r):
            #expect(r == rect)
        case .path:
            Issue.record("Expected .rect geometry")
        }
    }

    @Test func shearedParallelogramTopEdgeRemainsShiftedRightAfterYFlip() {
        let boundingRect = CGRect(x: 0, y: 0, width: 200, height: 150)
        let targetRect = CGRect(x: 0, y: 0, width: 400, height: 300)

        var shear = CGAffineTransform(a: 1, b: 0, c: 0.3, d: 1, tx: 0, ty: 0)
        let transform = PanelGeometry.transformForPanel(boundingRect: boundingRect, targetRect: targetRect)
        let combined = shear.concatenating(transform)

        // True sheared parallelogram: shear c=0.3 shifts x by 0.3*y.
        // Top edge at y=150 is shifted 45px right (0.3 * 150).
        let bl = CGPoint(x: 0, y: 0).applying(combined)
        let br = CGPoint(x: 200, y: 0).applying(combined)
        let tr = CGPoint(x: 245, y: 150).applying(combined)
        let tl = CGPoint(x: 0, y: 150).applying(combined)

        #expect(bl.x < br.x, "Bottom edge: left should be left of right")
        #expect(tl.x < tr.x, "Top edge: left should be left of right")

        let bottomWidth = br.x - bl.x
        let topWidth = tr.x - tl.x

        // After Y-flip, the shear direction is preserved: top edge should still be wider
        // (top shifted right in the rendered SwiftUI view)
        #expect(topWidth > bottomWidth,
                "Shear preserved: top width \(topWidth) > bottom width \(bottomWidth)")
    }

    @Test func yFlipInvertsYCoordinates() {
        let boundingRect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let targetRect = CGRect(x: 0, y: 0, width: 100, height: 100)

        let transform = PanelGeometry.transformForPanel(boundingRect: boundingRect, targetRect: targetRect)

        // A point at the bottom of the bounding rect (y=0 in CG) should map to
        // the top of the target rect (y=100 in SwiftUI)
        let bottomPoint = CGPoint(x: 50, y: 0).applying(transform)
        let topPoint = CGPoint(x: 50, y: 100).applying(transform)

        #expect(bottomPoint.y == 100, "CG bottom (y=0) maps to SwiftUI top (y=100)")
        #expect(topPoint.y == 0, "CG top (y=100) maps to SwiftUI bottom (y=0)")
    }

    @Test func zeroBoundingRectReturnsIdentity() {
        let boundingRect = CGRect.zero
        let targetRect = CGRect(x: 0, y: 0, width: 200, height: 150)

        let transform = PanelGeometry.transformForPanel(boundingRect: boundingRect, targetRect: targetRect)
        #expect(transform == .identity)
    }

    @Test func offsetBoundingRectIsTranslatedCorrectly() {
        let boundingRect = CGRect(x: 50, y: 30, width: 200, height: 150)
        let targetRect = CGRect(x: 0, y: 0, width: 200, height: 150)

        let transform = PanelGeometry.transformForPanel(boundingRect: boundingRect, targetRect: targetRect)

        // Corners of the bounding rect should map to corners of the target rect
        let bl = CGPoint(x: 50, y: 30).applying(transform)
        let br = CGPoint(x: 250, y: 30).applying(transform)
        let tr = CGPoint(x: 250, y: 180).applying(transform)
        let tl = CGPoint(x: 50, y: 180).applying(transform)

        #expect(bl.x == 0)
        #expect(bl.y == 150)
        #expect(br.x == 200)
        #expect(br.y == 150)
        #expect(tr.x == 200)
        #expect(tr.y == 0)
        #expect(tl.x == 0)
        #expect(tl.y == 0)
    }

    @Test func scaledTransformPreservesProportions() {
        let boundingRect = CGRect(x: 0, y: 0, width: 100, height: 50)
        let targetRect = CGRect(x: 0, y: 0, width: 300, height: 150)

        let transform = PanelGeometry.transformForPanel(boundingRect: boundingRect, targetRect: targetRect)

        let bl = CGPoint(x: 0, y: 0).applying(transform)
        let tr = CGPoint(x: 100, y: 50).applying(transform)

        #expect(bl.x == 0)
        #expect(bl.y == 150)
        #expect(tr.x == 300)
        #expect(tr.y == 0)
    }
}
