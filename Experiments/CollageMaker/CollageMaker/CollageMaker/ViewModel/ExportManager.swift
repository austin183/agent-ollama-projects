import AppKit
import CoreGraphics
import Foundation
import OSLog
import UniformTypeIdentifiers

private let logger = Logger(
    subsystem: "austin183.indie.CollageMaker",
    category: "Export"
)

enum ExportResult {
    case success(URL)
    case cancelled
    case failure(Error)
}

/// Abstracts the save panel presentation and folder memory so ExportManager
/// can be tested without NSSavePanel or UserDefaults.
protocol SavePanelPresenter {
    /// Presents a save panel and returns the chosen URL, or nil if cancelled.
    @MainActor
    func present(defaultFolder: URL?) async -> URL?
}

/// Default implementation using NSSavePanel + UserDefaults for folder memory.
final class DefaultSavePanelPresenter: SavePanelPresenter {
    func present(defaultFolder: URL?) async -> URL? {
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

        UserDefaults.standard.set(url.deletingLastPathComponent().path, forKey: UserDefaultsPersistence.Keys.defaultExportFolder)
        return url
    }
}

@MainActor
@Observable
final class ExportManager {
    var isExporting: Bool = false
    var successMessage: String? = nil

    private let assembler: any CollageRenderer
    private let savePanelPresenter: any SavePanelPresenter
    var exportTask: Task<Void, Error>?

    init(assembler: any CollageRenderer, savePanelPresenter: any SavePanelPresenter = DefaultSavePanelPresenter()) {
        self.assembler = assembler
        self.savePanelPresenter = savePanelPresenter
    }

    func export(
        config: AssemblyConfig,
        cgImages: [CGImage],
        backgroundImage: CGImage?,
        quality: Double
    ) async -> ExportResult {
        guard !config.layout.panels.isEmpty else { return .cancelled }

        exportTask?.cancel()
        isExporting = true
        successMessage = nil
        defer { isExporting = false }

        guard let url = await savePanelPresenter.present(defaultFolder: nil) else { return .cancelled }
        logger.info("Export to \(url.lastPathComponent, privacy: .public)")

        let assembler = self.assembler

        exportTask = Task.detached { [assembler, config, cgImages, backgroundImage, quality, url] in
            let data = await assembler.assembleWithCGImages(
                config: config,
                cgImages: cgImages,
                backgroundImage: backgroundImage,
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
            return .success(url)
        } catch {
            if !Task.isCancelled {
                logger.error("Export failed: \(error.localizedDescription, privacy: .public)")
            }
            return .failure(error)
        }
    }

    func dismissSuccess() {
        successMessage = nil
    }
}
