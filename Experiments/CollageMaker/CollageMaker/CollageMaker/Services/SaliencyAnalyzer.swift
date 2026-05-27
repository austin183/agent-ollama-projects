import CoreGraphics
import Foundation
import OSLog
import Vision

private let logger = Logger(
    subsystem: "austin183.indie.CollageMaker",
    category: "Analysis"
)

private let perfLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "performance"
)

enum SaliencyError: Error {
    case invalidImage
    case analysisFailed
}

protocol SaliencyAnalysis {
    func analyze(_ cgImage: CGImage) async throws -> SaliencyResult
    func analyzeAll(_ cgImages: [CGImage]) async throws -> [SaliencyResult]
}

actor SaliencyAnalyzer: SaliencyAnalysis {
    func analyze(_ cgImage: CGImage) async throws -> SaliencyResult {
        let analyzeStart = ContinuousClock.now
        defer { perfLogger.debug("Single Image Saliency completed in \(ContinuousClock.now - analyzeStart)") }

        let width = cgImage.width
        let height = cgImage.height

        guard width > 0 && height > 0 else {
            throw SaliencyError.invalidImage
        }

        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
        let faceRequest = VNDetectFaceRectanglesRequest()

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: CGImagePropertyOrientation.up,
            options: [:]
        )

        try handler.perform([saliencyRequest, faceRequest])

        let salientObjects = (saliencyRequest.results?.first as? VNSaliencyImageObservation)?.salientObjects ?? []
        let faces = faceRequest.results ?? []

        var points: [(x: CGFloat, y: CGFloat, weight: Float)] = []

        for obj in salientObjects {
            let box = obj.boundingBox
            let cx = box.midX * CGFloat(width)
            let cy = (1.0 - box.midY) * CGFloat(height)
            points.append((cx, cy, obj.confidence))
        }

        for face in faces {
            let box = face.boundingBox
            let cx = box.midX * CGFloat(width)
            let cy = (1.0 - box.midY) * CGFloat(height)
            points.append((cx, cy, max(face.confidence, 0.9)))
        }

        if points.isEmpty {
            return SaliencyResult(
                center: CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) / 2),
                radius: min(CGFloat(width), CGFloat(height)) / 3,
                confidence: 0.5
            )
        }

        let totalWeight = points.reduce(0) { $0 + $1.weight }
        let centerX = points.reduce(0) { $0 + $1.x * CGFloat($1.weight) } / CGFloat(totalWeight)
        let centerY = points.reduce(0) { $0 + $1.y * CGFloat($1.weight) } / CGFloat(totalWeight)
        let maxConf = points.map { $0.weight }.max()!

        var maxDim: CGFloat = 0
        for p in points {
            let dx = p.x - centerX
            let dy = p.y - centerY
            let dist = sqrt(dx * dx + dy * dy)
            if dist > maxDim {
                maxDim = dist
            }
        }

        let radius = max(maxDim, min(CGFloat(width), CGFloat(height)) / 6)

        return SaliencyResult(
            center: CGPoint(x: centerX, y: centerY),
            radius: radius,
            confidence: maxConf
        )
    }

    func analyzeAll(_ cgImages: [CGImage]) async throws -> [SaliencyResult] {
        logger.info("Analyzing \(cgImages.count) image(s) for saliency")
        return try await withThrowingTaskGroup(of: (Int, SaliencyResult).self) { group in
            for (index, cgImage) in cgImages.enumerated() {
                group.addTask {
                    let result = try await self.analyze(cgImage)
                    return (index, result)
                }
            }

            var results: [Int: SaliencyResult] = [:]
            for try await (index, result) in group {
                results[index] = result
            }
            return (0..<cgImages.count).compactMap { results[$0] }
        }
    }
}
