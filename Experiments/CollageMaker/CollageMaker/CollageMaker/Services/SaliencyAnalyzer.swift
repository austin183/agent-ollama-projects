import CoreGraphics
import Foundation
import OSLog
import Vision

private let logger = Logger(
    subsystem: "austin183.indie.CollageMaker",
    category: "Analysis"
)

private let perfLogger = Logger(
    subsystem: "austin183.indie.CollageMaker",
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
    nonisolated func analyze(_ cgImage: CGImage) async throws -> SaliencyResult {
        let analyzeStart = ContinuousClock.now
        defer { perfLogger.debug("Single Image Saliency completed in \(ContinuousClock.now - analyzeStart)") }

        let width = cgImage.width
        let height = cgImage.height

        guard width > 0 && height > 0 else {
            throw SaliencyError.invalidImage
        }

        logger.debug("Saliency image: \(width)x\(height) orientation=.up (EXIF stripped, always .up)")

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
        let imageSize = CGSize(width: width, height: height)

        logger.debug("  Faces detected: \(faces.count)")
        for (i, face) in faces.enumerated() {
            let box = face.boundingBox
            let cg = CoordinateConverter.visionToCG(CGPoint(x: box.midX, y: box.midY), imageSize: imageSize)
            let boxStr = String(format: "[%.3f,%.3f %.3fx%.3f]", box.minX, box.minY, box.width, box.height)
            let cgStr = String(format: "[%.0f,%.0f]", cg.x, cg.y)
            let confStr = String(format: "%.3f", face.confidence)
            logger.debug("  Face #\(i): box=\(boxStr) cg=\(cgStr) conf=\(confStr)")
        }
        logger.debug("  Salient objects: \(salientObjects.count)")

        var points: [(x: CGFloat, y: CGFloat, weight: Float)] = []

        for obj in salientObjects {
            let box = obj.boundingBox
            let cg = CoordinateConverter.visionToCG(CGPoint(x: box.midX, y: box.midY), imageSize: imageSize)
            points.append((cg.x, cg.y, obj.confidence))
        }

        for face in faces {
            let box = face.boundingBox
            let cg = CoordinateConverter.visionToCG(CGPoint(x: box.midX, y: box.midY), imageSize: imageSize)
            points.append((cg.x, cg.y, max(face.confidence, 0.9)))
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

        let centerStr = String(format: "[%.0f,%.0f]", centerX, centerY)
        let radiusStr = String(format: "%.0f", radius)
        let confStr = String(format: "%.3f", maxConf)
        logger.debug("  Result: center=\(centerStr) radius=\(radiusStr) conf=\(confStr)")

        return SaliencyResult(
            center: CGPoint(x: centerX, y: centerY),
            radius: radius,
            confidence: maxConf
        )
    }

    func analyzeAll(_ cgImages: [CGImage]) async throws -> [SaliencyResult] {
        logger.info("Analyzing \(cgImages.count) image(s) for saliency")
        return await withTaskGroup(of: (Int, Result<SaliencyResult, Error>).self) { group in
            for (index, cgImage) in cgImages.enumerated() {
                group.addTask {
                    let result: Result<SaliencyResult, Error>
                    do {
                        result = .success(try await self.analyze(cgImage))
                    } catch {
                        result = .failure(error)
                    }
                    return (index, result)
                }
            }

            var results: [Int: SaliencyResult] = [:]
            for await (index, result) in group {
                switch result {
                case .success(let saliencyResult):
                    results[index] = saliencyResult
                case .failure(let error):
                    logger.error("Saliency analysis failed for image at index \(index): \(error.localizedDescription, privacy: .public)")
                    let img = cgImages[index]
                    let fallback = SaliencyResult(
                        center: CGPoint(x: CGFloat(img.width) / 2, y: CGFloat(img.height) / 2),
                        radius: min(CGFloat(img.width), CGFloat(img.height)) / 3,
                        confidence: 0.5
                    )
                    results[index] = fallback
                }
            }
            return (0..<cgImages.count).compactMap { results[$0] }
        }
    }
}
