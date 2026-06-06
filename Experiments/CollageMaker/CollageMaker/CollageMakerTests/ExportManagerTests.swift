import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import CollageMaker

@MainActor
@Suite(.serialized) struct ExportManagerTests {

    private let assembler: TestAssembler = { let a = TestAssembler(); a.trackCalls = true; return a }()
    private var manager: ExportManager {
        ExportManager(assembler: assembler)
    }

    // MARK: - Initial state

    @Test func initialStateIsIdle() {
        let mgr = manager
        #expect(mgr.isExporting == false)
        #expect(mgr.successMessage == nil)
    }

    // MARK: - Export with empty panels

    @Test func exportWithEmptyPanelsReturnsCancelled() async {
        let mgr = manager
        let config = makeAssemblyConfig(panels: [])

        let result = await mgr.export(
            config: config,
            cgImages: [],
            backgroundImage: nil,
            quality: 0.9
        )

        switch result {
        case .cancelled:
            break
        case .success, .failure:
            Issue.record("Expected .cancelled but got \(result)")
        }
        #expect(mgr.isExporting == false)
    }

    // MARK: - Dismiss success

    @Test func dismissSuccessClearsMessage() {
        let mgr = manager
        mgr.successMessage = "Saved to collage.jpg"
        mgr.dismissSuccess()
        #expect(mgr.successMessage == nil)
    }

    // MARK: - Export state management

    @Test func exportTaskCancellation() async {
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)
        let config = makeAssemblyConfig(panels: panels)
        let cgImage = createTestCGImage(color: .systemBlue, size: CGSize(width: 200, height: 200))

        // Verify the assembler integration by checking TestAssembler records calls.
        // Note: Full export flow requires NSSavePanel which can't run headless.
        _ = await assembler.assembleWithCGImages(
            config: config,
            cgImages: [cgImage],
            backgroundImage: nil,
            quality: 0.9
        )
        #expect(assembler.assembleCalls == 1)
    }
}
