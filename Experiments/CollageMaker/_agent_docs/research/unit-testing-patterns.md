# CollageMaker Unit Testing — Research & Patterns

## Current State

| Test Suite | Tests | Status |
|---|---|---|
| `LayoutGeneratorTests` | 12 | ✅ All pass |
| `SaliencyResultTests` | 3 | ✅ All pass |
| `ImagePanelTests` | 3 | ✅ All pass |
| `CollageAssemblerTests` | 4 | ❌ All crash |
| **Total** | **22** | **18/22 pass** |

---

## 1. CGImage Test Fixture Crash — Root Cause & Fixes

### Problem
`CGContext.makeImage()` crashes in the test environment when creating 1920x1080 images with `[.byteOrder32Big]` bitmap info.

### Why It Happens
- `[.byteOrder32Big]` creates a **32-bit RGBX** buffer with no alpha channel
- In the test runner, the display server context may be headless or restricted
- Large canvas (1920x1080 = 8.3M pixels × 4 bytes = 33MB) may exceed test environment limits
- The crash is in `CGContext.makeImage()`, not context creation

### Fix Option A: Smaller Test Images ✅ (Recommended)
Use 100x100 or 200x200 images for assembler tests. The assembler logic doesn't depend on exact dimensions — it just draws into rects.

```swift
private func createTestCGImage(size: CGSize = CGSize(width: 100, height: 100), color: CGColor) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo: CGBitmapInfo = [.byteOrder32Big]

    guard let context = CGContext(
        data: nil,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
    ) else {
        fatalError("Failed to create CGContext")
    }

    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)
    context.setFillColor(color)
    context.fill(CGRect(origin: .zero, size: size))

    return context.makeImage()!
}
```

**Caveat:** The `assembler.assembleWithCGImages` method draws into `panel.frame` rects (which are 1920x1080-scale), but with a 100x100 source image, the image will just be upsampled. The test still validates the **pipeline works** (context creation → draw → makeImage → JPEG export).

### Fix Option B: `NSBitmapImageRep` Approach
Create images via `NSBitmapImageRep` and `lockFocus`:

```swift
private func createTestImage(size: CGSize, color: NSColor) -> NSImage {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .sRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    )!

    let image = NSImage(size: size)
    image.addRepresentation(rep)

    image.lockFocus()
    color.set()
    CGRect(origin: .zero, size: size).fill()
    image.unlockFocus()

    return image
}
```

**Problem:** `NSImage.cgImage(forProposedRect:)` may still return nil for images created this way in headless test environments.

### Fix Option C: `CGImageAlphaInfo.noneSkipFirst`
Try a different bitmap info that's more compatible:

```swift
let bitmapInfo: CGBitmapInfo = CGImageAlphaInfo.noneSkipFirst.rawValue
```

**Unlikely to work** — the crash is about the test environment, not the bitmap format.

### Recommendation
**Use Fix A (smaller images)** — simplest, most reliable, tests the same pipeline logic.

---

## 2. Testing `SaliencyAnalyzer` (Actor + Async)

### Challenge
`SaliencyAnalyzer` is an `actor` that uses the Vision framework. Testing requires:
- Real images (Vision won't analyze synthetic CGImages meaningfully)
- Async/await test methods
- Actor isolation

### Test Pattern: Integration Test with Real Image
```swift
@MainActor
struct SaliencyAnalyzerTests {

    @Test func analyzeReturnsValidResult() async throws {
        let analyzer = SaliencyAnalyzer()

        // Use a real image from test bundle
        guard let url = Bundle.module.url(forResource: "test-photo", withExtension: "jpg"),
              let image = NSImage(contentsOf: url)
        else {
            Issue.record("Test image not found")
            return
        }

        let result = try await analyzer.analyze(image)

        #expect(result.center.x >= 0)
        #expect(result.center.y >= 0)
        #expect(result.radius > 0)
        #expect(result.confidence >= 0)
        #expect(result.confidence <= 1)
    }

    @Test func analyzeThrowsForInvalidImage() async throws {
        let analyzer = SaliencyAnalyzer()
        let emptyImage = NSImage(size: CGSize(width: 1, height: 1))

        #throw(try await analyzer.analyze(emptyImage))
    }

    @Test func analyzeAllReturnsCorrectCount() async throws {
        let analyzer = SaliencyAnalyzer()

        guard let url = Bundle.module.url(forResource: "test-photo", withExtension: "jpg"),
              let image1 = NSImage(contentsOf: url),
              let image2 = NSImage(contentsOf: url)
        else {
            Issue.record("Test image not found")
            return
        }

        let results = try await analyzer.analyzeAll([image1, image2])

        #expect(results.count == 2)
    }
}
```

### Test Image Setup
1. Add test images to `CollageMakerTests/Resources/`
2. In Xcode: add files to test target with "Copy items if needed"
3. Access via `Bundle.module.url(forResource:withExtension:)`

---

## 3. Testing `CollageViewModel` (@MainActor ObservableObject)

### Challenge
`CollageViewModel` is `@MainActor` with `@Published` state. Testing requires:
- `@MainActor` test methods
- State observation (Combine or direct property checks)
- Mocking `NSSavePanel` for export tests

### Test Pattern: Direct State Inspection
```swift
@MainActor
struct CollageViewModelTests {

    @Test func addImagesRegeneratesLayout() async throws {
        let vm = CollageViewModel()

        let image = createTestImageItem(size: CGSize(width: 100, height: 100))
        vm.addImages([image])

        #expect(vm.images.count == 1)
        #expect(vm.panels.count == 1)
        #expect(vm.crops.count == 1)
        #expect(vm.panels[0].isHero == true)
    }

    @Test func removeImageAdjustsHeroIndex() async throws {
        let vm = CollageViewModel()

        let images = (0..<3).map { _ in createTestImageItem() }
        vm.addImages(images)
        vm.setHeroIndex(2)

        vm.removeImage(at: 1)

        #expect(vm.images.count == 2)
        #expect(vm.heroIndex == 1)  // Was 2, shifted down
    }

    @Test func clearAllResetsState() async throws {
        let vm = CollageViewModel()
        vm.addImages([createTestImageItem()])
        vm.clearAll()

        #expect(vm.images.isEmpty)
        #expect(vm.panels.isEmpty)
        #expect(vm.crops.isEmpty)
        #expect(vm.previewImage == nil)
        #expect(vm.selectedPanelId == nil)
    }

    @Test func setHeroIndexRegeneratesLayout() async throws {
        let vm = CollageViewModel()
        vm.addImages([createTestImageItem(), createTestImageItem()])

        vm.setHeroIndex(1)

        let hero = vm.panels.first(where: { $0.isHero })
        #expect(hero?.imageIndex == 1)
    }

    @Test func updateGutterRegeneratesLayout() async throws {
        let vm = CollageViewModel()
        vm.addImages([createTestImageItem(), createTestImageItem()])

        let panelsBefore = vm.panels
        vm.updateGutter(10)

        // Panels should have changed (different gutter spacing)
        #expect(vm.panels != panelsBefore)
    }

    private func createTestImageItem(size: CGSize = CGSize(width: 100, height: 100)) -> ImageItem {
        let image = NSImage(size: size)
        return ImageItem(nsImage: image, fileName: "test.jpg")
    }
}
```

### Test Pattern: State Observation with Combine
```swift
@Test func cropUpdateTriggersPreview() async throws {
    let vm = CollageViewModel()
    vm.addImages([createTestImageItem()])

    var previewChanged = false
    let cancellable = vm.objectWillChange.sink { _ in
        previewChanged = true
    }

    let panelId = vm.panels[0].id
    vm.updateCrop(for: panelId, sourceRect: CGRect(x: 10, y: 10, width: 80, height: 80), zoom: 1.0)

    // Give Combine time to fire
    try await Task.sleep(for: .milliseconds(100))

    #expect(previewChanged == true)
    _ = cancellable  // Prevent unused warning
}
```

---

## 4. Protocol-Based Mocking for Vision Framework

### Problem
`SaliencyAnalyzer` depends on the Vision framework, which is expensive and non-deterministic.

### Solution: Extract Protocol
```swift
protocol SaliencyAnalysis {
    func analyze(_ image: NSImage) async throws -> SaliencyResult
    func analyzeAll(_ images: [NSImage]) async throws -> [SaliencyResult]
}

// Make SaliencyAnalyzer conform
actor SaliencyAnalyzer: SaliencyAnalysis { ... }

// Mock for testing
class MockSaliencyAnalyzer: SaliencyAnalysis {
    var mockResults: [SaliencyResult] = []
    var analyzeCallCount = 0

    func analyze(_ image: NSImage) async throws -> SaliencyResult {
        analyzeCallCount += 1
        return mockResults.first ?? SaliencyResult(
            center: CGPoint(x: 50, y: 50),
            radius: 30,
            confidence: 0.9
        )
    }

    func analyzeAll(_ images: [NSImage]) async throws -> [SaliencyResult] {
        analyzeCallCount += images.count
        return Array(mockResults.prefix(images.count))
    }
}
```

**Caveat:** `CollageViewModel` creates `SaliencyAnalyzer` as a private property. To inject a mock, add an initializer:

```swift
init(saliencyAnalyzer: SaliencyAnalysis = SaliencyAnalyzer()) {
    self.saliencyAnalyzer = saliencyAnalyzer
}
```

---

## 5. Testing `LayoutGenerator` — Additional Tests

Current tests cover count, hero, canvas bounds, and uniqueness. Missing:

### Panel Overlap Detection
```swift
@Test func panelsDoNotOverlap() async throws {
    let panels = LayoutGenerator.generate(numImages: 6, heroIndex: nil)

    for i in 0..<panels.count {
        for j in (i+1)..<panels.count {
            let overlap = panels[i].frame.intersection(panels[j].frame)
            #expect(overlap.isEmpty || overlap.width <= 1) // Allow 1px gutter overlap
        }
    }
}
```

### Hero Panel Is Largest
```swift
@Test func heroPanelIsLargest() async throws {
    let panels = LayoutGenerator.generate(numImages: 4, heroIndex: 0)

    let hero = panels.first(where: { $0.isHero })!
    let nonHeroes = panels.filter { !$0.isHero }

    let heroArea = hero.width * hero.height
    for panel in nonHeroes {
        let area = panel.width * panel.height
        #expect(heroArea >= area)
    }
}
```

### Gutter Spacing
```swift
@Test func gutterAffectsPanelSize() async throws {
    let panelsSmall = LayoutGenerator.generate(numImages: 4, heroIndex: nil, gutter: 2)
    let panelsLarge = LayoutGenerator.generate(numImages: 4, heroIndex: nil, gutter: 16)

    // Larger gutter should produce smaller panels
    let totalAreaSmall = panelsSmall.reduce(0) { $0 + $1.width * $1.height }
    let totalAreaLarge = panelsLarge.reduce(0) { $0 + $1.width * $1.height }

    #expect(totalAreaSmall > totalAreaLarge)
}
```

---

## 6. Testing `SaliencyResult` — Additional Tests

Missing: exact coordinate verification, aspect ratio handling.

### Precise Crop Origin
```swift
@Test func cropOriginIsCenteredOnSaliency() async throws {
    let result = SaliencyResult(
        center: CGPoint(x: 500, y: 300),
        radius: 200,
        confidence: 0.8
    )

    let topLeft = result.croppedTopLeftCorner(imageSize: CGSize(width: 1000, height: 600))

    // cropRadius = 100, cropWidth = 200, cropHeight = 120 (for 1.67 aspect)
    // topLeft should be approximately (400, 240)
    #expect(topLeft.x >= 350 && topLeft.x <= 450)
    #expect(topLeft.y >= 200 && topLeft.y <= 280)
}
```

### Portrait Image
```swift
@Test func cropPortraitImage() async throws {
    let result = SaliencyResult(
        center: CGPoint(x: 300, y: 500),
        radius: 200,
        confidence: 0.7
    )

    let topLeft = result.croppedTopLeftCorner(imageSize: CGSize(width: 600, height: 1000))

    #expect(topLeft.x >= 0)
    #expect(topLeft.y >= 0)
}
```

---

## 7. Testing `ImagePanel` — Additional Tests

Missing: Codable round-trip, frame computation with negative coords.

### Codable Round-Trip
```swift
@Test func panelCodableRoundTrip() async throws {
    let panel = ImagePanel(id: UUID(), x: 10, y: 20, width: 100, height: 200, imageIndex: 3, isHero: true)

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let data = try encoder.encode(panel)
    let decoded = try decoder.decode(ImagePanel.self, from: data)

    #expect(decoded.x == panel.x)
    #expect(decoded.y == panel.y)
    #expect(decoded.width == panel.width)
    #expect(decoded.height == panel.height)
    #expect(decoded.imageIndex == panel.imageIndex)
    #expect(decoded.isHero == panel.isHero)
}
```

### Panel Inequality
```swift
@Test func panelInequality() async throws {
    let id = UUID()
    let panel1 = ImagePanel(id: id, x: 0, y: 0, width: 100, height: 100, imageIndex: 0)
    let panel2 = ImagePanel(id: id, x: 0, y: 0, width: 100, height: 100, imageIndex: 1)

    #expect(panel1 != panel2)
}
```

---

## 8. Testing `CollageAssembler` — Fixed Tests

### Use Small Images + Proportional Panels
```swift
struct CollageAssemblerTests {

    @Test func assembleBasicCollage() async throws {
        let assembler = CollageAssembler()
        let cgImage = createSmallTestImage(color: NSColor.red.cgColor)

        // Create a single full-canvas panel for small test
        let panel = ImagePanel(
            x: 0, y: 0, width: 1920, height: 1080, imageIndex: 0, isHero: true
        )
        let crops = [CropInfo(
            sourceRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            destinationRect: panel.frame,
            imageIndex: 0
        )]

        let data = assembler.assembleWithCGImages(
            panels: [panel],
            cgImages: [cgImage],
            crops: crops,
            title: "",
            quality: 0.9
        )

        #expect(data != nil)
        #expect(data?.isEmpty == false)

        guard let data else { return }
        let resultImage = NSImage(data: data)
        #expect(resultImage != nil)
        #expect(resultImage?.size.width == 1920)
        #expect(resultImage?.size.height == 1080)
    }

    // ... other tests follow same pattern ...

    private func createSmallTestImage(color: CGColor) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: CGBitmapInfo = [.byteOrder32Big]

        // 100x100 is safe for test environment
        let context = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        )!

        context.translateBy(x: 0, y: 100)
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))

        return context.makeImage()!
    }
}
```

---

## 9. Swift Testing Framework Patterns Used

### `#expect` — Assertions
```swift
#expect(value == expected)           // Equality
#expect(value != nil)                // Non-nil
#expect(value > 0)                   // Comparison
#expect(throws: Never.self) { ... }  // No error thrown
```

### `#throw` — Expect Error
```swift
#throw(try await analyzer.analyze(emptyImage))
```

### `Issue.record` — Conditional Failure
```swift
guard let url = Bundle.module.url(forResource: "test", withExtension: "jpg")
else {
    Issue.record("Test resource not found")
    return
}
```

### `@Test` with Parameters
```swift
@Test(.disabled()) func skippedTest() { }

@Test("arg: ", [1, 2, 3, 4, 5, 6, 7, 9, 10])
func panelCountForImageCount(_ count: Int) async throws {
    let panels = LayoutGenerator.generate(numImages: count, heroIndex: nil)
    #expect(panels.count == count)
}
```

### `@MainActor` Tests
```swift
@MainActor
struct ViewModelTests {
    @Test func testState() async throws { ... }
}
```

---

## 10. Recommended Test File Structure

```
CollageMakerTests/
  CollageMakerTests.swift          # Current file (reorganize)
  Resources/
    test-photo.jpg                  # Real image for Vision tests
    test-photo-landscape.jpg        # Landscape variant
    test-photo-portrait.jpg         # Portrait variant
```

**Future split (when test count grows):**
```
  LayoutGeneratorTests.swift
  SaliencyResultTests.swift
  CollageAssemblerTests.swift
  ImagePanelTests.swift
  SaliencyAnalyzerTests.swift      # New — needs real images
  CollageViewModelTests.swift      # New — needs @MainActor
  MockSaliencyAnalyzer.swift       # New — protocol mock
  TestHelpers.swift                # Shared fixtures
```

---

## 11. Immediate Next Steps

1. **Fix CollageAssembler tests** — Use 100x100 images instead of 1920x1080
2. **Add LayoutGenerator tests** — Overlap, hero size, gutter spacing
3. **Add SaliencyResult tests** — Exact coordinates, portrait images
4. **Add ImagePanel tests** — Codable round-trip, inequality
5. **Add test image resources** — For SaliencyAnalyzer integration tests
6. **Add CollageViewModel tests** — State transitions, layout regeneration
7. **Consider protocol-based mocking** — For Vision framework isolation
