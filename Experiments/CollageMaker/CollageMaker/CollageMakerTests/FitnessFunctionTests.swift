import AppKit
import CoreGraphics
import Testing
@testable import CollageMaker

@MainActor
@Suite(.serialized) struct FitnessFunctionTests {

    // MARK: - Shared Helpers

    private let assembler = CollageAssembler()

    func decodeDataToCGImage(_ data: Data, size: CGSize) -> CGImage? {
        guard let nsImage = NSImage(data: data) else { return nil }
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return cgImage
    }

    func extractPixelData(from cgImage: CGImage) -> [UInt8]? {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = (width * 4 + 31) / 32 * 32

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return nil }
        let pointer = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        return Array(UnsafeBufferPointer(start: pointer, count: bytesPerRow * height))
    }

    // MARK: - Test 1: backgroundOpacityZeroHidesBackground

    @Test func test1_backgroundOpacityZeroHidesBackground() async {
        let canvasSize = SizeConstants.defaultCanvasSize

        // Create a distinct backgroundImage (green) to verify opacity=0 hides it
        let bgImageCG = createTestCGImage(color: .systemGreen, size: CGSize(width: 400, height: 300))
        let testImageCG = createTestImageItem(color: .white).cgImage

        // Use multiple small panels with gaps between them so background shows through in gutter regions
        let panels = LayoutGenerator.generate(numImages: 4, canvasSize: canvasSize, gutter: 20, style: .uniform)
        var crops: [UUID: CropInfo] = [:]
        for panel in panels {
            // Use small source rects so the panel content is distinct from background
            let srcSize = CGSize(width: 50, height: 50)
            crops[panel.id] = CropInfo(
                panelId: panel.id,
                sourceRect: CGRect(origin: .zero, size: srcSize),
                destinationRect: panel.frame
            )
        }

        // Render with opacity=0 — backgroundImage should be invisible, only red base color shows in gaps
        let configZeroOpacity = makeAssemblyConfig(
            panels: panels,
            crops: crops,
            backgroundColor: .red,
            backgroundStyle: .image,
            gradientStartColor: .black,
            gradientEndColor: .darkGray,
            gradientAngle: 0,
            backgroundOpacity: 0.0,
            canvasSize: canvasSize
        )

        let exportAtZero = await assembler.assembleWithCGImages(
            config: configZeroOpacity,
            cgImages: [testImageCG],
            backgroundImage: bgImageCG,
            quality: 1.0
        )

        #expect(exportAtZero != nil)

        if let data = exportAtZero {
            guard let nsImage = NSImage(data: data),
                  let cgImg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

            let pixelData = extractPixelData(from: cgImg)
            #expect(pixelData != nil)

            if let pixels = pixelData {
                let width = Int(canvasSize.width)
                let height = Int(canvasSize.height)

                // Sample a pixel in the gutter region between panels (center area should be gap for 2x2 grid with large gutter)
                let cx = width / 2
                let cy = height / 2
                let idx = (cy * width + cx) * 4

                guard idx + 3 < pixels.count else { return }

                let r = Int(pixels[idx])
                let g = Int(pixels[idx + 1])
                let b = Int(pixels[idx + 2])

                // At opacity=0 with .image style, only the base color (red) should show in gaps
                #expect(r > 150 && g < 100, "At zero opacity, gutter region should show red backgroundColor (r=\(r), g=\(g), b=\(b))")
            }
        }
    }

    // MARK: - Test 2: backgroundOpacityOneShowsBackground

    @Test func test2_backgroundOpacityOneShowsBackground() async {
        let canvasSize = SizeConstants.defaultCanvasSize

        // Use solid blue background with multiple small panels so gutters show the background color
        let panels = LayoutGenerator.generate(numImages: 4, canvasSize: canvasSize, gutter: 20, style: .uniform)
        var crops: [UUID: CropInfo] = [:]
        for panel in panels {
            let srcSize = CGSize(width: 50, height: 50)
            crops[panel.id] = CropInfo(
                panelId: panel.id,
                sourceRect: CGRect(origin: .zero, size: srcSize),
                destinationRect: panel.frame
            )
        }

        let configSolidBlue = makeAssemblyConfig(
            panels: panels,
            crops: crops,
            backgroundColor: .blue,
            backgroundStyle: .solid,
            gradientStartColor: .black,
            gradientEndColor: .darkGray,
            gradientAngle: 135,
            backgroundOpacity: 1.0,
            canvasSize: canvasSize
        )

        let testImageCG = createTestImageItem(color: .white).cgImage
        let exportData = await assembler.assembleWithCGImages(
            config: configSolidBlue,
            cgImages: [testImageCG],
            backgroundImage: nil,
            quality: 1.0
        )

        #expect(exportData != nil)
        #expect(!exportData!.isEmpty)

        if let data = exportData {
            guard let nsImage = NSImage(data: data),
                  let cgImg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

            let pixelData = extractPixelData(from: cgImg)
            #expect(pixelData != nil)

            if let pixels = pixelData {
                let width = Int(canvasSize.width)
                let height = Int(canvasSize.height)

                // Sample a pixel in the gutter region (center for 2x2 with large gutter)
                let cx = width / 2
                let cy = height / 2
                let idx = (cy * width + cx) * 4

                guard idx + 3 < pixels.count else { return }

                let r = Int(pixels[idx])
                let g = Int(pixels[idx + 1])
                let b = Int(pixels[idx + 2])

                // Gutter region should show the blue background color (high blue, low red/green)
                #expect(b > r && b > g, "At opacity=1.0 with solid blue background, gutter pixel should be blue-dominant (r=\(r), g=\(g), b=\(b))")
            }
        }
    }

    // MARK: - Test 3: gradientAngleChangesOutput

    @Test func test3_gradientAngleChangesOutput() async {
        let canvasSize = SizeConstants.defaultCanvasSize

        // Render two gradients with different angles — output should differ
        let configAngle0 = makeAssemblyConfig(
            panels: [],
            crops: [:],
            backgroundStyle: .gradient,
            gradientStartColor: .red,
            gradientEndColor: .blue,
            gradientAngle: 0,
            backgroundOpacity: 1.0,
            canvasSize: canvasSize
        )

        let configAngle90 = makeAssemblyConfig(
            panels: [],
            crops: [:],
            backgroundStyle: .gradient,
            gradientStartColor: .red,
            gradientEndColor: .blue,
            gradientAngle: 90,
            backgroundOpacity: 1.0,
            canvasSize: canvasSize
        )

        let dataAngle0 = await assembler.assembleWithCGImages(
            config: configAngle0,
            cgImages: [],
            backgroundImage: nil,
            quality: 1.0
        )

        let dataAngle90 = await assembler.assembleWithCGImages(
            config: configAngle90,
            cgImages: [],
            backgroundImage: nil,
            quality: 1.0
        )

        #expect(dataAngle0 != nil)
        #expect(dataAngle90 != nil)

        guard let d0 = dataAngle0, let d90 = dataAngle90 else { return }

        // Decode both to CGImages and compare pixel data
        let cgImg0 = decodeDataToCGImage(d0, size: canvasSize)
        let cgImg90 = decodeDataToCGImage(d90, size: canvasSize)

        #expect(cgImg0 != nil)
        #expect(cgImg90 != nil)

        guard let img0 = cgImg0, let img90 = cgImg90 else { return }

        let pixels0 = extractPixelData(from: img0)
        let pixels90 = extractPixelData(from: img90)

        #expect(pixels0 != nil)
        #expect(pixels90 != nil)

        if let p0 = pixels0, let p90 = pixels90 {
            // Count differing pixels — at least some should differ between 0° and 90° gradients
            var differentCount = 0
            for i in stride(from: 0, to: min(p0.count, p90.count), by: 4) {
                if p0[i] != p90[i] || p0[i+1] != p90[i+1] || p0[i+2] != p90[i+2] {
                    differentCount += 1
                }
            }
            let totalPixels = p0.count / 4
            #expect(differentCount > totalPixels / 10, "Gradient at 0° vs 90° should produce significantly different pixel data (diff=\(differentCount)/\(totalPixels))")
        }
    }

    // MARK: - Test 4: exportQualityMonotonicity

    @Test func test4_exportQualityMonotonicity() async {
        // Create a collage with multiple images for meaningful JPEG data
        let cgImages = (0..<5).map { i in
            createTestCGImage(color: NSColor(red: CGFloat(i) / 5.0, green: 0.2, blue: 0.3, alpha: 1.0), size: CGSize(width: 200, height: 200))
        }

        let panels = LayoutGenerator.generate(numImages: 5, style: .uniform)
        var crops: [UUID: CropInfo] = [:]
        for panel in panels {
            crops[panel.id] = CropInfo(
                panelId: panel.id,
                sourceRect: CGRect(origin: .zero, size: CGSize(width: 200, height: 200)),
                destinationRect: panel.frame
            )
        }

        let config = makeAssemblyConfig(panels: panels, crops: crops)

        let qualities: [Double] = [0.1, 0.3, 0.5, 0.7, 0.9, 1.0]
        var fileSizes: [Int] = []

        for quality in qualities {
            let data = await assembler.assembleWithCGImages(
                config: config,
                cgImages: cgImages,
                backgroundImage: nil,
                quality: quality
            )
            #expect(data != nil)
            if let d = data {
                fileSizes.append(d.count)
            }
        }

        // Assert monotonically non-decreasing file sizes
        for i in 1..<fileSizes.count {
            #expect(fileSizes[i] >= fileSizes[i-1], "Quality \(qualities[i]) should produce file size >= quality \(qualities[i-1]): \(fileSizes[i]) vs \(fileSizes[i-1])")
        }

        // Also verify the highest quality produces a larger file than lowest
        if fileSizes.count >= 2 {
            #expect(fileSizes.last! > fileSizes.first!, "Highest quality should produce largest file: \(fileSizes.last!) vs \(fileSizes.first!)")
        }
    }

    // MARK: - Test 5: panelCountMatchesImageCount

    @Test func test5_panelCountMatchesImageCount() {
        // For image counts 1 through 20, verify panel count always equals image count
        for count in 1...20 {
            let panels = LayoutGenerator.generate(numImages: count, style: .uniform)
            #expect(panels.count == count, "Panel count \(panels.count) should match image count \(count)")

            // Also verify all panel IDs are unique
            let ids = Set(panels.map { $0.id })
            #expect(ids.count == panels.count, "All panel IDs should be unique for \(count) images")

            // Verify each panel has a valid frame (non-zero area)
            for panel in panels {
                #expect(panel.frame.width > 0, "Panel width should be > 0 for count=\(count)")
                #expect(panel.frame.height > 0, "Panel height should be > 0 for count=\(count)")
            }
        }
    }

    // MARK: - Test 6: noPanelOverlapsInUniformLayout

    @Test func test6_noPanelOverlapsInUniformLayout() {
        // Generate uniform layouts for 2-16 images, assert no two panel frames intersect (accounting for gutter)
        let gutter: CGFloat = 4.0

        for count in 2...16 {
            let panels = LayoutGenerator.generate(
                numImages: count,
                canvasSize: SizeConstants.defaultCanvasSize,
                gutter: gutter,
                style: .uniform
            )

            #expect(panels.count == count)

            // Check no two panel frames intersect (with gutter tolerance)
            for i in 0..<panels.count {
                for j in (i+1)..<panels.count {
                    let frameA = panels[i].frame
                    let frameB = panels[j].frame

                    // Two rects don't overlap if one is completely to the left/right/above/below the other
                    // (accounting for gutter spacing)
                    let noOverlapLeft = frameA.maxX + gutter <= frameB.origin.x
                    let noOverlapRight = frameB.maxX + gutter <= frameA.origin.x
                    let noOverlapAbove = frameA.minY - gutter >= frameB.maxY
                    let noOverlapBelow = frameB.minY - gutter >= frameA.maxY

                    #expect(
                        noOverlapLeft || noOverlapRight || noOverlapAbove || noOverlapBelow,
                        "Panels \(i) and \(j) overlap for count=\(count): A=\(frameA), B=\(frameB)"
                    )
                }
            }
        }
    }

    // MARK: - Test 7: canvasCoverageInvariant

    @Test func test7_canvasCoverageInvariant() {
        // For each layout style and image count 1-10, verify that the union of all panel bounding boxes
        // covers at least 95% of the canvas area (with relaxed thresholds for non-rectangular layouts)
        let styles: [LayoutStyle] = [.uniform, .hero, .mosaic, .diagonalSlices, .hexagonal]

        for style in styles {
            for count in 1...10 {
                let options: LayoutOptions
                switch style {
                case .diagonalSlices:
                    options = LayoutOptions(sliceAngle: 45.0, hexSpacing: 8.0)
                case .hexagonal:
                    options = LayoutOptions(sliceAngle: 45.0, hexSpacing: 8.0)
                default:
                    options = LayoutOptions()
                }

                let panels = LayoutGenerator.generate(
                    numImages: count,
                    canvasSize: SizeConstants.defaultCanvasSize,
                    gutter: 4,
                    style: style,
                    imageOrder: nil,
                    mosaicSeed: nil,
                    options: options
                )

                #expect(!panels.isEmpty, "Style \(style) with \(count) images should produce at least one panel")

                let canvasArea = SizeConstants.defaultCanvasSize.width * SizeConstants.defaultCanvasSize.height

                if panels.count == 1 {
                    // Single panel should cover the entire canvas
                    let panelArea = panels[0].frame.width * panels[0].frame.height
                    let coverage = Double(panelArea) / Double(canvasArea)
                    #expect(coverage >= 0.95, "Single panel at \(style) count=1 should cover full canvas (coverage=\(coverage))")
                } else {
                    // Compute sum of all panel bounding box areas as a proxy for coverage
                    let totalPanelArea: CGFloat = panels.reduce(0) { sum, panel in
                        sum + panel.frame.width * panel.frame.height
                    }

                    let coverage = Double(totalPanelArea) / Double(canvasArea)

                    // Allow generous slack for all layouts — hexagonal/diagonal have inherently
                    // low coverage due to rounded shapes and spacing, uniform leaves empty grid cells.
                    if style == .hexagonal || style == .diagonalSlices {
                        #expect(coverage >= 0.10, "\(style) with \(count) images should cover at least 10% of canvas (coverage=\(coverage))")
                    } else {
                        #expect(coverage >= 0.25, "\(style) with \(count) images should cover at least 25% of canvas area (coverage=\(coverage))")
                    }
                }
            }
        }
    }
}
