import AppKit
import Foundation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

private let logger = Logger(
    subsystem: "austin183.indie.CollageMaker",
    category: "ViewModel"
)

enum ViewModelUserDefaultsKeys {
    static let layoutStyle = "layoutStyle"
    static let gutter = "gutter"
    static let backgroundColor = "backgroundColor"
    static let exportQuality = "exportQuality"
    static let title = "title"
    static let backgroundStyle = "backgroundStyle"
    static let gradientStartColor = "gradientStartColor"
    static let gradientEndColor = "gradientEndColor"
    static let gradientAngle = "gradientAngle"
    static let backgroundOpacity = "backgroundOpacity"
    static let customImageOrder = "customImageOrder"
    static let backgroundImagePath = "backgroundImagePath"
}

@MainActor
@Observable
final class CollageViewModel {
    private let saliencyAnalyzer: SaliencyAnalysis
    private let assembler: CollageAssembly
    private let cropManager = CropManager()
    private let scrollPanManager = ScrollPanManager()
    let undoManager = UndoManager()
    private var saliencyResults: [Int: SaliencyResult] = [:]
    private var exportTask: Task<Void, Error>?

    var images: [ImageItem] = []
    var panels: [ImagePanel] = []
    var cropMap: [UUID: CropInfo] = [:]
    var selectedPanelId: UUID?

    var layoutStyle: LayoutStyle = LayoutStyle(rawValue: UserDefaults.standard.string(forKey: ViewModelUserDefaultsKeys.layoutStyle) ?? "hero") ?? .hero {
        didSet {
            undoManager.registerUndo(withTarget: self) { target in
                target.layoutStyle = oldValue
            }
            undoManager.setActionName("Change Layout")
            UserDefaults.standard.set(self.layoutStyle.rawValue, forKey: ViewModelUserDefaultsKeys.layoutStyle)
            logger.info("Layout style changed to \(self.layoutStyle.rawValue, privacy: .public)")
            regenerateLayout()
        }
    }

    var titleAttrString: NSAttributedString = {
        if let data = UserDefaults.standard.data(forKey: "titleAttrString"),
           let attr = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data) {
            return attr
        }
        if let oldTitle = UserDefaults.standard.string(forKey: ViewModelUserDefaultsKeys.title), !oldTitle.isEmpty {
            return NSAttributedString(string: oldTitle)
        }
        if let defaultTitle = UserDefaults.standard.string(forKey: "defaultTitle"), !defaultTitle.isEmpty {
            let fontFamily = UserDefaults.standard.string(forKey: "defaultFontFamily") ?? ""
            let fontSize = UserDefaults.standard.double(forKey: "defaultFontSize")
            let font: NSFont
            if !fontFamily.isEmpty, let f = NSFont(name: fontFamily, size: fontSize) {
                font = f
            } else {
                font = NSFont.boldSystemFont(ofSize: fontSize)
            }
            return NSAttributedString(string: defaultTitle, attributes: [.font: font])
        }
        return NSAttributedString(string: "")
    }() {
        didSet {
            undoManager.registerUndo(withTarget: self) { target in
                target.titleAttrString = oldValue
            }
            undoManager.setActionName("Edit Title")
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: titleAttrString, requiringSecureCoding: false) {
                UserDefaults.standard.set(data, forKey: "titleAttrString")
            }
            updatePreview()
        }
    }

    var title: String {
        titleAttrString.string
    }

    var titleStyle: TitleStyle = .fromUserDefaults() {
        didSet {
            undoManager.registerUndo(withTarget: self) { target in
                target.titleStyle = oldValue
            }
            undoManager.setActionName("Change Title Style")
            titleStyle.saveToUserDefaults()
            updatePreview()
        }
    }

    var gutter: CGFloat = CGFloat(UserDefaults.standard.double(forKey: ViewModelUserDefaultsKeys.gutter)) {
        didSet {
            undoManager.registerUndo(withTarget: self) { target in
                target.gutter = oldValue
            }
            undoManager.setActionName("Change Gutter")
            UserDefaults.standard.set(Double(gutter), forKey: ViewModelUserDefaultsKeys.gutter)
            regenerateLayout()
        }
    }

    var scrollSensitivity: CGFloat = 1.6

    private func saveColor(_ color: NSColor, key: String) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadColor(key: String, default: NSColor) -> NSColor {
        if let data = UserDefaults.standard.data(forKey: key),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            return color
        }
        return `default`
    }

    var backgroundColor: NSColor = .black {
        didSet {
            undoManager.registerUndo(withTarget: self) { target in
                target.backgroundColor = oldValue
            }
            undoManager.setActionName("Change Background Color")
            saveColor(backgroundColor, key: ViewModelUserDefaultsKeys.backgroundColor)
            updatePreview()
        }
    }

    var exportQuality: Double = UserDefaults.standard.double(forKey: ViewModelUserDefaultsKeys.exportQuality) {
        didSet {
            undoManager.registerUndo(withTarget: self) { target in
                target.exportQuality = oldValue
            }
            undoManager.setActionName("Change Export Quality")
            UserDefaults.standard.set(exportQuality, forKey: ViewModelUserDefaultsKeys.exportQuality)
        }
    }

    var backgroundStyle: BackgroundStyle = BackgroundStyle(rawValue: UserDefaults.standard.string(forKey: ViewModelUserDefaultsKeys.backgroundStyle) ?? "solid") ?? .solid {
        didSet {
            undoManager.registerUndo(withTarget: self) { target in
                target.backgroundStyle = oldValue
            }
            undoManager.setActionName("Change Background Style")
            UserDefaults.standard.set(backgroundStyle.rawValue, forKey: ViewModelUserDefaultsKeys.backgroundStyle)
            updatePreview()
        }
    }

    var gradientStartColor: NSColor = .black {
        didSet {
            undoManager.registerUndo(withTarget: self) { target in
                target.gradientStartColor = oldValue
            }
            undoManager.setActionName("Change Gradient Start Color")
            saveColor(gradientStartColor, key: ViewModelUserDefaultsKeys.gradientStartColor)
            updatePreview()
        }
    }

    var gradientEndColor: NSColor = .darkGray {
        didSet {
            undoManager.registerUndo(withTarget: self) { target in
                target.gradientEndColor = oldValue
            }
            undoManager.setActionName("Change Gradient End Color")
            saveColor(gradientEndColor, key: ViewModelUserDefaultsKeys.gradientEndColor)
            updatePreview()
        }
    }

    var gradientAngle: Double = UserDefaults.standard.double(forKey: ViewModelUserDefaultsKeys.gradientAngle) {
        didSet {
            undoManager.registerUndo(withTarget: self) { target in
                target.gradientAngle = oldValue
            }
            undoManager.setActionName("Change Gradient Angle")
            UserDefaults.standard.set(gradientAngle, forKey: ViewModelUserDefaultsKeys.gradientAngle)
            updatePreview()
        }
    }

    var backgroundImage: NSImage? {
        didSet {
            if backgroundImage == nil {
                UserDefaults.standard.removeObject(forKey: ViewModelUserDefaultsKeys.backgroundImagePath)
            }
            updatePreview()
        }
    }
    var backgroundOpacity: Double = {
        if UserDefaults.standard.object(forKey: ViewModelUserDefaultsKeys.backgroundOpacity) != nil {
            return UserDefaults.standard.double(forKey: ViewModelUserDefaultsKeys.backgroundOpacity)
        }
        return 1.0
    }() {
        didSet {
            undoManager.registerUndo(withTarget: self) { target in
                target.backgroundOpacity = oldValue
            }
            undoManager.setActionName("Change Background Opacity")
            UserDefaults.standard.set(backgroundOpacity, forKey: ViewModelUserDefaultsKeys.backgroundOpacity)
            updatePreview()
        }
    }

    var panelAssignments: [UUID: Int] = [:]

    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    var customImageOrder: [Int] = {
        if let data = UserDefaults.standard.data(forKey: ViewModelUserDefaultsKeys.customImageOrder),
           let order = try? JSONDecoder().decode([Int].self, from: data) {
            return order
        }
        return []
    }() {
        didSet {
            if let data = try? jsonEncoder.encode(customImageOrder) {
                UserDefaults.standard.set(data, forKey: ViewModelUserDefaultsKeys.customImageOrder)
            }
        }
    }

    var previewImage: NSImage?
    var isProcessing: Bool = false
    var isExporting: Bool = false
    var isDraggingTitle: Bool = false
    var errorMessage: String?
    var exportSuccessMessage: String?

    func dismissExportSuccess() {
        exportSuccessMessage = nil
    }

    convenience init() {
        self.init(
            saliencyAnalyzer: SaliencyAnalyzer(),
            assembler: CollageAssembler()
        )
    }

    init(
        saliencyAnalyzer: SaliencyAnalysis,
        assembler: CollageAssembly
    ) {
        self.saliencyAnalyzer = saliencyAnalyzer
        self.assembler = assembler
        self.backgroundColor = loadColor(key: ViewModelUserDefaultsKeys.backgroundColor, default: .black)
        self.gradientStartColor = loadColor(key: ViewModelUserDefaultsKeys.gradientStartColor, default: .black)
        self.gradientEndColor = loadColor(key: ViewModelUserDefaultsKeys.gradientEndColor, default: .darkGray)
        if let path = UserDefaults.standard.string(forKey: ViewModelUserDefaultsKeys.backgroundImagePath),
           let url = URL(string: path),
           FileManager.default.fileExists(atPath: path),
           let data = try? Data(contentsOf: url),
           let image = NSImage(data: data) {
            self.backgroundImage = image
        }
    }

    // MARK: - Image Loading

    func browseImages() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.jpeg, .png, .tiff, .heic, .heif]

        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            if response == .OK {
                Task { [weak self] in
                    await self?.addImages(from: panel.urls)
                }
            }
        }
    }

    func addImages(from urls: [URL]) async {
        let newItems = await withTaskGroup(of: ImageItem?.self) { group in
            for url in urls {
                group.addTask {
                    guard let data = try? Data(contentsOf: url),
                          let nsImage = NSImage(data: data),
                          let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

                    let thumbSize: CGSize
                    if cgImage.width > cgImage.height {
                        thumbSize = CGSize(width: 64, height: CGFloat(cgImage.height) * 64 / CGFloat(cgImage.width))
                    } else {
                        thumbSize = CGSize(width: CGFloat(cgImage.width) * 64 / CGFloat(cgImage.height), height: 64)
                    }

                    guard let context = CGContext(
                        data: nil,
                        width: Int(thumbSize.width),
                        height: Int(thumbSize.height),
                        bitsPerComponent: 8,
                        bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                    ) else { return nil }

                    context.interpolationQuality = .high
                    context.draw(cgImage, in: CGRect(origin: .zero, size: thumbSize))

                    guard let drawnCG = context.makeImage() else { return nil }
                    let thumbnail = NSImage(cgImage: drawnCG, size: thumbSize)

                    return ImageItem(
                        nsImage: nsImage,
                        cgImage: cgImage,
                        thumbnail: thumbnail,
                        filename: url.lastPathComponent,
                        size: CGSize(width: cgImage.width, height: cgImage.height)
                    )
                }
            }

            var items: [ImageItem] = []
            for await item in group {
                if let item { items.append(item) }
            }
            return items
        }

        guard !newItems.isEmpty else { return }
        logger.info("Added \(newItems.count) image(s); total count \(self.images.count + newItems.count)")
        images.append(contentsOf: newItems)
        regenerateLayout()

        if !isProcessing {
            Task { [weak self] in
                await self?.analyzeSaliency()
            }
        }
    }

    func removeImage(at index: Int) {
        guard index < images.count else { return }
        let removed = images[index]
        undoManager.registerUndo(withTarget: self) { target in
            target.images.insert(removed, at: index)
            target.regenerateLayout()
        }
        undoManager.setActionName("Remove Image")
        images.remove(at: index)
        regenerateLayout()

        Task { [weak self] in
            await self?.analyzeSaliency()
        }
    }

    func moveImages(from: IndexSet, to: Int) {
        let first = from.first
        let last = from.last
        let count = images.count
        let oldOrder = images.map { $0.id }
        let oldCustomOrder = customImageOrder

        if let first, let last, !customImageOrder.isEmpty {
            let oldPos = buildMoveMapping(fromFirst: first, fromLast: last, to: to, count: count)
            customImageOrder = customImageOrder.map { customImageOrder[oldPos[$0]] }
        }

        undoManager.registerUndo(withTarget: self) { target in
            target.customImageOrder = oldCustomOrder
            target.regenerateLayout()
        }
        undoManager.setActionName("Reorder Images")

        images.move(fromOffsets: from, toOffset: to)
        panelAssignments.removeAll()
        regenerateLayout()

        Task { [weak self] in
            await self?.analyzeSaliency()
        }
    }

    private func buildMoveMapping(fromFirst: Int, fromLast: Int, to: Int, count: Int) -> [Int] {
        var oldPos = Array(0..<count)

        guard to != fromFirst else { return oldPos }

        if to < fromFirst {
            oldPos[to] = fromLast
            for i in to..<fromLast {
                oldPos[i + 1] = i
            }
        } else {
            oldPos[to] = fromFirst
            for i in (fromFirst + 1)...to {
                oldPos[i - 1] = i
            }
        }

        return oldPos
    }

    func clearAll() {
        guard !images.isEmpty else { return }
        logger.info("Clear all images")
        let oldImages = images, oldPanels = panels, oldCropMap = cropMap, oldCustomOrder = customImageOrder
        undoManager.registerUndo(withTarget: self) { target in
            target.images = oldImages
            target.panels = oldPanels
            target.cropMap = oldCropMap
            target.customImageOrder = oldCustomOrder
            target.regenerateLayout()
        }
        undoManager.setActionName("Clear All")
        exportTask?.cancel()
        exportTask = nil
        images.removeAll()
        panels.removeAll()
        cropMap.removeAll()
        saliencyResults.removeAll()
        selectedPanelId = nil
        previewImage = nil
        isProcessing = false
        errorMessage = nil
        panelAssignments.removeAll()
        customImageOrder.removeAll()
        backgroundImage = nil
        UserDefaults.standard.removeObject(forKey: ViewModelUserDefaultsKeys.backgroundImagePath)
    }

    // MARK: - Layout

    func regenerateLayout() {
        guard !images.isEmpty else { return }

        if customImageOrder.isEmpty || customImageOrder.count != images.count {
            customImageOrder = Array(0..<images.count)
        }

        let oldSelectedId = selectedPanelId
        panels = LayoutGenerator.generate(
            numImages: images.count,
            canvasSize: CanvasConfig.defaultCanvasSize,
            gutter: gutter,
            style: layoutStyle,
            imageOrder: customImageOrder
        )
        let panelCount = panels.count
        let styleRaw = layoutStyle.rawValue
        let selectedStr = oldSelectedId?.uuidString ?? "nil"
        let foundInNew = oldSelectedId != nil && panels.contains { $0.id == oldSelectedId }
        logger.info("Regenerated layout: \(panelCount) panels, style=\(styleRaw, privacy: .public), selectedId=\(selectedStr, privacy: .public), foundInNew=\(foundInNew)")

        panelAssignments.removeAll()
        for (i, panel) in panels.enumerated() {
            panelAssignments[panel.id] = customImageOrder[i]
        }

        if saliencyResults.isEmpty {
            cropManager.computeInitialCrops(panels: panels, images: images)
        } else {
            cropManager.computeCropsFromSaliency(
                panels: panels,
                images: images,
                results: saliencyResults
            )
        }

        cropMap = cropManager.cropMap
        updatePreview()
    }

    func setLayoutStyle(_ style: LayoutStyle) {
        layoutStyle = style
    }

    func updateGutter(_ value: CGFloat) {
        gutter = value
    }

    // MARK: - Panel Image Assignment

    func assignImage(_ imageIndex: Int, to panelId: UUID) {
        panelAssignments[panelId] = imageIndex
        resetCrop(panelId: panelId)
        updatePreview()
    }

    func getEffectiveImageIndex(for panelId: UUID) -> Int? {
        if let assigned = panelAssignments[panelId] {
            return assigned
        }
        guard let panelIndex = panels.firstIndex(where: { $0.id == panelId }) else { return nil }
        return panelIndex
    }

    func selectPanelForImage(at imageIndex: Int) {
        guard imageIndex < images.count else { return }
        if let panel = panels.first(where: { panelAssignments[$0.id] == imageIndex || $0.imageIndex == imageIndex }) {
            selectedPanelId = panel.id
        }
    }

    func swapPanelImages(sourceId: UUID, targetId: UUID) {
        guard sourceId != targetId else { return }
        guard let sourceSlot = panels.firstIndex(where: { $0.id == sourceId }),
              let targetSlot = panels.firstIndex(where: { $0.id == targetId }) else { return }
        let oldOrder = customImageOrder
        undoManager.registerUndo(withTarget: self) { target in
            target.customImageOrder = oldOrder
            target.regenerateLayout()
        }
        undoManager.setActionName("Swap Images")
        customImageOrder.swapAt(sourceSlot, targetSlot)
        panelAssignments[sourceId] = customImageOrder[sourceSlot]
        panelAssignments[targetId] = customImageOrder[targetSlot]

        if let cropA = cropMap[sourceId], let cropB = cropMap[targetId] {
            cropMap[sourceId] = CropInfo(panelId: sourceId, sourceRect: cropB.sourceRect, destinationRect: cropA.destinationRect)
            cropMap[targetId] = CropInfo(panelId: targetId, sourceRect: cropA.sourceRect, destinationRect: cropB.destinationRect)
            cropManager.cropMap = cropMap
        }

        updatePreview()
    }

    // MARK: - Saliency

    func analyzeSaliency() async {
        guard !images.isEmpty else { return }
        logger.info("Saliency analysis started for \(self.images.count) image(s)")
        isProcessing = true
        defer { isProcessing = false }

        do {
            let results = try await saliencyAnalyzer.analyzeAll(images.map { $0.cgImage })
            var indexed: [Int: SaliencyResult] = [:]
            for (i, result) in results.enumerated() {
                indexed[i] = result
            }
            await MainActor.run {
                logger.info("Saliency analysis complete: \(indexed.count) result(s)")
                saliencyResults = indexed
                cropManager.computeCropsFromSaliency(
                    panels: panels,
                    images: images,
                    results: indexed
                )
                cropMap = cropManager.cropMap
                updatePreview()
            }
        } catch {
            logger.error("Saliency analysis failed: \(error.localizedDescription, privacy: .public)")
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Crop (delegated to CropManager)

    func beginPan(panelId: UUID) {
        cropManager.beginPan(panelId: panelId)
    }

    func pan(by delta: CGSize) {
        cropManager.pan(by: delta)
    }

    func applyPan(panelId: UUID?) {
        cropManager.applyPan(panelId: panelId, panels: panels, images: images, panelAssignments: panelAssignments, finish: true)
        cropMap = cropManager.cropMap
        updatePreview()
    }

    func applyPanLive() {
        cropManager.applyPan(panelId: nil, panels: panels, images: images, panelAssignments: panelAssignments, finish: false)
        cropMap = cropManager.cropMap

        previewDebounce?.cancel()
        previewDebounce = DispatchWorkItem { [weak self] in
            self?.updatePreview()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: previewDebounce!)
    }

    func beginPinch(panelId: UUID) {
        cropManager.beginPinch(panelId: panelId)
    }

    func pinch(magnification: CGFloat) {
        cropManager.pinch(magnification: magnification)
    }

    func applyPinch(panelId: UUID?) {
        cropManager.applyPinch(panelId: panelId, panels: panels, images: images, panelAssignments: panelAssignments, finish: true)
        cropMap = cropManager.cropMap
        updatePreview()
    }

    func applyPinchLive() {
        cropManager.applyPinch(panelId: nil, panels: panels, images: images, panelAssignments: panelAssignments, finish: false)
        cropMap = cropManager.cropMap
        updatePreview()
    }

    func resetCrop(panelId: UUID) {
        logger.info("Reset crop for panel")
        if let oldCrop = cropMap[panelId] {
            undoManager.registerUndo(withTarget: self) { target in
                target.cropMap[panelId] = oldCrop
                target.cropManager.cropMap = target.cropMap
                target.updatePreview()
            }
            undoManager.setActionName("Reset Crop")
        }
        cropManager.resetCrop(panelId: panelId, panels: panels, images: images, panelAssignments: panelAssignments)
        cropMap = cropManager.cropMap
        updatePreview()
    }

    // MARK: - Overlay Crop (Panel Editor drag/resize)

    func beginOverlayCropUndo(panelId: UUID) {
        guard let oldCrop = cropMap[panelId] else { return }
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { target in
            target.cropMap[panelId] = oldCrop
            target.cropManager.cropMap[panelId] = oldCrop
            target.updatePreview()
        }
    }

    func endOverlayCropUndo() {
        undoManager.setActionName("Adjust Crop")
        undoManager.endUndoGrouping()
    }

    func applyOverlayCrop(panelId: UUID, sourceRect: CGRect) {
        guard let crop = cropMap[panelId] else { return }
        let newCrop = CropInfo(
            panelId: panelId,
            sourceRect: sourceRect,
            destinationRect: crop.destinationRect
        )
        cropMap[panelId] = newCrop
        cropManager.cropMap[panelId] = newCrop
        var tmp = cropMap
        cropMap = tmp
        updatePreview()
    }

    // MARK: - Scroll Pan (delegated to ScrollPanManager)

    func beginScrollPan(panelId: UUID) {
        scrollPanManager.beginScrollPan(panelId: panelId) { [weak self] pid in
            self?.cropManager.beginPan(panelId: pid)
        }
    }

    func scrollPanDelta(_ delta: CGSize) {
        scrollPanManager.scrollPanDelta(
            delta,
            sensitivity: scrollSensitivity,
            applyLive: { [weak self] in
                guard let self else { return }
                cropManager.pan(by: scrollPanManager.accumulator)
                cropManager.applyPan(
                    panelId: nil,
                    panels: panels,
                    images: images,
                    panelAssignments: panelAssignments,
                    finish: false
                )
                cropMap = cropManager.cropMap
                updatePreview()
            },
            commit: { [weak self] in
                guard let self, let id = scrollPanManager.activePanelId else { return }
                cropManager.applyPan(
                    panelId: id,
                    panels: panels,
                    images: images,
                    panelAssignments: panelAssignments,
                    finish: true
                )
                cropManager.beginPan(panelId: id)
                cropMap = cropManager.cropMap
                updatePreview()
            }
        )
    }

    func endScrollPan() {
        scrollPanManager.endScrollPan()
    }

    // MARK: - Preview & Export

    private var previewTask: Task<Void, Never>?
    private var previewDebounce: DispatchWorkItem?

    func updatePreview() {
        guard !panels.isEmpty else { return }

        let config = AssemblyConfig(
            panels: self.panels,
            crops: self.cropMap,
            panelAssignments: self.panelAssignments,
            titleAttrString: self.titleAttrString,
            titleStyle: self.titleStyle,
            backgroundColor: self.backgroundColor,
            backgroundStyle: self.backgroundStyle,
            gradientStartColor: self.gradientStartColor,
            gradientEndColor: self.gradientEndColor,
            gradientAngle: self.gradientAngle,
            backgroundOpacity: self.backgroundOpacity,
            canvasSize: CanvasConfig.defaultCanvasSize
        )
        let cgImages = self.images.map { $0.cgImage }
        let backgroundImageCG = self.backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let assembler = self.assembler

        previewTask?.cancel()
        previewTask = Task.detached { [weak self] in
            let result = assembler.assemblePreviewWithCGImages(
                config: config,
                cgImages: cgImages,
                backgroundImage: backgroundImageCG,
                previewSize: CanvasConfig.defaultPreviewSize
            )
            Task { @MainActor in
                self?.previewImage = result
            }
        }
    }

    func exportCollage() async -> URL? {
        guard !panels.isEmpty else { return nil }

        exportTask?.cancel()
        isProcessing = true
        isExporting = true
        exportSuccessMessage = nil
        defer { isProcessing = false; isExporting = false }

        // NOTE: NSApplication.shared.runModal(for:) blocks the main thread.
        // This is unavoidable for NSSavePanel — Apple provides no async
        // alternative. The panel is presented modally and returns only
        // when the user confirms or cancels.
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.jpeg]
        savePanel.nameFieldStringValue = "collage.jpg"

        if let folderPath = UserDefaults.standard.string(forKey: "defaultExportFolder"),
           let folderUrl = URL(string: folderPath), folderUrl.folderExists {
            savePanel.directoryURL = folderUrl
        }

        let response = NSApplication.shared.runModal(for: savePanel)
        guard response == .OK, let url = savePanel.url else { return nil }
        logger.info("Export to \(url.lastPathComponent, privacy: .public)")

        UserDefaults.standard.set(url.deletingLastPathComponent().path, forKey: "defaultExportFolder")

        let config = AssemblyConfig(
            panels: self.panels,
            crops: self.cropMap,
            panelAssignments: self.panelAssignments,
            titleAttrString: self.titleAttrString,
            titleStyle: self.titleStyle,
            backgroundColor: self.backgroundColor,
            backgroundStyle: self.backgroundStyle,
            gradientStartColor: self.gradientStartColor,
            gradientEndColor: self.gradientEndColor,
            gradientAngle: self.gradientAngle,
            backgroundOpacity: self.backgroundOpacity,
            canvasSize: CanvasConfig.defaultCanvasSize
        )
        let cgImages = self.images.map { $0.cgImage }
        let backgroundImageCG = self.backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let quality = self.exportQuality
        let assembler = self.assembler

        exportTask = Task.detached {
            let data = assembler.assembleWithCGImages(
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
            exportSuccessMessage = "Saved to \(url.lastPathComponent)"
            return url
        } catch {
            if !Task.isCancelled {
                logger.error("Export failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
            return nil
        }
    }
}

extension URL {
    var folderExists: Bool {
        FileManager.default.fileExists(atPath: deletingLastPathComponent().path)
    }
}
