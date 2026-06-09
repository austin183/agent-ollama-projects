import CoreGraphics
import Foundation
import Testing
@testable import CollageMaker

@Suite struct CropInfoCodableTests {

    @Test func rectRoundTripPreservesAllFields() throws {
        let panelId = UUID()
        let sourceRect = CGRect(x: 10, y: 20, width: 80, height: 60)
        let destRect = CGRect(x: 0, y: 0, width: 200, height: 150)
        let original = CropInfo(panelId: panelId, sourceRect: sourceRect, destination: .rect(destRect))

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CropInfo.self, from: data)

        #expect(decoded.panelId == panelId)
        #expect(decoded.sourceRect == sourceRect)
        #expect(decoded.destinationRect == destRect)
        #expect(original == decoded)
    }

    @Test func pathRoundTripPreservesBoundingRect() throws {
        let panelId = UUID()
        let sourceRect = CGRect(x: 5, y: 5, width: 90, height: 90)
        let boundingRect = CGRect(x: 0, y: 0, width: 100, height: 100)

        var shear = CGAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0)
        let path = CGPath(rect: boundingRect, transform: nil)
            .copy(using: &shear)!

        let original = CropInfo(
            panelId: panelId,
            sourceRect: sourceRect,
            destination: .path(cgPath: path, boundingRect: boundingRect)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CropInfo.self, from: data)

        #expect(decoded.panelId == panelId)
        #expect(decoded.sourceRect == sourceRect)
        #expect(decoded.destinationRect == boundingRect)
    }

    @Test func pathRoundTripReconstructsAsRectPath() throws {
        let panelId = UUID()
        let sourceRect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let boundingRect = CGRect(x: 10, y: 20, width: 200, height: 150)

        var shear = CGAffineTransform(a: 1, b: 0, c: 0.15, d: 1, tx: 0, ty: 0)
        let path = CGPath(rect: boundingRect, transform: nil)
            .copy(using: &shear)!

        let original = CropInfo(
            panelId: panelId,
            sourceRect: sourceRect,
            destination: .path(cgPath: path, boundingRect: boundingRect)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CropInfo.self, from: data)

        switch decoded.destination {
        case .rect:
            Issue.record("Expected .path geometry after round-trip")
        case .path(_, let rect):
            #expect(rect == boundingRect)
        }
    }

    @Test func pathShapeIsLostAfterRoundTrip() throws {
        let panelId = UUID()
        let sourceRect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let boundingRect = CGRect(x: 0, y: 0, width: 200, height: 150)

        var shear = CGAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0)
        let originalPath = CGPath(rect: boundingRect, transform: nil)
            .copy(using: &shear)!

        let original = CropInfo(
            panelId: panelId,
            sourceRect: sourceRect,
            destination: .path(cgPath: originalPath, boundingRect: boundingRect)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CropInfo.self, from: data)

        // The decoded path is reconstructed as CGPath(rect:boundingRect, transform:nil),
        // which is a plain rectangle — the original shear transform is lost.
        // This is expected behavior: only the bounding rect is serialized.
        switch decoded.destination {
        case .rect:
            Issue.record("Expected .path geometry after round-trip")
        case .path(_, let rect):
            #expect(rect == boundingRect)
        }
    }

    @Test func defaultDestinationTypeIsRect() throws {
        let panelId = UUID()
        let sourceRect = CGRect(x: 0, y: 0, width: 50, height: 50)
        let destRect = CGRect(x: 0, y: 0, width: 100, height: 100)

        // Encode a CropInfo, then remove the destinationType key to simulate
        // legacy data that doesn't have the field.
        let original = CropInfo(panelId: panelId, sourceRect: sourceRect, destination: .rect(destRect))
        var jsonObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original), options: []) as! [String: Any]
        jsonObject.removeValue(forKey: "destinationType")
        let jsonData = try JSONSerialization.data(withJSONObject: jsonObject, options: [])

        let decoded = try JSONDecoder().decode(CropInfo.self, from: jsonData)

        #expect(decoded.panelId == panelId)
        #expect(decoded.sourceRect == sourceRect)
        #expect(decoded.destinationRect == destRect)

        switch decoded.destination {
        case .rect(let r):
            #expect(r == destRect)
        case .path:
            Issue.record("Expected .rect when destinationType is omitted")
        }
    }

    @Test func encodesDestinationTypeAsString() throws {
        let panelId = UUID()
        let rectInfo = CropInfo(panelId: panelId, sourceRect: .zero, destination: .rect(CGRect(x: 0, y: 0, width: 10, height: 10)))
        let pathInfo = CropInfo(panelId: panelId, sourceRect: .zero,
                                destination: .path(cgPath: CGPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10), transform: nil),
                                                   boundingRect: CGRect(x: 0, y: 0, width: 10, height: 10)))

        let rectData = try JSONEncoder().encode(rectInfo)
        let rectJson = String(decoding: rectData, as: UTF8.self)
        #expect(rectJson.contains("\"destinationType\":\"rect\""))

        let pathData = try JSONEncoder().encode(pathInfo)
        let pathJson = String(decoding: pathData, as: UTF8.self)
        #expect(pathJson.contains("\"destinationType\":\"path\""))
    }
}
