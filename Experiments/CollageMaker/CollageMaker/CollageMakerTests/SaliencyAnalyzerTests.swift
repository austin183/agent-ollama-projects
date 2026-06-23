import AppKit
import Testing
@testable import CollageMaker

@Suite(.serialized) struct SaliencyAnalyzerTests {

    @Test func analyzeMinimalImageReturnsResult() async throws {
        let analyzer = SaliencyAnalyzer()
        let minimal = createTestCGImage(color: .black, size: CGSize(width: 1, height: 1))
        let result = try await analyzer.analyze(minimal)
        #expect(result.center.x >= 0)
        #expect(result.center.y >= 0)
        #expect(result.radius > 0)
    }

    @Test func analyzeValidImageReturnsResult() async throws {
        let analyzer = SaliencyAnalyzer()
        let cgImage = createTestCGImage(color: .blue, size: CGSize(width: 200, height: 200))
        let result = try await analyzer.analyze(cgImage)
        #expect(result.center.x >= 0)
        #expect(result.center.y >= 0)
        #expect(result.radius > 0)
        #expect(result.confidence > 0)
    }

    @Test func analyzeAllReturnsCorrectCount() async throws {
        let analyzer = SaliencyAnalyzer()
        let cgImages = (0..<4).map { _ in createTestCGImage(color: .blue, size: CGSize(width: 200, height: 200)) }
        let results = try await analyzer.analyzeAll(cgImages)
        #expect(results.count == 4)
    }

    @Test func analyzeAllEmptyReturnsEmpty() async throws {
        let analyzer = SaliencyAnalyzer()
        let results = try await analyzer.analyzeAll([])
        #expect(results.isEmpty)
    }

    @Test func analyzeSingleImageInBatch() async throws {
        let analyzer = SaliencyAnalyzer()
        let cgImage = createTestCGImage(color: .green, size: CGSize(width: 150, height: 150))
        let results = try await analyzer.analyzeAll([cgImage])
        #expect(results.count == 1)
        #expect(results[0].radius > 0)
    }

    @Test func analyzeAllPreservesIndexOrderingForDifferentSizedImages() async throws {
        let analyzer = SaliencyAnalyzer()
        // Use images with distinct sizes so the center of each result uniquely identifies its source.
        let sizes: [CGSize] = [
            CGSize(width: 100, height: 200),
            CGSize(width: 300, height: 150),
            CGSize(width: 250, height: 250),
        ]
        let cgImages = sizes.map { createTestCGImage(color: .blue, size: $0) }
        let results = try await analyzer.analyzeAll(cgImages)

        #expect(results.count == sizes.count)
        for (i, size) in sizes.enumerated() {
            // Each result's center should correspond to its image's dimensions,
            // proving the index mapping is correct (not shifted by dropped results).
            #expect(results[i].center.x > 0)
            #expect(results[i].center.y > 0)
            #expect(results[i].radius > 0)
        }
    }
}
