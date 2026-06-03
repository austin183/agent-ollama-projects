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
    private let assembler: any CollageAssembly
    private let persistence: UserDefaultsPersistence
    let cropManager = CropManager()
    let previewManager: PreviewManager
    let undoManager = UndoManager()
    let imageLibrary = ImageLibraryManager()
    private var isInitializing = false
    private var saliencyResults: [Int: SaliencyResult] = [:]
    private var saveDebounceTask: Task<Void, Never>?
    private var cropMapVersion = 0
    private var titleImageVersion = 0

    /// Cached CoreText bounds — only recomputed when layout-affecting properties change.
    /// Wrapped in a reference type so tests can verify cache hits via identity comparison.
    final class TitleBoundsCache {
        let bounds: TitleBoundsCT
        init(_ bounds: TitleBoundsCT) { self.bounds = bounds }
    }
    var cachedTitleBounds: TitleBoundsCache? = nil
    private var cachedTitleLayoutKey: TitleStyle.LayoutKey? = nil
    private var cachedTitleString: NSAttributedString?

    private func ensureTitleBounds() -> TitleBoundsCache? {
        guard !titleAttrString.string.isEmpty else {
            cachedTitleBounds = nil
            cachedTitleString = nil
            cachedTitleLayoutKey = nil
            return nil
        }
        let currentKey = titleStyle.layoutKey
        if let cachedBounds = cachedTitleBounds,
           let cachedStr = cachedTitleString, cachedStr.isEqual(titleAttrString),
           cachedTitleLayoutKey == currentKey {
            return cachedBounds
        }
        cachedTitleString = titleAttrString
        let textData = TitleTextData.extract(from: titleAttrString)
        let bounds = TitleBoundsCT.compute(textData: textData, style: titleStyle)
        cachedTitleBounds = TitleBoundsCache(bounds)
        cachedTitleLayoutKey = currentKey
        return cachedTitleBounds
    }

    /// Cached title canvas frame — uses cached CoreText bounds + cheap CGRect math.
    var cachedTitleCanvasFrame: CGRect? {
        guard let cache = ensureTitleBounds() else { return nil }
        let bounds = cache.bounds
        let canvasSize = CanvasConfig.defaultCanvasSize
        let boundingBox = bounds.boundingBox(canvasWidth: canvasSize.width)
        let drawWidth = titleStyle.effectiveWidth(canvasWidth: canvasSize.width)
        let anchorX = titleStyle.positionX * canvasSize.width
        let drawX = anchorX - drawWidth / 2
        let anchorYcg = canvasSize.height - titleStyle.positionY * canvasSize.height
        let baselineY = anchorYcg - boundingBox.height
        let textTop = baselineY + boundingBox.origin.y
        return CGRect(x: drawX, y: textTop - 12, width: drawWidth, height: boundingBox.height + 24)
    }

    /// Cached title minimum natural width — uses cached CoreText bounds.
    var cachedTitleMinWidth: CGFloat {
        guard let cache = ensureTitleBounds() else { return 0 }
        let bounds = cache.bounds
        let canvasSize = CanvasConfig.defaultCanvasSize
        return bounds.minNaturalWidth(canvasWidth: canvasSize.width)
    }

    var exportManager: ExportManager = ExportManager(assembler: CollageAssembler())

    var images: [ImageItem] { imageLibrary.images }
    var customImageOrder: [Int] {
        get { imageLibrary.customImageOrder }
        set {
            guard !isInitializing else { return }
            imageLibrary.customImageOrder = newValue
            debouncedSave()
        }
    }
    var panels: [ImagePanel] = []
    var selectedPanelId: UUID?

    /// Single source of truth for crop state — delegated to CropManager.
    /// The version counter establishes @Observable dependency so in-place
    /// cropMap mutations fire change signals to views.
    var cropMap: [UUID: CropInfo] {
        get {
            let _ = cropMapVersion
            return cropManager.cropMap
        }
        set { cropManager.cropMap = newValue }
    }

    private func notifyCropMapChanged() {
        cropMapVersion += 1
    }

    /// Throttled notification — fires at most every ~30ms (~33fps) so the view
    /// updates during active gestures without re-evaluating on every frame.
    private var lastCropNotifyTime: ContinuousClock.Instant = ContinuousClock.now
    private let cropNotifyInterval: Duration = .milliseconds(30)

    private func throttledNotifyCropMapChanged() {
        let now = ContinuousClock.now
        if now - lastCropNotifyTime >= cropNotifyInterval {
            lastCropNotifyTime = now
            notifyCropMapChanged()
        }
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
            guard !oldValue.isEqual(titleAttrString) else { return }
            guard !isInitializing else { return }
            undoManager.registerUndo(withTarget: self) { target in
                target.titleAttrString = oldValue
            }
            undoManager.setActionName("Edit Title")
            debouncedSave()
            if isLayeredMode {
                updateTitleImage()
            } else {
                updatePreview()
            }
        }
    }

    var title: String {
        titleAttrString.string
    }

    var titleStyle: TitleStyle = .default {
        didSet {
            guard !isInitializing else { return }
            if isDraggingTitle {
                updateTitleImageLive()
                return
            }
            undoManager.registerUndo(withTarget: self) { target in
                target.titleStyle = oldValue
            }
            undoManager.setActionName("Change Title Style")
            if isLayeredMode {
                updateTitleImage()
            } else {
                updatePreview()
            }
            debouncedSave()
        }
    }

    var gutter: CGFloat = 0 {
        didSet {
            guard !isInitializing else { return }
            gutterDidChange(oldValue: oldValue)
        }
    }

    private func gutterDidChange(oldValue: CGFloat) {
        gutterDebounceTask?.cancel()
        gutterDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self else { return }
            undoManager.registerUndo(withTarget: self) { target in
                target.gutter = oldValue
            }
            undoManager.setActionName("Change Gutter")
            debouncedSave()
            regenerateLayout(preserveCrops: true)
        }
    }

    var scrollSensitivity: CGFloat = 1.6
    private var scrollCommitTimer: DispatchWorkItem?

    var backgroundColor: NSColor = .black {
        didSet {
            guard !isInitializing else { return }
            undoManager.registerUndo(withTarget: self) { target in
                target.backgroundColor = oldValue
            }
            undoManager.setActionName("Change Background Color")
            debouncedSave()
            updatePreviewDebounced()
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
            updatePreviewDebounced()
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
            updatePreviewDebounced()
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
            updatePreviewDebounced()
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
            updatePreviewDebounced()
        }
    }

    /// Maps panel UUIDs to image indices for custom assignments.
    /// Intentionally NOT persisted — panel UUIDs change on every layout
    /// regeneration. The canonical persisted source is `customImageOrder`,
    /// which is used to rebuild panelAssignments in `regenerateLayout()`.
    var panelAssignments: [UUID: Int] = [:]

    var previewImage: NSImage? {
        get { previewManager.previewImage }
        set { previewManager.previewImage = newValue }
    }
    var previewBackgroundImage: NSImage? {
        get { previewManager.previewBackgroundImage }
        set { previewManager.previewBackgroundImage = newValue }
    }
    var panelRenderedImages: [UUID: NSImage] {
        get { previewManager.panelRenderedImages }
        set { previewManager.panelRenderedImages = newValue }
    }
    var titleImage: NSImage? {
        get {
            let _ = titleImageVersion
            return previewManager.titleImage
        }
        set { previewManager.titleImage = newValue }
    }
    var isLayeredMode: Bool = false
    var isLiveGesturing: Bool = false
    var isProcessing: Bool = false
    var isExporting: Bool { exportManager.isExporting }
    var isDraggingTitle: Bool = false
    var errorMessage: String?
    var exportSuccessMessage: String? { exportManager.successMessage }

    func dismissExportSuccess() {
        exportManager.dismissSuccess()
    }

    private func debouncedSave() {
        saveDebounceTask?.cancel()
        let persistence = self.persistence
        saveDebounceTask = Task { [weak self, persistence] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self else { return }
            persistence.save(self)
        }
    }

    convenience init() {
        let assembler = CollageAssembler()
        self.init(
            saliencyAnalyzer: SaliencyAnalyzer(),
            assembler: assembler,
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
        self.previewManager = PreviewManager(assembler: assembler)
        self.exportManager = ExportManager(assembler: assembler)
        self.undoManager.levelsOfUndo = 60

        imageLibrary.onImagesChanged = { [weak self] in
            self?.regenerateLayout()
        }

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
        imageLibrary.customImageOrder = bundle.customImageOrder
        isInitializing = false
    }

    func setBackgroundImage(_ image: NSImage?, path: String?) {
        backgroundImagePath = path
        backgroundImage = image
    }

    // MARK: - Image Loading

    func browseImages() {
        imageLibrary.browseImages()
    }

    func addImages(from urls: [URL]) async {
        await imageLibrary.addImages(from: urls)
        if !images.isEmpty && !isProcessing {
            Task { [weak self] in
                await self?.analyzeSaliency()
            }
        }
    }

    func removeImage(at index: Int) {
        guard let (removed, at) = imageLibrary.removeImage(at: index) else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.imageLibrary.images.insert(removed, at: at)
            target.regenerateLayout()
        }
        undoManager.setActionName("Remove Image")

        Task { [weak self] in
            await self?.analyzeSaliency()
        }
    }

    func moveImages(from: IndexSet, to: Int) {
        let oldCustomOrder = customImageOrder
        imageLibrary.moveImages(from: from, to: to)
        panelAssignments.removeAll()
        undoManager.registerUndo(withTarget: self) { target in
            target.customImageOrder = oldCustomOrder
            target.regenerateLayout()
        }
        undoManager.setActionName("Reorder Images")

        Task { [weak self] in
            await self?.analyzeSaliency()
        }
    }

    func clearAll() {
        guard !images.isEmpty else { return }
        logger.info("Clear all images")
        let oldPanels = panels, oldCropMap = cropMap
        let oldImages = imageLibrary.clearAll()
        undoManager.registerUndo(withTarget: self) { target in
            target.imageLibrary.images = oldImages
            target.panels = oldPanels
            target.cropMap = oldCropMap
            target.backgroundImage = nil
            target.regenerateLayout()
        }
        undoManager.setActionName("Clear All")
        exportManager.exportTask?.cancel()
        panels.removeAll()
        cropManager.cropMap.removeAll()
        saliencyResults.removeAll()
        selectedPanelId = nil
        previewManager.clearAll()
        isProcessing = false
        errorMessage = nil
        panelAssignments.removeAll()
        backgroundImage = nil
    }

    // MARK: - Layout

    func regenerateLayout(preserveCrops: Bool = false) {
        previewRenderDebounceTask?.cancel()
        guard !images.isEmpty else { return }

        let layoutStart = ContinuousClock.now
        defer { perfLogger.debug("Layout Regeneration completed in \(ContinuousClock.now - layoutStart)") }

        if customImageOrder.isEmpty || customImageOrder.count != images.count {
            customImageOrder = Array(0..<images.count)
        }

        let oldCropsBySlot = preserveCrops ? cropManager.cropsBySlot(panels) : nil
        let oldRenderedBySlot = preserveCrops ? previewManager.panelRenderedImagesBySlot(panels) : nil
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

        if preserveCrops, let oldCropsBySlot, let oldRenderedBySlot {
            cropManager.applyCropsBySlot(oldCropsBySlot, panels: panels)
            previewManager.applyRenderedBySlot(oldRenderedBySlot, panels: panels)
        } else {
            previewManager.panelRenderedImages.removeAll()
            if saliencyResults.isEmpty {
                cropManager.computeInitialCrops(panels: panels, images: images)
            } else {
                cropManager.computeCropsFromSaliency(
                    panels: panels,
                    images: images,
                    results: saliencyResults
                )
            }
        }

        isLayeredMode = false
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
            previewRenderDebounceTask?.cancel()
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
        if let panelId {
            updatePanelPreview(panelId: panelId)
        }
    }

    func applyPanLive() {
        let panStart = ContinuousClock.now
        defer { perfLogger.debug("Pan Application completed in \(ContinuousClock.now - panStart)") }

        cropManager.applyPan(panelId: nil, panels: panels, images: images, panelAssignments: panelAssignments, finish: false)
        throttledNotifyCropMapChanged()

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
        if let panelId {
            updatePanelPreview(panelId: panelId)
            notifyCropMapChanged()
        }
    }

    func applyPinchLive() {
        cropManager.applyPinch(panelId: nil, panels: panels, images: images, panelAssignments: panelAssignments, finish: false)
        throttledNotifyCropMapChanged()

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
                target.updatePanelPreview(panelId: panelId)
            }
            undoManager.setActionName("Reset Crop")
        }
        cropManager.resetCrop(panelId: panelId, panels: panels, images: images, panelAssignments: panelAssignments)
        updatePanelPreview(panelId: panelId)
    }

    // MARK: - Overlay Crop (Panel Editor drag/resize)

    func beginOverlayCropUndo(panelId: UUID) {
        guard let oldCrop = cropMap[panelId] else { return }
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { target in
            target.cropMap[panelId] = oldCrop
            target.updatePanelPreview(panelId: panelId)
        }
    }

    func endOverlayCropUndo() {
        undoManager.setActionName("Adjust Crop")
        undoManager.endUndoGrouping()
    }

    func applyOverlayCropLive(panelId: UUID, sourceRect: CGRect) {
        guard let crop = cropMap[panelId] else { return }
        let newCrop = CropInfo(
            panelId: panelId,
            sourceRect: sourceRect,
            destinationRect: crop.destinationRect
        )
        cropManager.cropMap[panelId] = newCrop
        throttledNotifyCropMapChanged()

        panelPreviewTask?.cancel()
        panelPreviewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self?.updatePanelPreview(panelId: panelId)
        }
    }

    func finishOverlayCrop(panelId: UUID) {
        panelPreviewTask?.cancel()
        updatePanelPreview(panelId: panelId)
        notifyCropMapChanged()
    }

    func applyOverlayCrop(panelId: UUID, sourceRect: CGRect) {
        applyOverlayCropLive(panelId: panelId, sourceRect: sourceRect)
        finishOverlayCrop(panelId: panelId)
    }

    // MARK: - Scroll Pan (delegated to CropManager)

    func beginScrollPan(panelId: UUID) {
        cropManager.beginScrollPan(panelId: panelId)
    }

    func scrollPanDelta(_ delta: CGSize) {
        cropManager.scrollPanAccumulateDelta(delta, sensitivity: scrollSensitivity)
        cropManager.scrollPanApply(
            panels: panels,
            images: images,
            panelAssignments: panelAssignments,
            finish: false
        )
        throttledNotifyCropMapChanged()

        previewDebounceTask?.cancel()
        previewDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            if let panelId = self?.cropManager.scrollPanActivePanelId {
                self?.updatePanelPreview(panelId: panelId)
            }
        }

        scheduleScrollPanCommit()
    }

    private func scheduleScrollPanCommit() {
        scrollCommitTimer?.cancel()
        scrollCommitTimer = DispatchWorkItem { [weak self] in
            guard let self, let id = self.cropManager.scrollPanActivePanelId else { return }
            self.cropManager.scrollPanApply(
                panels: self.panels,
                images: self.images,
                panelAssignments: self.panelAssignments,
                finish: true
            )
            self.cropManager.beginPan(panelId: id)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: scrollCommitTimer!)
    }

    func endScrollPan() {
        scrollCommitTimer?.cancel()
        scrollCommitTimer = nil
        cropManager.endScrollPan()
        notifyCropMapChanged()
    }

    // MARK: - Config

    func buildAssemblyConfig() -> AssemblyConfig {
        let textData = TitleTextData.extract(from: titleAttrString)
        let fontColor = titleStyle.fontColor.cgColor
        let titleBgColor = titleStyle.backgroundColor.cgColor
        return AssemblyConfig(
            panels: panels,
            crops: cropMap,
            panelAssignments: panelAssignments,
            titleTextData: textData,
            titleStyle: titleStyle,
            titleFontColor: fontColor,
            titleBackgroundColor: titleBgColor,
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

    private var previewDebounceTask: Task<Void, Never>?
    private var previewRenderDebounceTask: Task<Void, Never>?
    private var panelPreviewTask: Task<Void, Never>?
    private var titleDebounceTask: Task<Void, Never>?
    private var fontSizeDebounceTask: Task<Void, Never>?
    private var gutterDebounceTask: Task<Void, Never>?

    func updatePanelPreview(panelId: UUID) {
        guard let panel = panels.first(where: { $0.id == panelId }),
              let crop = cropMap[panelId] else { return }

        let effectiveIndex = panelAssignments[panelId] ?? panel.imageIndex
        guard effectiveIndex < images.count else { return }

        let cgImage = images[effectiveIndex].cgImage
        let panelSize = panel.frame.size

        previewManager.updatePanelPreview(
            crop: crop,
            cgImage: cgImage,
            panelSize: panelSize,
            panelId: panelId
        )
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

        previewManager.updateBackground(
            config: bgConfig,
            canvasSize: CanvasConfig.defaultCanvasSize,
            backgroundImage: backgroundImageCG,
            previewSize: CanvasConfig.defaultPreviewSize
        )
    }

    func updatePreviewDebounced() {
        previewRenderDebounceTask?.cancel()
        previewRenderDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self?.updatePreview()
        }
    }

    func updatePreview() {
        guard !panels.isEmpty else { return }

        let previewStart = ContinuousClock.now
        defer { perfLogger.debug("Preview Assembly completed in \(ContinuousClock.now - previewStart)") }

        let config = buildAssemblyConfig()
        let cgImages = images.map { $0.cgImage }
        let backgroundImageCG = backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)

        previewManager.updatePreview(
            config: config,
            cgImages: cgImages,
            backgroundImage: backgroundImageCG,
            previewSize: CanvasConfig.defaultPreviewSize
        )

        if isLayeredMode {
            updateBackground()
            updateTitleImage()
        }
    }

    func updateAllPanelPreviews() {
        isLayeredMode = true
        previewManager.updateAllPanelPreviews(
            panels: panels,
            crops: cropMap,
            images: images,
            panelAssignments: panelAssignments
        )
        updateBackground()
        updateTitleImage()
    }

    func updateTitleImage() {
        titleImageVersion += 1
        previewManager.updateTitleImage(
            titleAttrString: titleAttrString,
            titleStyle: titleStyle,
            canvasSize: CanvasConfig.defaultCanvasSize
        )
    }

    func updateTitleImageLive() {
        titleDebounceTask?.cancel()
        titleDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self?.updateTitleImage()
        }
    }

    func finishTitleDrag() {
        titleDebounceTask?.cancel()
        updateTitleImage()
        debouncedSave()
    }

    func setTitleFontFamily(_ family: String) {
        guard !isInitializing else { return }
        let oldValue = titleStyle.fontFamily
        titleStyle.fontFamily = family
        undoManager.registerUndo(withTarget: self) { target in
            target.setTitleFontFamily(oldValue)
        }
        undoManager.setActionName("Change Font Family")
        updateTitleImageLive()
        debouncedSave()
    }

    func setTitleFontSize(_ size: CGFloat) {
        guard !isInitializing else { return }
        let oldValue = titleStyle.fontSize
        titleStyle.fontSize = size
        undoManager.registerUndo(withTarget: self) { target in
            target.setTitleFontSize(oldValue)
        }
        undoManager.setActionName("Change Font Size")
        fontSizeDebounceTask?.cancel()
        fontSizeDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self?.updateTitleImage()
        }
        debouncedSave()
    }

    func setTitleBackgroundColor(_ color: NSColor) {
        guard !isInitializing else { return }
        let oldValue = titleStyle.backgroundColor
        titleStyle.backgroundColor = color
        undoManager.registerUndo(withTarget: self) { target in
            target.setTitleBackgroundColor(oldValue)
        }
        undoManager.setActionName("Change Title BG Color")
        if isLayeredMode {
            updateTitleImage()
        } else {
            updatePreview()
        }
        debouncedSave()
    }

    func setTitleFontColor(_ color: NSColor) {
        guard !isInitializing else { return }
        let oldValue = titleStyle.fontColor
        titleStyle.fontColor = color
        undoManager.registerUndo(withTarget: self) { target in
            target.setTitleFontColor(oldValue)
        }
        undoManager.setActionName("Change Title Color")
        if isLayeredMode {
            updateTitleImage()
        } else {
            updatePreview()
        }
        debouncedSave()
    }

    func setTitleAlignment(_ alignment: NSTextAlignment) {
        guard !isInitializing else { return }
        let oldValue = titleStyle.alignment
        titleStyle.alignment = alignment
        undoManager.registerUndo(withTarget: self) { target in
            target.setTitleAlignment(oldValue)
        }
        undoManager.setActionName("Change Title Alignment")
        if isLayeredMode {
            updateTitleImage()
        } else {
            updatePreview()
        }
        debouncedSave()
    }

    func setTitleShowBackground(_ show: Bool) {
        guard !isInitializing else { return }
        let oldValue = titleStyle.showBackground
        titleStyle.showBackground = show
        undoManager.registerUndo(withTarget: self) { target in
            target.setTitleShowBackground(oldValue)
        }
        undoManager.setActionName("Toggle Title BG")
        if isLayeredMode {
            updateTitleImage()
        } else {
            updatePreview()
        }
        debouncedSave()
    }

    func exportCollage() async -> URL? {
        await exportManager.export(viewModel: self)
    }

    /// Yields to let pending async tasks complete.
    /// Used by tests to synchronize with debounced rendering work.
    func awaitPendingTasks() async {
        await previewManager.awaitPendingTasks()
    }
}

extension URL {
    var folderExists: Bool {
        FileManager.default.fileExists(atPath: deletingLastPathComponent().path)
    }
}
