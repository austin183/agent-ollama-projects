import Foundation

/// Minimal surface ImageCoordinator needs to orchestrate image operations
/// without importing CollageViewModel directly.
protocol ImageCoordinationTarget: AnyObject {
    func beginProcessing()
    func endProcessing()
    var isProcessing: Bool { get }
    func updatePreview()
    func updateAllPanelPreviews()
    func updatePanelPreview(panelId: UUID)
    func resetCrop(panelId: UUID)
    var selectedPanelId: UUID? { get set }
    var errorMessage: String? { get set }
    var customImageOrder: [Int] { get set }
    func regenerateLayout()
    func cancelDebouncer(id: String)
}
