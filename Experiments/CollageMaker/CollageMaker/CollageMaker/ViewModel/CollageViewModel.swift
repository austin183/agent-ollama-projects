import AppKit
import Foundation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

private let logger = Logger(
    subsystem: "austin183.indie.CollageMaker",
    category: "ViewModel"
)

private let perfLogger = Logger(
    subsystem: "austin183.indie.CollageMaker",
    category: "performance"
)


@MainActor
@Observable
final class CollageViewModel {
    private let saliencyAnalyzer: SaliencyAnalysis
    private let assembler: CollageAssembly
    private let persistence: UserDefaultsPersistence
    let cropManager = CropManager()
    private let scrollPanManager = ScrollPanManager()
    let undoManager = UndoManager()
    private var isInitializing = false
    private var saliencyResults: [Int: SaliencyResult] = [:]
    private var exportTask: Task<Void, Error>?
    private var saveDebounceTask: Task<Void, Never>?

    var images: [ImageItem] = []
    var panels: [ImagePanel] = []
    var selectedPanelId: UUID?

    /// Single source of truth for crop state — delegated to CropManager.
    var cropMap: [UUID: CropInfo] {
        get { cropManager.cropMap }
        set { cropManager.cropMap = newValue }
    }

    var layoutStyle: LayoutStyle = .hero {
        didSet {
            guard !isInitializing else { return }
            undoManager.registerUndo(withTarget: self) { target in
                target.layoutStyle = oldValue
            }
            undoManager.setActionName("Change Layout")
            debouncedSave()
            logger.info("Layout style changed to \(self.layoutStyle.rawValue, privacy: .public)")
            regenerateLayout()
        }
    }

    var titleAttrString: NSAttributedString = NSAttributedString(string: "") {
        didSet {
            guard !isInitializing else { return }
            undoManager.registerUndo(withTarget: self) { target in
                target.titleAttrString = oldValue
            }
            undoManager.setActionName("Edit Title")
            debouncedSave()
            updatePreview()
        }
    }

    var title: String {
        titleAttrString.string
    }

    var titleStyle: TitleStyle = .default {
        didSet {
            guard !isInitializing else { return }
            if !isDraggingTitle {
                undoManager.registerUndo(withTarget: self) { target in
                    target.titleStyle = oldValue
                }
                undoManager.setActionName("Change Title Style")
            }
            debouncedSave()
            updatePreview()
        }
    }

    var gutter: CGFloat = 0 {
        didSet {
            guard !isInitializing else { return }
            undoManager.registerUndo(withTarget: self) { target in
                target.gutter = oldValue
            }
            undoManager.setActionName("Change Gutter")
            debouncedSave()
            regenerateLayout()
        }
    }

    var scrollSensitivity: CGFloat = 1.6

    var backgroundColor: NSColor = .black {
        didSet {
            guard !isInitializing else { return }
            undoManager.registerUndo(withTarget: self) { target in
                target.backgroundColor = oldValue
            }
            undoManager.setActionName("Change Background Color")
            debouncedSave()
            updatePreview()
        }
    }

    var exportQuality: Double = 0.92 {
        didSet {
            guard !isInitializing else { return }
            undoManager.registerUndo(withTarget: self) { target in
                target.exportQuality = oldValue
            }
            undoManager.setActionName("Change Export Quality")
            debouncedSave()
        }
    }

    var backgroundStyle: BackgroundStyle = .solid {
        didSet {
            guard !isInitializing else { return }
            undoManager.registerUndo(withTarget: self) { target in
                target.backgroundStyle = oldValue
            }
            undoManager.setActionName("Change Background Style")
            debouncedSave()
            updatePreview()
        }
    }

    var gradientStartColor: NSColor = .black {
        didSet {
            guard !isInitializing else { return }
            undoManager.registerUndo(withTarget: self) { target in
                target.gradientStartColor = oldValue
            }
            undoManager.setActionName("Change Gradient Start Color")
            debouncedSave()
            updatePreview()
        }
    }

    var gradientEndColor: NSColor = .darkGray {
        didSet {
            guard !isInitializing else { return }
            undoManager.registerUndo(withTarget: self) { target in
                target.gradientEndColor = oldValue
            }
            undoManager.setActionName("Change Gradient End Color")
            debouncedSave()
            updatePreview()
        }
    }

    var gradientAngle: Double = 0 {
        didSet {
            guard !isInitializing else { return }
            undoManager.registerUndo(withTarget: self) { target in
                target.gradientAngle = oldValue
            }
            undoManager.setActionName("Change Gradient Angle")
            debouncedSave()
            updatePreview()
        }
    }

    var backgroundImage: NSImage? {
        didSet {
            guard !isInitializing else { return }
            undoManager.registerUndo(withTarget: self) { target in
                target.backgroundImage = oldValue
            }
            undoManager.setActionName("Change Background Image")
            if backgroundImage == nil {
                backgroundImagePath = nil
            }
            debouncedSave()
            updatePreview()
        }
    }
    var backgroundImagePath: String?
    var backgroundOpacity: Double = 1.0 {
        didSet {
            guard !isInitializing else { return }
            undoManager.registerUndo(withTarget: self) { target in
                target.backgroundOpacity = oldValue
            }
            undoManager.setActionName("Change Background Opacity")
            debouncedSave()
            updatePreview()
        }
    }

    /// Maps panel UUIDs to image indices for custom assignments.
    /// Intentionally NOT persisted — panel UUIDs change on every layout
    /// regeneration. The canonical persisted source is `customImageOrder`,
    /// which is used to rebuild panelAssignments in `regenerateLayout()`.
    var panelAssignments: [UUID: Int] = [:]

    var customImageOrder: [Int] = [] {
        didSet {
            guard !isInitializing else { return }
            debouncedSave()
        }
    }

    var previewImage: NSImage?
    var previewBackgroundImage: NSImage?
    var panelRenderedImages: [UUID: NSImage] = [:]
    var titleImage: NSImage?
    var isLiveGesturing: Bool = false
    var isProcessing: Bool = false
    var isExporting: Bool = false
    var isDraggingTitle: Bool = false
    var errorMessage: String?
    var exportSuccessMessage: String?

    func dismissExportSuccess() {
        exportSuccessMessage = nil
    }

    private func debouncedSave() {
        saveDebounceTask?.cancel()
        let persistence = self.persistence
        saveDebounceTask = Task { [weak self, persistence] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self else { return }
            do {
                try persistence.save(self)
            } catch {
                logger.error("Persistence save failed: \(error.localizedDescription, privacy: .public)")
                if !Task.isCancelled {
                    self.errorMessage = "Failed to save: \(error.localizedDescription)"
                }
            }
        }
    }

    convenience init() {
        self.init(
            saliencyAnalyzer: SaliencyAnalyzer(),
            assembler: CollageAssembler(),
            persistence: UserDefaultsPersistence()
        )
    }

    convenience init(
        saliencyAnalyzer: SaliencyAnalysis,
        assembler: CollageAssembly
    ) {
        self.init(
            saliencyAnalyzer: saliencyAnalyzer,
            assembler: assembler,
            persistence: UserDefaultsPersistence()
        )
    }

    init(
        saliencyAnalyzer: SaliencyAnalysis,
        assembler: CollageAssembly,
        persistence: UserDefaultsPersistence
    ) {
        self.saliencyAnalyzer = saliencyAnalyzer
        self.assembler = assembler
        self.persistence = persistence
        self.undoManager.levelsOfUndo = 60

        isInitializing = true
        let bundle = persistence.load()
        self.layoutStyle = bundle.layoutStyle
        self.titleAttrString = bundle.titleAttrString
        self.titleStyle = bundle.titleStyle
        self.gutter = bundle.gutter
        self.backgroundColor = bundle.backgroundColor
        self.exportQuality = bundle.exportQuality
        self.backgroundStyle = bundle.backgroundStyle
        self.gradientStartColor = bundle.gradientStartColor
        self.gradientEndColor = bundle.gradientEndColor
        self.gradientAngle = bundle.gradientAngle
        self.backgroundImagePath = bundle.backgroundImagePath
        self.backgroundImage = bundle.backgroundImage
        self.backgroundOpacity = bundle.backgroundOpacity
        self.customImageOrder = bundle.customImageOrder
        isInitializing = false
    }

    func setBackgroundImage(_ image: NSImage?, path: String?) {
        backgroundImagePath = path
        backgroundImage = image
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
                    guard let data = FileManager.default.contents(atPath: url.path) else { return nil }

                    let imagePair = await MainActor.run { () -> (NSImage, CGImage)? in
                        guard let nsImage = NSImage(data: data),
                              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                            return nil
                        }
                        return (nsImage, cgImage)
                    }
                    guard let (nsImage, cgImage) = imagePair else { return nil }

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
        cropManager.cropMap.removeAll()
        saliencyResults.removeAll()
        selectedPanelId = nil
        previewImage = nil
        previewBackgroundImage = nil
        panelRenderedImages.removeAll()
        titleImage = nil
        isProcessing = false
        errorMessage = nil
        panelAssignments.removeAll()
        customImageOrder.removeAll()
        backgroundImage = nil
    }

    // MARK: - Layout

    func regenerateLayout() {
        guard !images.isEmpty else { return }

        let layoutStart = ContinuousClock.now
        defer { perfLogger.debug("Layout Regeneration completed in \(ContinuousClock.now - layoutStart)") }

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

        panelRenderedImages.removeAll()
        updatePreview()
        updateAllPanelPreviews()
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
        updatePanelPreview(panelId: panelId)
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
        }

        updatePreview()
        updatePanelPreview(panelId: sourceId)
        updatePanelPreview(panelId: targetId)
    }

    // MARK: - Saliency

    func analyzeSaliency() async {
        guard !images.isEmpty else { return }
        logger.info("Saliency analysis started for \(self.images.count) image(s)")
        isProcessing = true
        defer { isProcessing = false }

        do {
            let saliencyStart = ContinuousClock.now
            defer { perfLogger.debug("Saliency Analysis completed in \(ContinuousClock.now - saliencyStart)") }
            let results = try await saliencyAnalyzer.analyzeAll(images.map { $0.cgImage })
            var indexed: [Int: SaliencyResult] = [:]
            for (i, result) in results.enumerated() {
                indexed[i] = result
            }
            logger.info("Saliency analysis complete: \(indexed.count) result(s)")
            saliencyResults = indexed
            cropManager.computeCropsFromSaliency(
                panels: panels,
                images: images,
                results: indexed
            )
            updatePreview()
            updateAllPanelPreviews()
        } catch {
            logger.error("Saliency analysis failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
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
        updatePreview()
    }

    func applyPanLive() {
        let panStart = ContinuousClock.now
        defer { perfLogger.debug("Pan Application completed in \(ContinuousClock.now - panStart)") }

        cropManager.applyPan(panelId: nil, panels: panels, images: images, panelAssignments: panelAssignments, finish: false)

        previewDebounceTask?.cancel()
        previewDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            if let panelId = self?.cropManager.activePanelId {
                self?.updatePanelPreview(panelId: panelId)
            }
        }
    }

    func beginPinch(panelId: UUID) {
        cropManager.beginPinch(panelId: panelId)
    }

    func pinch(magnification: CGFloat) {
        cropManager.pinch(magnification: magnification)
    }

    func applyPinch(panelId: UUID?) {
        cropManager.applyPinch(panelId: panelId, panels: panels, images: images, panelAssignments: panelAssignments, finish: true)
        updatePreview()
    }

    func applyPinchLive() {
        cropManager.applyPinch(panelId: nil, panels: panels, images: images, panelAssignments: panelAssignments, finish: false)

        panelPreviewTask?.cancel()
        panelPreviewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            if let panelId = self?.cropManager.activePanelId {
                self?.updatePanelPreview(panelId: panelId)
            }
        }
    }

    func resetCrop(panelId: UUID) {
        logger.info("Reset crop for panel")
        if let oldCrop = cropMap[panelId] {
            undoManager.registerUndo(withTarget: self) { target in
                target.cropMap[panelId] = oldCrop
                target.updatePreview()
            }
            undoManager.setActionName("Reset Crop")
        }
        cropManager.resetCrop(panelId: panelId, panels: panels, images: images, panelAssignments: panelAssignments)
        updatePreview()
        updatePanelPreview(panelId: panelId)
    }

    // MARK: - Overlay Crop (Panel Editor drag/resize)

    func beginOverlayCropUndo(panelId: UUID) {
        guard let oldCrop = cropMap[panelId] else { return }
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { target in
            target.cropMap[panelId] = oldCrop
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
        cropManager.cropMap[panelId] = newCrop
        updatePreview()
        updatePanelPreview(panelId: panelId)
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

                previewDebounceTask?.cancel()
                previewDebounceTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    if let panelId = self?.scrollPanManager.activePanelId {
                        self?.updatePanelPreview(panelId: panelId)
                    }
                }
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
                updatePreview()
            }
        )
    }

    func endScrollPan() {
        scrollPanManager.endScrollPan()
    }

    // MARK: - Config

    private func buildAssemblyConfig() -> AssemblyConfig {
        AssemblyConfig(
            panels: panels,
            crops: cropMap,
            panelAssignments: panelAssignments,
            titleAttrString: titleAttrString,
            titleStyle: titleStyle,
            backgroundColor: backgroundColor,
            backgroundStyle: backgroundStyle,
            gradientStartColor: gradientStartColor,
            gradientEndColor: gradientEndColor,
            gradientAngle: gradientAngle,
            backgroundOpacity: backgroundOpacity,
            canvasSize: CanvasConfig.defaultCanvasSize
        )
    }

    // MARK: - Preview & Export

    private var previewTask: Task<Void, Never>?
    private var previewDebounceTask: Task<Void, Never>?
    private var panelPreviewTask: Task<Void, Never>?
    private var backgroundTask: Task<Void, Never>?
    private var titleTask: Task<Void, Never>?

    func updatePanelPreview(panelId: UUID) {
        guard let panel = panels.first(where: { $0.id == panelId }),
              let crop = cropMap[panelId] else { return }

        let effectiveIndex = panelAssignments[panelId] ?? panel.imageIndex
        guard effectiveIndex < images.count else { return }

        let cgImage = images[effectiveIndex].cgImage
        let panelSize = panel.frame.size
        let assembler = self.assembler

        panelPreviewTask?.cancel()
        panelPreviewTask = Task.detached { [weak self, cgImage, crop, panelSize, assembler] in
            guard let self else { return }
            let result = assembler.renderPanel(
                crop: crop,
                cgImage: cgImage,
                panelSize: panelSize
            )
            Task { @MainActor in
                self.panelRenderedImages[panelId] = result
            }
        }
    }

    func updateBackground() {
        let bgConfig = BackgroundConfig(
            style: backgroundStyle,
            color: backgroundColor,
            gradientStartColor: gradientStartColor,
            gradientEndColor: gradientEndColor,
            gradientAngle: gradientAngle,
            opacity: backgroundOpacity
        )
        let backgroundImageCG = backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let assembler = self.assembler

        backgroundTask?.cancel()
        backgroundTask = Task.detached { [weak self, bgConfig, backgroundImageCG, assembler] in
            guard let self else { return }
            let result = assembler.renderBackground(
                config: bgConfig,
                canvasSize: CanvasConfig.defaultCanvasSize,
                backgroundImage: backgroundImageCG,
                previewSize: CanvasConfig.defaultPreviewSize
            )
            Task { @MainActor in
                self.previewBackgroundImage = result
            }
        }
    }

    func updatePreview() {
        guard !panels.isEmpty else { return }

        let previewStart = ContinuousClock.now
        defer { perfLogger.debug("Preview Assembly completed in \(ContinuousClock.now - previewStart)") }

        let config = buildAssemblyConfig()
        let cgImages = images.map { $0.cgImage }
        let backgroundImageCG = backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let assembler = assembler

        previewTask?.cancel()
        previewTask = Task.detached { [weak self, config, cgImages, backgroundImageCG, assembler] in
            guard let self else { return }
            let result = assembler.assemblePreviewWithCGImages(
                config: config,
                cgImages: cgImages,
                backgroundImage: backgroundImageCG,
                previewSize: CanvasConfig.defaultPreviewSize
            )
            Task { @MainActor in
                self.previewImage = result
            }
        }

        updateBackground()
        updateTitleImage()
    }

    func updateAllPanelPreviews() {
        for panel in panels {
            updatePanelPreview(panelId: panel.id)
        }
    }

    func updateTitleImage() {
        let titleAttrString = self.titleAttrString
        let titleStyle = self.titleStyle
        let canvasSize = CanvasConfig.defaultCanvasSize
        let assembler = self.assembler

        titleTask?.cancel()
        titleTask = Task.detached { [weak self, titleAttrString, titleStyle, canvasSize, assembler] in
            guard let self else { return }
            let result = assembler.renderTitle(
                titleAttrString: titleAttrString,
                titleStyle: titleStyle,
                canvasSize: canvasSize
            )
            Task { @MainActor in
                self.titleImage = result
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

        if let folderPath = UserDefaults.standard.string(forKey: UserDefaultsPersistence.Keys.defaultExportFolder),
           let folderUrl = URL(string: folderPath), folderUrl.folderExists {
            savePanel.directoryURL = folderUrl
        }

        let response = NSApplication.shared.runModal(for: savePanel)
        guard response == .OK, let url = savePanel.url else { return nil }
        logger.info("Export to \(url.lastPathComponent, privacy: .public)")

        UserDefaults.standard.set(url.deletingLastPathComponent().path, forKey: UserDefaultsPersistence.Keys.defaultExportFolder)

        let config = self.buildAssemblyConfig()
        let cgImages = self.images.map { $0.cgImage }
        let backgroundImageCG = self.backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let quality = self.exportQuality
        let assembler = self.assembler

        exportTask = Task.detached { [assembler, config, cgImages, backgroundImageCG, quality, url] in
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
