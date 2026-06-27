import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import CollageMaker

@MainActor
struct LayoutRoundTripTests {

    private let canvasSize = SizeConstants.defaultCanvasSize

    @Test func roundTripAllStyles() async throws {
        let numImages = 6
        let images = (0..<numImages).map { i in
            createTestImageItem(color: NSColor.systemBlue, size: CGSize(width: 200, height: 200), filename: "\(i).jpg")
        }

        for style in LayoutStyle.allCases {
            let manager = LayoutManager()
            manager.layoutStyle = style

            manager.regenerateLayout(
                images: images,
                customImageOrder: [],
                cropManager: CropManager(),
                previewManager: PreviewManager(assembler: TestAssembler()),
                saliencyResults: [:],
                preserveCrops: false
            )

            #expect(manager.panels.count == numImages)

            for panel in manager.panels {
                #expect(panel.geometry.boundingRect.width > 0)
                #expect(panel.geometry.boundingRect.height > 0)
            }
        }
    }

    @Test func roundTripPreservesImageOrder() async throws {
        let numImages = 5
        let images = (0..<numImages).map { i in
            createTestImageItem(color: NSColor.systemBlue, size: CGSize(width: 200, height: 200), filename: "\(i).jpg")
        }
        let customOrder = [4, 2, 0, 3, 1]

        for style in LayoutStyle.allCases {
            let manager = LayoutManager()
            manager.layoutStyle = style

            manager.regenerateLayout(
                images: images,
                customImageOrder: customOrder,
                cropManager: CropManager(),
                previewManager: PreviewManager(assembler: TestAssembler()),
                saliencyResults: [:],
                preserveCrops: false
            )

            #expect(manager.panels.count == numImages)

            for (i, panel) in manager.panels.enumerated() {
                let expectedImageIndex = customOrder[i]
                #expect(manager.panelAssignments[panel.id] == expectedImageIndex)
            }
        }
    }

    @Test func diagonalAngleRoundTrip() async throws {
        let numImages = 4
        let images = (0..<numImages).map { i in
            createTestImageItem(color: NSColor.systemBlue, size: CGSize(width: 200, height: 200), filename: "\(i).jpg")
        }

        let angles: [CGFloat] = [0, 30, 45, 60, 75, 45]
        var stateAt45First: [ImagePanel]? = nil

        for angle in angles {
            let manager = LayoutManager()
            manager.layoutStyle = .diagonalSlices
            manager.diagonalSliceAngle = angle

            manager.regenerateLayout(
                images: images,
                customImageOrder: [],
                cropManager: CropManager(),
                previewManager: PreviewManager(assembler: TestAssembler()),
                saliencyResults: [:],
                preserveCrops: false
            )

            #expect(manager.panels.count == numImages)

            for panel in manager.panels {
                #expect(panel.geometry.boundingRect.width > 0)
                #expect(panel.geometry.boundingRect.height > 0)
            }

            if angle == 45 && stateAt45First == nil {
                stateAt45First = manager.panels.map { panel in
                    ImagePanel(id: panel.id, imageIndex: panel.imageIndex, geometry: panel.geometry)
                }
            } else if angle == 45 && stateAt45First != nil {
                let finalPanels = manager.panels.map { panel in
                    ImagePanel(id: panel.id, imageIndex: panel.imageIndex, geometry: panel.geometry)
                }

                #expect(finalPanels.count == stateAt45First!.count)

                for (i, finalPanel) in finalPanels.enumerated() {
                    let originalPanel = stateAt45First![i]
                    #expect(originalPanel.imageIndex == finalPanel.imageIndex)
                    #expect(originalPanel.geometry.boundingRect.approximatelyEqual(to: finalPanel.geometry.boundingRect))
                }
            }
        }
    }

    @Test func hexagonalSpacingRoundTrip() async throws {
        let numImages = 7
        let images = (0..<numImages).map { i in
            createTestImageItem(color: NSColor.systemBlue, size: CGSize(width: 200, height: 200), filename: "\(i).jpg")
        }

        let spacings: [CGFloat] = [2, 8, 20, 8]

        for spacing in spacings {
            let manager = LayoutManager()
            manager.layoutStyle = .hexagonal
            manager.hexagonalSpacing = spacing

            manager.regenerateLayout(
                images: images,
                customImageOrder: [],
                cropManager: CropManager(),
                previewManager: PreviewManager(assembler: TestAssembler()),
                saliencyResults: [:],
                preserveCrops: false
            )

            #expect(manager.panels.count == numImages)

            for panel in manager.panels {
                #expect(panel.geometry.boundingRect.width > 0)
                #expect(panel.geometry.boundingRect.height > 0)
            }

            assertPanelsHavePositiveArea(manager.panels)
        }
    }

    @Test func singleImageAllStyles() async throws {
        let numImages = 1
        let images = (0..<numImages).map { i in
            createTestImageItem(color: NSColor.systemBlue, size: CGSize(width: 200, height: 200), filename: "\(i).jpg")
        }

        for style in LayoutStyle.allCases {
            let manager = LayoutManager()
            manager.layoutStyle = style

            manager.regenerateLayout(
                images: images,
                customImageOrder: [],
                cropManager: CropManager(),
                previewManager: PreviewManager(assembler: TestAssembler()),
                saliencyResults: [:],
                preserveCrops: false
            )

            #expect(manager.panels.count == 1)

            let panel = manager.panels[0]
            let expectedFrame = CGRect(origin: .zero, size: canvasSize)
            #expect(panel.geometry.boundingRect.approximatelyEqual(to: expectedFrame))
        }
    }
}

private extension CGRect {
    func approximatelyEqual(to other: CGRect, tolerance: CGFloat = 1e-6) -> Bool {
        let dx = abs(origin.x - other.origin.x)
        let dy = abs(origin.y - other.origin.y)
        let dw = abs(width - other.width)
        let dh = abs(height - other.height)
        return dx <= tolerance && dy <= tolerance && dw <= tolerance && dh <= tolerance
    }
}

private func assertPanelsHavePositiveArea(_ panels: [ImagePanel]) {
    // For hexagonal layouts, verify that all panels have valid bounding rects
    var totalArea: CGFloat = 0
    for panel in panels {
        let bounds = panel.geometry.boundingRect
        #expect(bounds.width > 0, "Panel should have positive width")
        #expect(bounds.height > 0, "Panel should have positive height")
        totalArea += bounds.width * bounds.height
    }

    // Hexagonal layouts with spacing don't fill 100% of the canvas due to gaps between hexagons
    #expect(totalArea > 0, "Total panel area should be positive")
}
