import AppKit
import CoreGraphics
import Foundation
import OSLog
import UniformTypeIdentifiers

private let logger = Logger(
    subsystem: "austin183.indie.CollageMaker",
    category: "Export"
)

@MainActor
@Observable
final class ExportManager {
    var isExporting: Bool = false
    var successMessage: String? = nil

    private let assembler: any CollageAssembly
    var exportTask: Task<Void, Error>?

    init(assembler: any CollageAssembly) {
        self.assembler = assembler
    }

    func export(viewModel: CollageViewModel) async -> URL? {
        guard !viewModel.panels.isEmpty else { return nil }

        exportTask?.cancel()
        viewModel.isProcessing = true
        isExporting = true
        successMessage = nil
        defer { viewModel.isProcessing = false; isExporting = false }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.jpeg]
        savePanel.nameFieldStringValue = "collage.jpg"

        if let folderPath = UserDefaults.standard.string(forKey: UserDefaultsPersistence.Keys.defaultExportFolder) {
            let folderUrl = URL(fileURLWithPath: folderPath)
            if folderUrl.folderExists {
                savePanel.directoryURL = folderUrl
            }
        }

        let response = NSApplication.shared.runModal(for: savePanel)
        guard response == .OK, let url = savePanel.url else { return nil }
        logger.info("Export to \(url.lastPathComponent, privacy: .public)")

        UserDefaults.standard.set(url.deletingLastPathComponent().path, forKey: UserDefaultsPersistence.Keys.defaultExportFolder)

        let config = viewModel.buildAssemblyConfig()
        let cgImages = viewModel.imageLibrary.images.map { $0.cgImage }
        let backgroundImageCG = viewModel.backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let quality = viewModel.exportQuality
        let assembler = self.assembler

        exportTask = Task.detached { [assembler, config, cgImages, backgroundImageCG, quality, url] in
            let data = await assembler.assembleWithCGImages(
                config: config,
                cgImages: cgImages,
                backgroundImage: backgroundImageCG,
                quality: quality
            )
            if let data {
                try data.write(to: url)
                logger.info("Exported collage: \(Int(data.count / 1024)) KB")
            }
        }

        do {
            try await exportTask?.value
            successMessage = "Saved to \(url.lastPathComponent)"
            return url
        } catch {
            if !Task.isCancelled {
                logger.error("Export failed: \(error.localizedDescription, privacy: .public)")
                viewModel.errorMessage = error.localizedDescription
            }
            return nil
        }
    }

    func dismissSuccess() {
        successMessage = nil
    }
}
