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
    private let persistence: any ViewModelPersistence
    let layoutManager = LayoutManager()
    let cropManager = CropManager()
    let previewManager: PreviewManager
    let undoManager = UndoManager()
    let imageLibrary = ImageLibraryManager()
    let backgroundManager = BackgroundManager()
    let titleManager = TitleManager()
    private var isInitializing = false
    private var saliencyResults: [Int: SaliencyResult] = [:]
    let debouncer = Debouncer()
    private var cropMapVersion = 0
    var titleImageVersion = 0

    // MARK: - Title computed properties (delegated to TitleManager)

    var titleAttrString: NSAttributedString {
        get { titleManager.titleAttrString }
        set {
            guard !isInitializing else { titleManager.titleAttrString = newValue; return }
            let old = titleManager.titleAttrString
            titleManager.titleAttrString = newValue
            guard !old.isEqual(newValue) else { return }
            registerUndo(oldValue: old, actionName: "Edit Title") { $0.titleManager.titleAttrString = old }
            if isLayeredMode {
                titleManager.updateImage(viewModel: self)
            } else {
                updatePreview()
            }
        }
    }

    var title: String { titleManager.title }

    var titleStyle: TitleStyle {
        get { titleManager.titleStyle }
        set {
            let old = titleManager.titleStyle
            titleManager.titleStyle = newValue
            guard !isInitializing else { return }
            if titleManager.isDraggingTitle {
                titleManager.updateImageLive(viewModel: self)
                return
            }
            undoManager.registerUndo(withTarget: self) { target in
                target.titleManager.titleStyle = old
            }
            undoManager.setActionName("Change Title Style")
            debouncedSave()
            if isLayeredMode {
                titleManager.updateImage(viewModel: self)
            } else {
                updatePreview()
            }
        }
    }

    var cachedTitleCanvasFrame: CGRect? { titleManager.canvasFrame }
    var cachedTitleMinWidth: CGFloat { titleManager.minWidth }

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
    var panels: [ImagePanel] { layoutManager.panels }
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

    var layoutStyle: LayoutStyle { layoutManager.layoutStyle }

    // Style-specific configuration (delegated to LayoutManager)
    var doubleExposureMaskImage: NSImage? { layoutManager.doubleExposureMaskImage }
    var doubleExposureMaskImagePath: String? { layoutManager.doubleExposureMaskImagePath }
    var doubleExposureMaskOpacity: CGFloat { layoutManager.doubleExposureMaskOpacity }
    var diagonalSliceAngle: CGFloat { layoutManager.diagonalSliceAngle }
    var hexagonalSpacing: CGFloat { layoutManager.hexagonalSpacing }

    // titleAttrString, title, titleStyle — delegated to titleManager (see above)

    var gutter: CGFloat { layoutManager.gutter }

    // MARK: - Layout Setters (side effects: undo, preview, regeneration)

    func setLayoutStyle(_ style: LayoutStyle) {
        let old = layoutManager.layoutStyle
        layoutManager.layoutStyle = style
        guard !isInitializing else { return }
        registerUndo(oldValue: old, actionName: "Change Layout") { $0.layoutManager.layoutStyle = old }
        logger.info("Layout style changed to \(self.layoutStyle.rawValue, privacy: .public)")
        regenerateLayout()
    }

    func setGutter(_ value: CGFloat) {
        let old = layoutManager.gutter
        layoutManager.gutter = value
        guard !isInitializing else { return }
        debouncer.debounce(id: "gutter", delay: .milliseconds(150)) { [weak self] in
            guard let self else { return }
            self.undoManager.registerUndo(withTarget: self) { target in
                target.layoutManager.gutter = old
            }
            self.undoManager.setActionName("Change Gutter")
            self.debouncedSave()
            self.regenerateLayout(preserveCrops: true)
        }
    }

    func setDiagonalSliceAngle(_ value: CGFloat) {
        let old = layoutManager.diagonalSliceAngle
        layoutManager.diagonalSliceAngle = value
        guard !isInitializing else { return }
        registerUndo(oldValue: old, actionName: "Change Slice Angle") { $0.layoutManager.diagonalSliceAngle = old }
        if layoutStyle == .diagonalSlices {
            regenerateLayout(preserveCrops: false)
        }
    }

    func setHexagonalSpacing(_ value: CGFloat) {
        let old = layoutManager.hexagonalSpacing
        layoutManager.hexagonalSpacing = value
        guard !isInitializing else { return }
        registerUndo(oldValue: old, actionName: "Change Hex Spacing") { $0.layoutManager.hexagonalSpacing = old }
        if layoutStyle == .hexagonal {
            regenerateLayout(preserveCrops: false)
        }
    }

    func setDoubleExposureMaskOpacity(_ value: CGFloat) {
        let old = layoutManager.doubleExposureMaskOpacity
        layoutManager.doubleExposureMaskOpacity = value
        guard !isInitializing else { return }
        registerUndo(oldValue: old, actionName: "Change Mask Opacity") { $0.layoutManager.doubleExposureMaskOpacity = old }
        updatePreviewDebounced()
    }

    func setMaskImage(_ image: NSImage?, path: String?) {
        let oldImage = layoutManager.doubleExposureMaskImage
        let oldPath = layoutManager.doubleExposureMaskImagePath
        layoutManager.doubleExposureMaskImagePath = path
        layoutManager.doubleExposureMaskImage = image
        guard !isInitializing else { return }
        if image == nil {
            layoutManager.doubleExposureMaskImagePath = nil
        }
        registerUndo(oldValue: oldImage, actionName: "Change Mask Image") { target in
            target.layoutManager.doubleExposureMaskImage = oldImage
            target.layoutManager.doubleExposureMaskImagePath = oldPath
        }
        updatePreview()
    }

    var scrollSensitivity: CGFloat = 1.6

    // MARK: - Background computed properties (delegated to BackgroundManager)

    var backgroundColor: NSColor {
        get { backgroundManager.backgroundColor }
        set {
            let old = backgroundManager.backgroundColor
            backgroundManager.backgroundColor = newValue
            guard !isInitializing else { return }
            debouncer.debounce(id: "backgroundColor", delay: .milliseconds(150)) { [weak self] in
                guard let self else { return }
                self.undoManager.registerUndo(withTarget: self) { target in
                    target.backgroundManager.backgroundColor = old
                }
                self.undoManager.setActionName("Change Background Color")
                self.debouncedSave()
                self.updatePreview()
            }
        }
    }

    var exportQuality: Double = 0.92 {
        didSet {
            registerUndo(oldValue: oldValue, actionName: "Change Export Quality") { $0.exportQuality = oldValue }
        }
    }

    var backgroundStyle: BackgroundStyle {
        get { backgroundManager.backgroundStyle }
        set {
            let old = backgroundManager.backgroundStyle
            backgroundManager.backgroundStyle = newValue
            guard !isInitializing else { return }
            undoManager.registerUndo(withTarget: self) { target in
                target.backgroundManager.backgroundStyle = old
            }
            undoManager.setActionName("Change Background Style")
            debouncedSave()
            updatePreview()
        }
    }

    var gradientStartColor: NSColor {
        get { backgroundManager.gradientStartColor }
        set {
            let old = backgroundManager.gradientStartColor
            backgroundManager.gradientStartColor = newValue
            guard !isInitializing else { return }
            undoManager.registerUndo(withTarget: self) { target in
                target.backgroundManager.gradientStartColor = old
            }
            undoManager.setActionName("Change Gradient Start Color")
            debouncedSave()
            updatePreviewDebounced()
        }
    }

    var gradientEndColor: NSColor {
        get { backgroundManager.gradientEndColor }
        set {
            let old = backgroundManager.gradientEndColor
            backgroundManager.gradientEndColor = newValue
            guard !isInitializing else { return }
            undoManager.registerUndo(withTarget: self) { target in
                target.backgroundManager.gradientEndColor = old
            }
            undoManager.setActionName("Change Gradient End Color")
            debouncedSave()
            updatePreviewDebounced()
        }
    }

    var gradientAngle: Double {
        get { backgroundManager.gradientAngle }
        set {
            let old = backgroundManager.gradientAngle
            backgroundManager.gradientAngle = newValue
            guard !isInitializing else { return }
            undoManager.registerUndo(withTarget: self) { target in
                target.backgroundManager.gradientAngle = old
            }
            undoManager.setActionName("Change Gradient Angle")
            debouncedSave()
            updatePreviewDebounced()
        }
    }

    var backgroundImage: NSImage? {
        get { backgroundManager.backgroundImage }
        set {
            let old = backgroundManager.backgroundImage
            backgroundManager.backgroundImage = newValue
            guard !isInitializing else { return }
            undoManager.registerUndo(withTarget: self) { target in
                target.backgroundManager.backgroundImage = old
            }
            undoManager.setActionName("Change Background Image")
            debouncedSave()
            if newValue == nil {
                backgroundManager.backgroundImagePath = nil
            }
            updatePreview()
        }
    }

    var backgroundImagePath: String? {
        get { backgroundManager.backgroundImagePath }
        set { backgroundManager.backgroundImagePath = newValue }
    }

    var backgroundOpacity: Double {
        get { backgroundManager.backgroundOpacity }
        set {
            let old = backgroundManager.backgroundOpacity
            backgroundManager.backgroundOpacity = newValue
            guard !isInitializing else { return }
            undoManager.registerUndo(withTarget: self) { target in
                target.backgroundManager.backgroundOpacity = old
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
    var panelAssignments: [UUID: Int] { layoutManager.panelAssignments }

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
    var isDraggingTitle: Bool {
        get { titleManager.isDraggingTitle }
        set { titleManager.isDraggingTitle = newValue }
    }
    var errorMessage: String?
    var exportSuccessMessage: String? { exportManager.successMessage }

    func dismissExportSuccess() {
        exportManager.dismissSuccess()
    }

    func debouncedSave() {
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
        persistence: any ViewModelPersistence
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
        layoutManager.layoutStyle = bundle.layoutStyle
        self.titleAttrString = bundle.titleAttrString
        self.titleStyle = bundle.titleStyle
        layoutManager.gutter = bundle.gutter
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
        layoutManager.doubleExposureMaskOpacity = bundle.doubleExposureMaskOpacity
        layoutManager.doubleExposureMaskImagePath = bundle.doubleExposureMaskImagePath
        layoutManager.doubleExposureMaskImage = bundle.doubleExposureMaskImage
        layoutManager.diagonalSliceAngle = bundle.diagonalSliceAngle
        layoutManager.hexagonalSpacing = bundle.hexagonalSpacing
        isInitializing = false
    }

    func setBackgroundImage(_ image: NSImage?, path: String?) {
        let oldImage = backgroundManager.backgroundImage
        backgroundManager.setBackgroundImage(image, path: path)
        guard !isInitializing else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.backgroundManager.backgroundImage = oldImage
        }
        undoManager.setActionName("Change Background Image")
        debouncedSave()
        updatePreview()
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
        layoutManager.panelAssignments.removeAll()
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
        let oldBgImage = backgroundManager.backgroundImage
        let oldBgImagePath = backgroundManager.backgroundImagePath
        backgroundManager.reset()
        titleManager.reset()
        layoutManager.reset()
        undoManager.registerUndo(withTarget: self) { target in
            target.imageLibrary.images = oldImages
            target.layoutManager.panels = oldPanels
            target.cropMap = oldCropMap
            target.backgroundManager.backgroundImage = oldBgImage
            target.backgroundManager.backgroundImagePath = oldBgImagePath
            target.regenerateLayout()
        }
        undoManager.setActionName("Clear All")
        exportManager.exportTask?.cancel()
        cropManager.cropMap.removeAll()
        saliencyResults.removeAll()
        selectedPanelId = nil
        previewManager.clearAll()
        processingCount = 0
        errorMessage = nil
    }

    // MARK: - Layout

    func regenerateLayout(preserveCrops: Bool = false) {
        debouncer.cancel(id: "previewRender")
        guard !images.isEmpty else { return }

        let layoutStart = ContinuousClock.now
        defer { perfLogger.debug("Layout Regeneration completed in \(ContinuousClock.now - layoutStart)") }

        layoutManager.regenerateLayout(
            images: images,
            customImageOrder: customImageOrder,
            cropManager: cropManager,
            previewManager: previewManager,
            saliencyResults: saliencyResults,
            preserveCrops: preserveCrops
        )

        let panelCount = panels.count
        let styleRaw = layoutStyle.rawValue
        let selectedStr = selectedPanelId?.uuidString ?? "nil"
        let foundInNew = selectedPanelId != nil && panels.contains { $0.id == selectedPanelId }
        logger.info("Regenerated layout: \(panelCount) panels, style=\(styleRaw, privacy: .public), selectedId=\(selectedStr, privacy: .public), foundInNew=\(foundInNew)")

        isLayeredMode = false
        updatePreview()
        updateAllPanelPreviews()
    }

    // MARK: - Panel Image Assignment

    func assignImage(_ imageIndex: Int, to panelId: UUID) {
        layoutManager.panelAssignments[panelId] = imageIndex
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
        layoutManager.panelAssignments[sourceId] = customImageOrder[sourceSlot]
        layoutManager.panelAssignments[targetId] = customImageOrder[targetSlot]

        if let cropA = cropMap[sourceId], let cropB = cropMap[targetId] {
            cropMap[sourceId] = CropInfo(panelId: sourceId, sourceRect: cropB.sourceRect, destination: cropA.destination)
            cropMap[targetId] = CropInfo(panelId: targetId, sourceRect: cropA.sourceRect, destination: cropB.destination)
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
            destination: crop.destination
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
        let textData = TitleTextData.extract(from: titleManager.titleAttrString)
        let fontColor = titleManager.titleStyle.fontColor.cgColor
        let titleBgColor = titleManager.titleStyle.backgroundColor.cgColor

        return AssemblyConfig(
            layout: LayoutConfig(
                panels: layoutManager.panels,
                crops: cropMap,
                panelAssignments: layoutManager.panelAssignments
            ),
            title: TitleConfig(
                textData: textData,
                style: titleManager.titleStyle,
                fontColor: fontColor,
                backgroundColor: titleBgColor
            ),
            background: backgroundManager.buildConfig(),
            canvasSize: SizeConstants.defaultCanvasSize,
            overlay: layoutManager.buildOverlayConfig()
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
        backgroundManager.updateBackground(viewModel: self)
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
        let backgroundImageCG = backgroundManager.backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)

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
        titleManager.updateImage(viewModel: self)
    }

    func updateTitleImageLive() {
        titleManager.updateImageLive(viewModel: self)
    }

    func finishTitleDrag() {
        titleManager.finishDrag(viewModel: self)
    }

    private func applyTitleChange<Value>(
        at keyPath: WritableKeyPath<TitleStyle, Value>,
        oldValue: Value,
        actionName: String,
        sideEffect: @escaping @MainActor () -> Void
    ) {
        guard !isInitializing else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.titleManager.titleStyle[keyPath: keyPath] = oldValue
        }
        undoManager.setActionName(actionName)
        debouncedSave()
        sideEffect()
    }

    func setTitleFontFamily(_ family: String) {
        let oldValue = titleManager.titleStyle.fontFamily
        titleManager.titleStyle.fontFamily = family
        applyTitleChange(at: \.fontFamily, oldValue: oldValue, actionName: "Change Font Family") {
            self.titleManager.updateImageLive(viewModel: self)
        }
    }

    func setTitleFontSize(_ size: CGFloat) {
        let oldValue = titleManager.titleStyle.fontSize
        titleManager.titleStyle.fontSize = size
        applyTitleChange(at: \.fontSize, oldValue: oldValue, actionName: "Change Font Size") {
            self.debouncer.debounce(id: "fontSize", delay: .milliseconds(150)) { [weak self] in
                guard let self else { return }
                self.titleManager.updateImage(viewModel: self)
            }
        }
    }

    func setTitleBackgroundColor(_ color: NSColor) {
        let oldValue = titleManager.titleStyle.backgroundColor
        titleManager.titleStyle.backgroundColor = color
        applyTitleChange(at: \.backgroundColor, oldValue: oldValue, actionName: "Change Title BG Color") {
            if self.isLayeredMode {
                self.titleManager.updateImage(viewModel: self)
            } else {
                self.updatePreview()
            }
        }
    }

    func setTitleFontColor(_ color: NSColor) {
        let oldValue = titleManager.titleStyle.fontColor
        titleManager.titleStyle.fontColor = color
        applyTitleChange(at: \.fontColor, oldValue: oldValue, actionName: "Change Title Color") {
            if self.isLayeredMode {
                self.titleManager.updateImage(viewModel: self)
            } else {
                self.updatePreview()
            }
        }
    }

    func setTitleAlignment(_ alignment: NSTextAlignment) {
        let oldValue = titleManager.titleStyle.alignment
        titleManager.titleStyle.alignment = alignment
        applyTitleChange(at: \.alignment, oldValue: oldValue, actionName: "Change Title Alignment") {
            if self.isLayeredMode {
                self.titleManager.updateImage(viewModel: self)
            } else {
                self.updatePreview()
            }
        }
    }

    func setTitleShowBackground(_ show: Bool) {
        let oldValue = titleManager.titleStyle.showBackground
        titleManager.titleStyle.showBackground = show
        applyTitleChange(at: \.showBackground, oldValue: oldValue, actionName: "Toggle Title BG") {
            if self.isLayeredMode {
                self.titleManager.updateImage(viewModel: self)
            } else {
                self.updatePreview()
            }
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
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: self.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
