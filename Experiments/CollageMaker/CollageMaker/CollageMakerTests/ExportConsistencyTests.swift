import AppKit
import CoreGraphics
import Testing
@testable import CollageMaker

@MainActor
@Suite(.serialized) struct ExportConsistencyTests {

    private let assembler = CollageAssembler()

    // MARK: - Helper methods

    func decodeDataToCGImage(_ data: Data, size: CGSize) -> CGImage? {
        guard let nsImage = NSImage(data: data) else { return nil }
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return cgImage
    }

    func extractPixelData(from cgImage: CGImage) -> [UInt8]? {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = (width * 4 + 31) / 32 * 32
        
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else { return nil }
        let pointer = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        return Array(UnsafeBufferPointer(start: pointer, count: bytesPerRow * height))
    }

    func comparePixelData(_ data1: [UInt8], _ data2: [UInt8], tolerance: Int = 5) -> Bool {
        guard data1.count == data2.count else { return false }

        var totalError: Double = 0
        let pixelCount = data1.count / 4

        for i in stride(from: 0, to: data1.count, by: 4) {
            let r1 = Int(data1[i])
            let g1 = Int(data1[i + 1])
            let b1 = Int(data1[i + 2])
            let a1 = Int(data1[i + 3])

            let r2 = Int(data2[i])
            let g2 = Int(data2[i + 1])
            let b2 = Int(data2[i + 2])
            let a2 = Int(data2[i + 3])

            let error = abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2) + abs(a1 - a2)
            totalError += Double(error) / 4.0
        }

        let meanError = totalError / Double(pixelCount)
        return meanError < Double(tolerance)
    }

    // MARK: - Test 1: exportMatchesPreviewAtFullResolution

    @Test func exportMatchesPreviewAtFullResolution() async {
        let cgImage1 = createTestCGImage(color: .systemBlue, size: CGSize(width: 200, height: 200))
        let cgImage2 = createTestCGImage(color: .systemGreen, size: CGSize(width: 200, height: 200))
        let cgImage3 = createTestCGImage(color: .systemRed, size: CGSize(width: 200, height: 200))

        let panels = LayoutGenerator.generate(numImages: 3, style: .uniform)
        var crops: [UUID: CropInfo] = [:]
        for panel in panels {
            crops[panel.id] = CropInfo(
                panelId: panel.id,
                sourceRect: CGRect(origin: .zero, size: CGSize(width: 200, height: 200)),
                destinationRect: panel.frame
            )
        }

        let config = makeAssemblyConfig(
            panels: panels,
            crops: crops,
            titleText: "Test Collage",
            backgroundStyle: .solid,
            gradientStartColor: .black,
            gradientEndColor: .darkGray,
            gradientAngle: 135,
            canvasSize: SizeConstants.defaultCanvasSize
        )

        let preview = await assembler.assemblePreviewWithCGImages(
            config: config,
            cgImages: [cgImage1, cgImage2, cgImage3],
            backgroundImage: nil,
            previewSize: SizeConstants.defaultCanvasSize
        )

        #expect(preview != nil)
        #expect(preview?.size == SizeConstants.defaultCanvasSize)

        let exportData = await assembler.assembleWithCGImages(
            config: config,
            cgImages: [cgImage1, cgImage2, cgImage3],
            backgroundImage: nil,
            quality: 1.0
        )

        #expect(exportData != nil)
        #expect(!exportData!.isEmpty)

        let exportCGImage = decodeDataToCGImage(exportData!, size: SizeConstants.defaultCanvasSize)
        #expect(exportCGImage != nil)

        if let previewCGImage = preview?.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let exportCG = exportCGImage {
            let previewPixelData = extractPixelData(from: previewCGImage)
            let exportPixelData = extractPixelData(from: exportCG)

            #expect(previewPixelData != nil)
            #expect(exportPixelData != nil)

            if let pPixels = previewPixelData, let ePixels = exportPixelData {
                #expect(comparePixelData(pPixels, ePixels, tolerance: 10))
            }
        }
    }

    // MARK: - Test 2: exportQualityAffectsFileSize

    @Test func exportQualityAffectsFileSize() async {
        let cgImage1 = createTestCGImage(color: .systemBlue, size: CGSize(width: 200, height: 200))
        let cgImage2 = createTestCGImage(color: .systemGreen, size: CGSize(width: 200, height: 200))
        let cgImage3 = createTestCGImage(color: .systemRed, size: CGSize(width: 200, height: 200))

        let panels = LayoutGenerator.generate(numImages: 3, style: .uniform)
        var crops: [UUID: CropInfo] = [:]
        for panel in panels {
            crops[panel.id] = CropInfo(
                panelId: panel.id,
                sourceRect: CGRect(origin: .zero, size: CGSize(width: 200, height: 200)),
                destinationRect: panel.frame
            )
        }

        let config = makeAssemblyConfig(panels: panels, crops: crops)

        let dataLowQuality = await assembler.assembleWithCGImages(
            config: config,
            cgImages: [cgImage1, cgImage2, cgImage3],
            backgroundImage: nil,
            quality: 0.1
        )

        let dataHighQuality = await assembler.assembleWithCGImages(
            config: config,
            cgImages: [cgImage1, cgImage2, cgImage3],
            backgroundImage: nil,
            quality: 1.0
        )

        #expect(dataLowQuality != nil)
        #expect(dataHighQuality != nil)
        #expect(!dataLowQuality!.isEmpty)
        #expect(!dataHighQuality!.isEmpty)

        if let lowData = dataLowQuality, let highData = dataHighQuality {
            #expect(highData.count > lowData.count)
        }
    }

    // MARK: - Test 3: exportWithTitleAndBackground

    @Test func exportWithTitleAndBackground() async {
        let cgImage1 = createTestCGImage(color: .systemBlue, size: CGSize(width: 200, height: 200))
        let panels = LayoutGenerator.generate(numImages: 1, style: .uniform)

        var crops: [UUID: CropInfo] = [:]
        for panel in panels {
            crops[panel.id] = CropInfo(
                panelId: panel.id,
                sourceRect: CGRect(origin: .zero, size: CGSize(width: 200, height: 200)),
                destinationRect: panel.frame
            )
        }

        let config = makeAssemblyConfig(
            panels: panels,
            crops: crops,
            titleText: "My Title",
            backgroundStyle: .solid,
            gradientStartColor: .black,
            gradientEndColor: .darkGray,
            gradientAngle: 135,
            canvasSize: SizeConstants.defaultCanvasSize
        )

        let exportData = await assembler.assembleWithCGImages(
            config: config,
            cgImages: [cgImage1],
            backgroundImage: nil,
            quality: 1.0
        )

        #expect(exportData != nil)
        #expect(!exportData!.isEmpty)

        let exportCGImage = decodeDataToCGImage(exportData!, size: SizeConstants.defaultCanvasSize)
        #expect(exportCGImage != nil)

        if let cgImg = exportCGImage {
            let pixelData = extractPixelData(from: cgImg)
            #expect(pixelData != nil)

            if let pixels = pixelData {
                let width = Int(SizeConstants.defaultCanvasSize.width)
                let height = Int(SizeConstants.defaultCanvasSize.height)

                let titleY = 50
                let titleX = Int(SizeConstants.defaultCanvasSize.width / 2.0) - 100

                if titleY < height && titleX >= 0 && (titleX + 200) < width {
                    var hasNonBackgroundPixel = false
                    for dy in 0..<40 {
                        for dx in 0..<200 {
                            let px = (titleY + dy) * width * 4 + (titleX + dx) * 4
                            if px + 3 < pixels.count {
                                let r = Int(pixels[px])
                                let g = Int(pixels[px + 1])
                                let b = Int(pixels[px + 2])

                                if r > 50 || g > 50 || b > 50 {
                                    hasNonBackgroundPixel = true
                                    break
                                }
                            }
                        }
                        if hasNonBackgroundPixel { break }
                    }
                    #expect(hasNonBackgroundPixel)
                }
            }
        }
    }

    // MARK: - Test 4: exportWithDiagonalSlicesLayout

    @Test func exportWithDiagonalSlicesLayout() async {
        let cgImage1 = createTestCGImage(color: .systemBlue, size: CGSize(width: 200, height: 200))
        let cgImage2 = createTestCGImage(color: .systemGreen, size: CGSize(width: 200, height: 200))

        let panels = LayoutGenerator.generate(numImages: 2, style: .diagonalSlices)

        var crops: [UUID: CropInfo] = [:]
        for panel in panels {
            crops[panel.id] = CropInfo(
                panelId: panel.id,
                sourceRect: CGRect(origin: .zero, size: CGSize(width: 200, height: 200)),
                destinationRect: panel.frame
            )
        }

        let config = makeAssemblyConfig(panels: panels, crops: crops)

        let exportData = await assembler.assembleWithCGImages(
            config: config,
            cgImages: [cgImage1, cgImage2],
            backgroundImage: nil,
            quality: 1.0
        )

        #expect(exportData != nil)
        #expect(!exportData!.isEmpty)

        let exportCGImage = decodeDataToCGImage(exportData!, size: SizeConstants.defaultCanvasSize)
        #expect(exportCGImage != nil)

        if let cgImg = exportCGImage {
            #expect(cgImg.width == Int(SizeConstants.defaultCanvasSize.width))
            #expect(cgImg.height == Int(SizeConstants.defaultCanvasSize.height))
        }
    }

    // MARK: - Test 5: exportWithHexagonalLayout

    @Test func exportWithHexagonalLayout() async {
        let cgImage1 = createTestCGImage(color: .systemBlue, size: CGSize(width: 200, height: 200))
        let cgImage2 = createTestCGImage(color: .systemGreen, size: CGSize(width: 200, height: 200))
        let cgImage3 = createTestCGImage(color: .systemRed, size: CGSize(width: 200, height: 200))

        let panels = LayoutGenerator.generate(numImages: 3, style: .hexagonal)

        var crops: [UUID: CropInfo] = [:]
        for panel in panels {
            crops[panel.id] = CropInfo(
                panelId: panel.id,
                sourceRect: CGRect(origin: .zero, size: CGSize(width: 200, height: 200)),
                destinationRect: panel.frame
            )
        }

        let config = makeAssemblyConfig(panels: panels, crops: crops)

        let exportData = await assembler.assembleWithCGImages(
            config: config,
            cgImages: [cgImage1, cgImage2, cgImage3],
            backgroundImage: nil,
            quality: 1.0
        )

        #expect(exportData != nil)
        #expect(!exportData!.isEmpty)

        let exportCGImage = decodeDataToCGImage(exportData!, size: SizeConstants.defaultCanvasSize)
        #expect(exportCGImage != nil)

        if let cgImg = exportCGImage {
            #expect(cgImg.width == Int(SizeConstants.defaultCanvasSize.width))
            #expect(cgImg.height == Int(SizeConstants.defaultCanvasSize.height))
        }
    }
}
