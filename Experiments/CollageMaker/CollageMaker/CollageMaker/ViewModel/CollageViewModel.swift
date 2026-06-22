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


private class PanelFrameCache {
    var version: Int = -1
    var size: CGSize = .zero
    var result: [UUID: CGRect] = [:]
}

@MainActor
@Observable
final class CollageViewModel {
    private let saliencyAnalyzer: SaliencyAnalysis
    private let assembler: any CollageAssembly
    private let persistence: any ViewModelPersistence
    private let imagePicker: ImagePicker
    let layoutManager = LayoutManager()
    let cropManager = CropManager()
    let previewManager: PreviewManager
    let undoManager = UndoManager()
    let imageLibrary = ImageLibraryManager()
    let backgroundManager = BackgroundManager()
    let titleManager = TitleManager()
    var imageCoordinator: ImageCoordinator
    private var isInitializing = false
    let debouncer = Debouncer()
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
                titleManager.updateImage(updater: self)
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
                titleManager.updateImage(updater: self)
                return
            }
            undoManager.registerUndo(withTarget: self) { target in
                target.titleManager.titleStyle = old
            }
            undoManager.setActionName("Change Title Style")
            if isLayeredMode {
                titleManager.updateImage(updater: self)
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
        }
    }
    var panels: [ImagePanel] { layoutManager.panels }
    var selectedPanelId: UUID?

    /// Single source of truth for crop state — delegated to CropManager.
    var cropMap: [UUID: CropInfo] {
        get { cropManager.cropMap }
        set { cropManager.cropMap = newValue }
    }

    func getCropVersion(for panelId: UUID) -> Int {
        cropManager.getCropVersion(panelId: panelId)
    }

    var scrollPanActivePanelId: UUID? { cropManager.scrollPanActivePanelId }

    /// Cached preview-space panel frames. Invalidates when layout version or
    /// preview size changes. Moves the O(N) canvas→preview coordinate transform
    /// out of the SwiftUI body evaluation path (R4 fix).
    private let frameCache = PanelFrameCache()

    func computePanelFrames(previewSize: CGSize) -> [UUID: CGRect] {
        if frameCache.version == layoutManager.layoutVersion,
           frameCache.size == previewSize {
            return frameCache.result
        }
        frameCache.version = layoutManager.layoutVersion
        frameCache.size = previewSize
        frameCache.result = panels.reduce(into: [UUID: CGRect]()) { dict, panel in
            dict[panel.id] = CoordinateConverter.canvasToPreviewFrame(
                panel.frame,
                in: previewSize,
                canvasSize: SizeConstants.defaultCanvasSize
            )
        }
        return frameCache.result
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
        let old = layoutManager.setLayoutStyle(style)
        guard !isInitializing else { return }
        registerUndo(oldValue: old, actionName: "Change Layout") { $0.layoutManager.layoutStyle = old }
        regenerateLayout()
    }

    func setGutter(_ value: CGFloat) {
        let old = layoutManager.setGutter(value)
        guard !isInitializing else { return }
        debouncer.debounce(id: "gutter", delay: FrameTempo.layoutChangeDebounce) { [weak self] in
            guard let self else { return }
            self.undoManager.registerUndo(withTarget: self) { target in
                target.layoutManager.gutter = old
            }
            self.undoManager.setActionName("Change Gutter")
            self.regenerateLayout(preserveCrops: true)
        }
    }

    func setDiagonalSliceAngle(_ value: CGFloat) {
        let old = layoutManager.setDiagonalSliceAngle(value)
        guard !isInitializing else { return }
        registerUndo(oldValue: old, actionName: "Change Slice Angle") { $0.layoutManager.diagonalSliceAngle = old }
        if layoutStyle == .diagonalSlices {
            regenerateLayout(preserveCrops: false)
        }
    }

    func setHexagonalSpacing(_ value: CGFloat) {
        let old = layoutManager.setHexagonalSpacing(value)
        guard !isInitializing else { return }
        registerUndo(oldValue: old, actionName: "Change Hex Spacing") { $0.layoutManager.hexagonalSpacing = old }
        if layoutStyle == .hexagonal {
            regenerateLayout(preserveCrops: false)
        }
    }

    func setDoubleExposureMaskOpacity(_ value: CGFloat) {
        let old = layoutManager.setDoubleExposureMaskOpacity(value)
        guard !isInitializing else { return }
        registerUndo(oldValue: old, actionName: "Change Mask Opacity") { $0.layoutManager.doubleExposureMaskOpacity = old }
        updatePreviewDebounced()
    }

    func setMaskImage(_ image: NSImage?, path: String?) {
        let (oldImage, oldPath) = layoutManager.setMaskImage(image, path: path)
        guard !isInitializing else { return }
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
            debouncer.debounce(id: "backgroundColor", delay: FrameTempo.backgroundColorDebounce) { [weak self] in
                guard let self else { return }
                self.undoManager.registerUndo(withTarget: self) { target in
                    target.backgroundManager.backgroundColor = old
                }
                self.undoManager.setActionName("Change Background Color")
                self.updatePreview()
            }
        }
    }

    var rightDrawerWidth: CGFloat = 300

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
    var showSaliencyOverlay: Bool = false
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

    func cancelExport() {
        exportManager.exportTask?.cancel()
    }

    /// Persists current settings to UserDefaults. Called on app quit.
    func saveSettings() {
        persistence.save(self)
    }

    private func registerUndo<Value>(oldValue: Value, actionName: String, restore: @escaping (CollageViewModel) -> Void) {
        guard !isInitializing else { return }
        undoManager.registerUndo(withTarget: self) { target in
            restore(target)
        }
        undoManager.setActionName(actionName)
    }

    convenience init() {
        let assembler = CollageAssembler()
        self.init(
            saliencyAnalyzer: SaliencyAnalyzer(),
            assembler: assembler,
            persistence: UserDefaultsPersistence(),
            imagePicker: DefaultImagePicker()
        )
    }

    convenience init(
        saliencyAnalyzer: SaliencyAnalysis,
        assembler: CollageAssembly
    ) {
        self.init(
            saliencyAnalyzer: saliencyAnalyzer,
            assembler: assembler,
            persistence: UserDefaultsPersistence(),
            imagePicker: DefaultImagePicker()
        )
    }

    init(
        saliencyAnalyzer: SaliencyAnalysis,
        assembler: CollageAssembly,
        persistence: any ViewModelPersistence,
        imagePicker: ImagePicker = DefaultImagePicker()
    ) {
        self.saliencyAnalyzer = saliencyAnalyzer
        self.assembler = assembler
        self.persistence = persistence
        self.imagePicker = imagePicker
        self.previewManager = PreviewManager(assembler: assembler)
        self.exportManager = ExportManager(assembler: assembler)
        self.undoManager.levelsOfUndo = 60
        self.imageCoordinator = ImageCoordinator(
            imageLibrary: imageLibrary,
            layoutManager: layoutManager,
            cropManager: cropManager,
            previewManager: previewManager,
            undoManager: undoManager,
            saliencyAnalyzer: saliencyAnalyzer
        )
        imageCoordinator.target = self

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
        self.rightDrawerWidth = bundle.rightDrawerWidth
        isInitializing = false
    }

    func setBackgroundImage(_ image: NSImage?, path: String?) {
        let (oldImage, oldPath) = backgroundManager.setBackgroundImage(image, path: path)
        guard !isInitializing else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.backgroundManager.backgroundImage = oldImage
            target.backgroundManager.backgroundImagePath = oldPath
        }
        undoManager.setActionName("Change Background Image")
        updatePreview()
    }

    // MARK: - Image Picker

    func chooseMaskImage() async {
        let result = await imagePicker.pickImage(allowedTypes: [.jpeg, .png, .tiff, .heic, .heif])
        if let image = result.image {
            setMaskImage(image, path: result.path)
        }
    }

    func chooseBackgroundImage() async {
        let result = await imagePicker.pickImage(allowedTypes: [.jpeg, .png, .tiff, .heic, .heif])
        if let image = result.image {
            setBackgroundImage(image, path: result.path)
        }
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
            saliencyResults: imageCoordinator.saliencyResults,
            preserveCrops: preserveCrops
        )

        // Sync customImageOrder from panelAssignments so swapPanelImages has a valid array.
        if imageLibrary.customImageOrder.isEmpty || imageLibrary.customImageOrder.count != images.count {
            imageLibrary.customImageOrder = panels.compactMap { layoutManager.panelAssignments[$0.id] }
        }

        let panelCount = panels.count
        let styleRaw = layoutStyle.rawValue
        let selectedStr = selectedPanelId?.uuidString ?? "nil"
        let foundInNew = selectedPanelId != nil && panels.contains { $0.id == selectedPanelId }
        logger.info("Regenerated layout: \(panelCount) panels, style=\(styleRaw, privacy: .public), selectedId=\(selectedStr, privacy: .public), foundInNew=\(foundInNew)")

        isLayeredMode = false
        updatePreview()
        updateAllPanelPreviews()
    }

    // MARK: - Saliency (delegated to ImageCoordinator)

    func analyzeSaliency() async {
        await imageCoordinator.analyzeSaliency()
    }

    // MARK: - Image Operations (undo + downstream effects)

    func clearAll() {
        guard !imageLibrary.images.isEmpty else { return }
        let oldSaliency = imageCoordinator.saliencyResults
        let oldDomain = imageCoordinator.clearDomain()

        let oldBackgroundConfig = backgroundManager.buildConfig()
        let oldTitleAttrString = titleManager.titleAttrString
        let oldTitleStyle = titleManager.titleStyle
        let oldSelectedPanelId = selectedPanelId

        layoutManager.reset()
        layoutManager.panels = []
        layoutManager.panelAssignments.removeAll()
        cropManager.cropMap.removeAll()
        cropManager.cropVersions.removeAll()
        previewManager.clearAll()
        backgroundManager.reset()
        titleManager.reset()
        selectedPanelId = nil
        errorMessage = nil

        undoManager.registerUndo(withTarget: self) { [oldBackgroundConfig, oldTitleAttrString, oldTitleStyle, oldSelectedPanelId, oldSaliency] target in
            target.imageLibrary.images = oldDomain.images
            target.layoutManager.panels = oldDomain.panels
            target.cropManager.cropMap = oldDomain.cropMap
            target.cropManager.cropVersions = oldDomain.cropVersions
            target.imageCoordinator.saliencyResults = oldSaliency
            target.backgroundManager.backgroundColor = oldBackgroundConfig.color
            target.backgroundManager.backgroundStyle = oldBackgroundConfig.style
            target.titleManager.titleAttrString = oldTitleAttrString
            target.titleManager.titleStyle = oldTitleStyle
            target.selectedPanelId = oldSelectedPanelId
            target.regenerateLayout()
        }
        undoManager.setActionName("Clear All")
    }

    func removeImage(at index: Int) {
        guard let (removed, at) = imageCoordinator.removeImage(at: index) else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.imageLibrary.images.insert(removed, at: at)
            target.regenerateLayout()
        }
        undoManager.setActionName("Remove Image")
    }

    func moveImages(from: IndexSet, to: Int) {
        let oldOrder = imageCoordinator.moveImages(from: from, to: to)
        undoManager.registerUndo(withTarget: self) { target in
            target.customImageOrder = oldOrder
            target.regenerateLayout()
        }
        undoManager.setActionName("Reorder Images")
    }

    func swapPanelImages(sourceId: UUID, targetId: UUID) {
        guard let state = imageCoordinator.swapPanelImages(sourceId: sourceId, targetId: targetId) else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.customImageOrder = state.customOrder
            target.cropManager.cropMap[sourceId] = state.sourceCrop
            target.cropManager.cropVersions[sourceId, default: 0] += 1
            target.cropManager.cropMap[targetId] = state.targetCrop
            target.cropManager.cropVersions[targetId, default: 0] += 1
            target.layoutManager.panelAssignments[sourceId] = state.sourceAssign
            target.layoutManager.panelAssignments[targetId] = state.targetAssign
            target.regenerateLayout()
        }
        undoManager.setActionName("Swap Images")
    }

    func browseImages() {
        imageCoordinator.browseImages()
    }

    func addImages(from urls: [URL]) async {
        await imageCoordinator.addImages(from: urls)
    }

    func getEffectiveImageIndex(for panelId: UUID) -> Int? {
        imageCoordinator.getEffectiveImageIndex(for: panelId)
    }

    func selectPanelForImage(at imageIndex: Int) {
        imageCoordinator.selectPanelForImage(at: imageIndex)
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

        debouncer.debounce(id: "panPreview", delay: FrameTempo.panPreviewDebounce) { [weak self] in
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
        }
    }

    func applyPinchLive() {
        cropManager.applyPinch(panelId: nil, panels: panels, images: images, panelAssignments: panelAssignments, finish: false)

        if let panelId = cropManager.activePanelId {
            debouncer.debounce(id: "pinchPreview", delay: FrameTempo.pinchPreviewDebounce) { [weak self] in
                self?.updatePanelPreview(panelId: panelId)
            }
        }
    }

    func resetCrop(panelId: UUID) {
        logger.info("Reset crop for panel")
        if let oldCrop = cropMap[panelId] {
            undoManager.registerUndo(withTarget: self) { target in
                target.cropMap[panelId] = oldCrop
                target.cropManager.cropVersions[panelId, default: 0] += 1
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
            target.cropManager.cropVersions[panelId, default: 0] += 1
            target.updatePanelPreview(panelId: panelId)
        }
    }

    func endOverlayCropUndo() {
        undoManager.setActionName("Adjust Crop")
        undoManager.endUndoGrouping()
    }

    private var lastOverlayRenderTime: ContinuousClock.Instant = ContinuousClock.now

    private func throttledOverlayRender(panelId: UUID) {
        let now = ContinuousClock.now
        guard now - lastOverlayRenderTime >= FrameTempo.overlayRenderInterval else { return }
        lastOverlayRenderTime = now
        debouncer.debounce(id: "overlayRender", delay: FrameTempo.overlayRenderDebounce) { [weak self] in
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
        cropManager.cropVersions[panelId, default: 0] += 1
        throttledOverlayRender(panelId: panelId)
    }

    func finishOverlayCrop(panelId: UUID) {
        debouncer.cancel(id: "overlayRender")
        updatePanelPreview(panelId: panelId)
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

    private func throttledScrollPanRender() {
        let now = ContinuousClock.now
        guard now - lastScrollRenderTime >= FrameTempo.scrollRenderInterval,
              let panelId = cropManager.scrollPanActivePanelId else { return }
        lastScrollRenderTime = now
        debouncer.debounce(id: "scrollPanPreview", delay: FrameTempo.scrollPanPreviewDebounce) { [weak self] in
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
        throttledScrollPanRender()
    }

    func endScrollPan() {
        debouncer.cancel(id: "scrollPanPreview")
        cropManager.endScrollPan()
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
        backgroundManager.updateBackground(updater: self)
    }

    func updatePreviewDebounced() {
        debouncer.debounce(id: "previewRender", delay: FrameTempo.previewRenderDebounce) { [weak self] in
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
            } else {
                previewManager.overlayImage = nil
                previewManager.overlayBlendMode = nil
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
        } else {
            previewManager.overlayImage = nil
            previewManager.overlayBlendMode = nil
        }
        updateTitleImage()
    }

    func updateTitleImage() {
        titleManager.updateImage(updater: self)
    }

    func updateTitleImageLive() {
        titleManager.updateImage(updater: self)
    }

    func finishTitleDrag() {
        titleManager.finishDrag(updater: self)
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
        sideEffect()
    }

    func setTitleFontFamily(_ family: String) {
        let oldValue = titleManager.titleStyle.fontFamily
        titleManager.titleStyle.fontFamily = family
        applyTitleChange(at: \.fontFamily, oldValue: oldValue, actionName: "Change Font Family") {
            self.titleManager.updateImage(updater: self)
        }
    }

    func setTitleFontSize(_ size: CGFloat) {
        let oldValue = titleManager.titleStyle.fontSize
        titleManager.titleStyle.fontSize = size
        applyTitleChange(at: \.fontSize, oldValue: oldValue, actionName: "Change Font Size") {
            self.debouncer.debounce(id: "fontSize", delay: FrameTempo.fontSizeDebounce) { [weak self] in
                guard let self else { return }
                self.titleManager.updateImage(updater: self)
            }
        }
    }

    func setTitleBackgroundColor(_ color: NSColor) {
        let oldValue = titleManager.titleStyle.backgroundColor
        titleManager.titleStyle.backgroundColor = color
        applyTitleChange(at: \.backgroundColor, oldValue: oldValue, actionName: "Change Title BG Color") {
            if self.isLayeredMode {
                self.titleManager.updateImage(updater: self)
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
                self.titleManager.updateImage(updater: self)
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
                self.titleManager.updateImage(updater: self)
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
                self.titleManager.updateImage(updater: self)
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

// MARK: - PreviewUpdatable Conformance

extension CollageViewModel: PreviewUpdatable {
    func updateTitleImage(attrString: NSAttributedString, style: TitleStyle, canvasSize: CGSize) {
        previewManager.updateTitleImage(titleAttrString: attrString, titleStyle: style, canvasSize: canvasSize)
    }

    func incrementTitleVersion() {
        titleImageVersion += 1
    }

    func updateBackground(config: BackgroundConfig, canvasSize: CGSize, backgroundImage: CGImage?, previewSize: CGSize) {
        previewManager.updateBackground(config: config, canvasSize: canvasSize, backgroundImage: backgroundImage, previewSize: previewSize)
    }

    func cancelDebouncer(id: String) {
        debouncer.cancel(id: id)
    }
}

// MARK: - ImageCoordinationTarget Conformance

extension CollageViewModel: ImageCoordinationTarget {
    func regenerateLayout() {
        regenerateLayout(preserveCrops: false)
    }
}

extension URL {
    var folderExists: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: self.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
