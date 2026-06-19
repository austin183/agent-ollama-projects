import Foundation
import OSLog

private let logger = Logger(
    subsystem: "austin183.indie.CollageMaker",
    category: "TestBootstrap"
)

enum TestBootstrap {
    private static let imageExtensions = ["jpg", "jpeg", "png", "tiff", "heic", "heif"]

    static func loadTestImageURLs() -> [URL]? {
        guard let dirPath = ProcessInfo.processInfo.environment["COLLAGEMAKER_TEST_IMAGES_DIR"] else {
            logger.info("COLLAGEMAKER_TEST_IMAGES_DIR not set, skipping test bootstrap")
            return nil
        }
        logger.info("Test images dir: \(dirPath, privacy: .public)")

        let dirURL = URL(fileURLWithPath: dirPath, isDirectory: true)

        guard let entries = try? FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil) else {
            logger.error("Failed to read test images directory: \(dirPath, privacy: .public)")
            return nil
        }

        let imageURLs = entries.filter { url in
            guard url.hasDirectoryPath == false else { return false }
            let ext = url.pathExtension.lowercased()
            return imageExtensions.contains(ext)
        }.sorted { $0.path < $1.path }

        logger.info("Found \(imageURLs.count) test image(s)")
        return imageURLs.isEmpty ? nil : imageURLs
    }
}
