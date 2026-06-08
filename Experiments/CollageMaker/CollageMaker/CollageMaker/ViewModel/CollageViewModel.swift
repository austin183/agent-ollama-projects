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
    private let debouncer = Debouncer()
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
        let canvasSize = SizeConstants.defaultCanvasSize
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
        let canvasSize = SizeConstants.defaultCanvasSize
        return bounds.minNaturalWidth(canvasWidth: canvasSize.width)
    }

    var exportManager: ExportManager!

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
    /// Scroll pan uses a slower 60ms interval since users are moving through
    /// content rapidly and 16fps is visually indistinguishable.
    private var lastCropNotifyTime: ContinuousClock.Instant = ContinuousClock.now
    private let cropNotifyInterval: Duration = .milliseconds(30)
    private let scrollCropNotifyInterval: Duration = .milliseconds(60)

    private func throttledNotifyCropMapChanged(forScrollPan: Bool = false) {
        let interval = forScrollPan ? scrollCropNotifyInterval : cropNotifyInterval
        let now = ContinuousClock.now
        if now - lastCropNotifyTime >= interval {
            lastCropNotifyTime = now
            notifyCropMapChanged()
        }
    }

    var layoutStyle: LayoutStyle = .hero {
        didSet {
            registerUndo(oldValue: oldValue, actionName: "Change Layout") { $0.layoutStyle = oldValue }
            logger.info("Layout style changed to \(self.layoutStyle.rawValue, privacy: .public)")
            regenerateLayout()
        }
    }

    // Style-specific configuration
    var doubleExposureMaskImage: NSImage? {
        didSet {
            guard !isInitializing else { return }
            registerUndo(oldValue: oldValue, actionName: "Change Mask Image") { $0.doubleExposureMaskImage = oldValue }
            if doubleExposureMaskImage == nil {
                doubleExposureMaskImagePath = nil
            }
            updatePreview()
        }
    }
    var doubleExposureMaskImagePath: String?
    var doubleExposureMaskOpacity: CGFloat = 0.5 {
        didSet {
            guard !isInitializing else { return }
            registerUndo(oldValue: oldValue, actionName: "Change Mask Opacity") { $0.doubleExposureMaskOpacity = oldValue }
            updatePreviewDebounced()
        }
    }
    var diagonalSliceAngle: CGFloat = 45.0 {
        didSet {
            guard !isInitializing else { return }
            registerUndo(oldValue: oldValue, actionName: "Change Slice Angle") { $0.diagonalSliceAngle = oldValue }
            if layoutStyle == .diagonalSlices {
                regenerateLayout(preserveCrops: false)
            }
        }
    }
    var hexagonalSpacing: CGFloat = 8.0 {
        didSet {
            guard !isInitializing else { return }
            registerUndo(oldValue: oldValue, actionName: "Change Hex Spacing") { $0.hexagonalSpacing = oldValue }
            if layoutStyle == .hexagonal {
                regenerateLayout(preserveCrops: false)
            }
        }
    }

    var titleAttrString: NSAttributedString = NSAttributedString(string: "") {
        didSet {
            guard !oldValue.isEqual(titleAttrString) else { return }
            registerUndo(oldValue: oldValue, actionName: "Edit Title") { $0.titleAttrString = oldValue }
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
            registerUndo(oldValue: oldValue, actionName: "Change Title Style") { $0.titleStyle = oldValue }
            if isLayeredMode {
                updateTitleImage()
            } else {
                updatePreview()
            }
        }
    }

    var gutter: CGFloat = 0 {
        didSet {
            guard !isInitializing else { return }
            gutterDidChange(oldValue: oldValue)
        }
    }

    private func gutterDidChange(oldValue: CGFloat) {
        debouncer.debounce(id: "gutter", delay: .milliseconds(150)) { [weak self] in
            guard let self else { return }
            self.undoManager.registerUndo(withTarget: self) { target in
                target.gutter = oldValue
            }
            self.undoManager.setActionName("Change Gutter")
            self.debouncedSave()
            self.regenerateLayout(preserveCrops: true)
        }
    }

    var scrollSensitivity: CGFloat = 1.6

    var backgroundColor: NSColor = .black {
        didSet {
            guard !isInitializing else { return }
            backgroundColorDidChange(oldValue: oldValue)
        }
    }

    private func backgroundColorDidChange(oldValue: NSColor) {
        debouncer.debounce(id: "backgroundColor", delay: .milliseconds(150)) { [weak self] in
            guard let self else { return }
            self.undoManager.registerUndo(withTarget: self) { target in
                target.backgroundColor = oldValue
            }
            self.undoManager.setActionName("Change Background Color")
            self.debouncedSave()
            self.updatePreview()
        }
    }

    var exportQuality: Double = 0.92 {
        didSet {
            registerUndo(oldValue: oldValue, actionName: "Change Export Quality") { $0.exportQuality = oldValue }
        }
    }

    var backgroundStyle: BackgroundStyle = .solid {
        didSet {
            registerUndo(oldValue: oldValue, actionName: "Change Background Style") { $0.backgroundStyle = oldValue }
            updatePreview()
        }
    }

    var gradientStartColor: NSColor = .black {
        didSet {
            registerUndo(oldValue: oldValue, actionName: "Change Gradient Start Color") { $0.gradientStartColor = oldValue }
            updatePreviewDebounced()
        }
    }

    var gradientEndColor: NSColor = .darkGray {
        didSet {
            registerUndo(oldValue: oldValue, actionName: "Change Gradient End Color") { $0.gradientEndColor = oldValue }
            updatePreviewDebounced()
        }
    }

    var gradientAngle: Double = 0 {
        didSet {
            registerUndo(oldValue: oldValue, actionName: "Change Gradient Angle") { $0.gradientAngle = oldValue }
            updatePreviewDebounced()
        }
    }

    var backgroundImage: NSImage? {
        didSet {
            registerUndo(oldValue: oldValue, actionName: "Change Background Image") { $0.backgroundImage = oldValue }
            if backgroundImage == nil {
                backgroundImagePath = nil
            }
            updatePreview()
        }
    }
    var backgroundImagePath: String?
    var backgroundOpacity: Double = 1.0 {
        didSet {
            registerUndo(oldValue: oldValue, actionName: "Change Background Opacity") { $0.backgroundOpacity = oldValue }
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
    var overlayImage: NSImage? {
        get { previewManager.overlayImage }
        set { previewManager.overlayImage = newValue }
    }
    var overlayBlendMode: CGBlendMode? {
        get { previewManager.overlayBlendMode }
        set { previewManager.overlayBlendMode = newValue }
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
    private var processingCount = 0
    var isProcessing: Bool { processingCount > 0 }

    func beginProcessing() { processingCount += 1 }
    func endProcessing() { processingCount = max(0, processingCount - 1) }
    var isExporting: Bool { exportManager.isExporting }
    var isDraggingTitle: Bool = false
    var errorMessage: String?
    var exportSuccessMessage: String? { exportManager.successMessage }

    func dismissExportSuccess() {
        exportManager.dismissSuccess()
    }

    private func debouncedSave() {
        debouncer.debounce(id: "save", delay: .milliseconds(300)) { [weak self] in
            guard let self else { return }
            self.persistence.save(self)
        }
    }

    private func registerUndo<Value>(oldValue: Value, actionName: String, restore: @escaping (CollageViewModel) -> Void) {
        guard !isInitializing else { return }
        undoManager.registerUndo(withTarget: self) { target in
            restore(target)
        }
        undoManager.setActionName(actionName)
        debouncedSave()
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
        self.doubleExposureMaskOpacity = bundle.doubleExposureMaskOpacity
        self.doubleExposureMaskImagePath = bundle.doubleExposureMaskImagePath
        self.doubleExposureMaskImage = bundle.doubleExposureMaskImage
        self.diagonalSliceAngle = bundle.diagonalSliceAngle
        self.hexagonalSpacing = bundle.hexagonalSpacing
        isInitializing = false
    }

    func setBackgroundImage(_ image: NSImage?, path: String?) {
        backgroundImagePath = path
        backgroundImage = image
    }

    func setMaskImage(_ image: NSImage?, path: String?) {
        doubleExposureMaskImagePath = path
        doubleExposureMaskImage = image
    }

    // MARK: - Undo Helpers

    func beginGestureUndo() {
        undoManager.beginUndoGrouping()
    }

    func endGestureUndo(actionName: String) {
        undoManager.setActionName(actionName)
        undoManager.endUndoGrouping()
    }

    func registerTitleStyleUndo(oldStyle: TitleStyle) {
        undoManager.registerUndo(withTarget: self) { $0.titleStyle = oldStyle }
        undoManager.setActionName("Move Title")
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
        processingCount = 0
        errorMessage = nil
        panelAssignments.removeAll()
        backgroundImage = nil
    }

    // MARK: - Layout

    func regenerateLayout(preserveCrops: Bool = false) {
        debouncer.cancel(id: "previewRender")
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
            canvasSize: SizeConstants.defaultCanvasSize,
            gutter: gutter,
            style: layoutStyle,
            imageOrder: customImageOrder,
            sliceAngle: diagonalSliceAngle,
            hexSpacing: hexagonalSpacing
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
        beginProcessing()
        defer { endProcessing() }

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
            debouncer.cancel(id: "previewRender")
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

        debouncer.debounce(id: "panPreview", delay: .milliseconds(150)) { [weak self] in
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

        if let panelId = cropManager.activePanelId {
            debouncer.debounce(id: "pinchPreview", delay: .milliseconds(0)) { [weak self] in
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

    private var lastOverlayRenderTime: ContinuousClock.Instant = ContinuousClock.now
    private let overlayRenderInterval: Duration = .milliseconds(50)

    private func throttledOverlayRender(panelId: UUID) {
        let now = ContinuousClock.now
        guard now - lastOverlayRenderTime >= overlayRenderInterval else { return }
        lastOverlayRenderTime = now
        debouncer.debounce(id: "overlayRender", delay: .milliseconds(0)) { [weak self] in
            self?.updatePanelPreview(panelId: panelId)
        }
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
        throttledOverlayRender(panelId: panelId)
    }

    func finishOverlayCrop(panelId: UUID) {
        debouncer.cancel(id: "overlayRender")
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

    private var lastScrollRenderTime: ContinuousClock.Instant = ContinuousClock.now
    private let scrollRenderInterval: Duration = .milliseconds(60)

    private func throttledScrollPanRender() {
        let now = ContinuousClock.now
        guard now - lastScrollRenderTime >= scrollRenderInterval,
              let panelId = cropManager.scrollPanActivePanelId else { return }
        lastScrollRenderTime = now
        debouncer.debounce(id: "scrollPanPreview", delay: .milliseconds(0)) { [weak self] in
            self?.updatePanelPreview(panelId: panelId)
        }
    }

    func scrollPanDelta(_ delta: CGSize) {
        cropManager.scrollPanAccumulateDelta(delta, sensitivity: scrollSensitivity)
        cropManager.scrollPanApply(
            panels: panels,
            images: images,
            panelAssignments: panelAssignments,
            finish: false
        )
        throttledNotifyCropMapChanged(forScrollPan: true)
        throttledScrollPanRender()
    }

    func endScrollPan() {
        debouncer.cancel(id: "scrollPanPreview")
        cropManager.endScrollPan()
        notifyCropMapChanged()
    }

    // MARK: - Config

    func buildAssemblyConfig() -> AssemblyConfig {
        let textData = TitleTextData.extract(from: titleAttrString)
        let fontColor = titleStyle.fontColor.cgColor
        let titleBgColor = titleStyle.backgroundColor.cgColor

        let overlay: OverlayConfig? = {
            guard layoutStyle == .doubleExposure,
                  let maskImage = doubleExposureMaskImage,
                  let cgImage = maskImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
            return OverlayConfig(
                maskImage: cgImage,
                opacity: doubleExposureMaskOpacity,
                blendMode: .multiply
            )
        }()

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
            canvasSize: SizeConstants.defaultCanvasSize,
            overlay: overlay
        )
    }

    // MARK: - Preview & Export

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
            geometry: panel.geometry,
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
            canvasSize: SizeConstants.defaultCanvasSize,
            backgroundImage: backgroundImageCG,
            previewSize: SizeConstants.defaultPreviewSize
        )
    }

    func updatePreviewDebounced() {
        debouncer.debounce(id: "previewRender", delay: .milliseconds(150)) { [weak self] in
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
            previewSize: SizeConstants.defaultPreviewSize
        )

        if isLayeredMode {
            updateBackground()
            if let overlay = config.overlay {
                previewManager.updateOverlay(
                    overlay: overlay,
                    canvasSize: SizeConstants.defaultCanvasSize
                )
            }
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
        if let overlay = buildAssemblyConfig().overlay {
            previewManager.updateOverlay(
                overlay: overlay,
                canvasSize: SizeConstants.defaultCanvasSize
            )
        }
        updateTitleImage()
    }

    func updateTitleImage() {
        titleImageVersion += 1
        previewManager.updateTitleImage(
            titleAttrString: titleAttrString,
            titleStyle: titleStyle,
            canvasSize: SizeConstants.defaultCanvasSize
        )
    }

    func updateTitleImageLive() {
        updateTitleImage()
    }

    func finishTitleDrag() {
        debouncer.cancel(id: "titleImage")
        updateTitleImage()
        debouncedSave()
    }

    private func applyTitleChange<Value>(
        at keyPath: WritableKeyPath<TitleStyle, Value>,
        oldValue: Value,
        actionName: String,
        sideEffect: @escaping @MainActor () -> Void
    ) {
        guard !isInitializing else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.titleStyle[keyPath: keyPath] = oldValue
        }
        undoManager.setActionName(actionName)
        debouncedSave()
        sideEffect()
    }

    private func titleViewUpdate() {
        if isLayeredMode {
            updateTitleImage()
        } else {
            updatePreview()
        }
    }

    func setTitleFontFamily(_ family: String) {
        let oldValue = titleStyle.fontFamily
        titleStyle.fontFamily = family
        applyTitleChange(at: \.fontFamily, oldValue: oldValue, actionName: "Change Font Family") {
            self.updateTitleImageLive()
        }
    }

    func setTitleFontSize(_ size: CGFloat) {
        let oldValue = titleStyle.fontSize
        titleStyle.fontSize = size
        applyTitleChange(at: \.fontSize, oldValue: oldValue, actionName: "Change Font Size") {
            self.debouncer.debounce(id: "fontSize", delay: .milliseconds(150)) { [weak self] in
                self?.updateTitleImage()
            }
        }
    }

    func setTitleBackgroundColor(_ color: NSColor) {
        let oldValue = titleStyle.backgroundColor
        titleStyle.backgroundColor = color
        applyTitleChange(at: \.backgroundColor, oldValue: oldValue, actionName: "Change Title BG Color") {
            self.titleViewUpdate()
        }
    }

    func setTitleFontColor(_ color: NSColor) {
        let oldValue = titleStyle.fontColor
        titleStyle.fontColor = color
        applyTitleChange(at: \.fontColor, oldValue: oldValue, actionName: "Change Title Color") {
            self.titleViewUpdate()
        }
    }

    func setTitleAlignment(_ alignment: NSTextAlignment) {
        let oldValue = titleStyle.alignment
        titleStyle.alignment = alignment
        applyTitleChange(at: \.alignment, oldValue: oldValue, actionName: "Change Title Alignment") {
            self.titleViewUpdate()
        }
    }

    func setTitleShowBackground(_ show: Bool) {
        let oldValue = titleStyle.showBackground
        titleStyle.showBackground = show
        applyTitleChange(at: \.showBackground, oldValue: oldValue, actionName: "Toggle Title BG") {
            self.titleViewUpdate()
        }
    }

    func exportCollage() async -> URL? {
        beginProcessing()
        defer { endProcessing() }
        errorMessage = nil

        guard !panels.isEmpty else { return nil }

        let config = buildAssemblyConfig()
        let cgImages = imageLibrary.images.map { $0.cgImage }
        let bgCG = backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)

        switch await exportManager.export(
            config: config,
            cgImages: cgImages,
            backgroundImage: bgCG,
            quality: exportQuality
        ) {
        case .success(let url):
            return url
        case .cancelled:
            return nil
        case .failure(let error):
            errorMessage = error.localizedDescription
            return nil
        }
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
