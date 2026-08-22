# AppKit Testing Patterns — Headless Environments and NSApplication

## The Headless Test Environment Problem

When running tests via `xcodebuild` or in CI, macOS test runners may not have a full display server session. This affects:
- `CGContext` creation with certain bitmap info flags
- `NSImage` operations that require a graphics context
- `NSGraphicsContext.current` returning `nil`
- `NSApplication` not being initialized

## NSApplication Initialization

### The Problem
Many AppKit operations (NSImage, NSColor, NSFont, NSBitmapImageRep) require `NSApplication.shared` to be initialized. In test targets, this doesn't happen automatically.

### The Fix: `@Suite` Initialization
```swift
import Testing
import AppKit

@Suite
struct AppKitInit {
    init() {
        // Initializes NSApplication.shared before any tests run
        _ = NSApplication.shared
    }
}
```

**Why `@Suite`:** The `@Suite` struct's `init()` runs before any `@Test` methods in the same file, ensuring AppKit is ready.

### Alternative: `@Test(.dependencies)`
```swift
@Test(.dependencies(AppKitInit.self))
func testSomething() {
    // Guaranteed to run after AppKitInit
}
```

## CGContext in Test Environments

### Bitmap Info Flags That Fail
```swift
// FAILS in headless tests — returns nil
let context = CGContext(
    data: nil,
    width: 1920,
    height: 1080,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)

// WORKS — combine byte order with alpha info
let context = CGContext(
    data: nil,
    width: 1920,
    height: 1080,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: [.byteOrder32Big, .noneSkipLast].rawValue
)
```

### Why `.byteOrder32Big` Alone Fails
- `.byteOrder32Big` specifies pixel byte ordering but **no alpha channel definition**
- In headless environments, the graphics subsystem rejects undefined formats
- Adding `.noneSkipLast` explicitly defines the 4th byte as unused, making the format well-defined

### Test-Safe CGImage Creation
```swift
func createTestCGImage(size: CGSize, color: CGColor) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo: CGBitmapInfo = [.byteOrder32Big, .noneSkipLast]
    
    // Use small sizes for tests (100x100 or 400x225)
    guard let context = CGContext(
        data: nil,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
    ) else {
        fatalError("Failed to create CGContext — is NSApplication initialized?")
    }
    
    // Flip to top-left origin
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)
    
    context.setFillColor(color)
    context.fill(CGRect(origin: .zero, size: size))
    
    guard let image = context.makeImage() else {
        fatalError("makeImage() returned nil — check bitmapInfo and NSApplication")
    }
    return image
}
```

## NSImage in Tests

### Creating Test NSImages
```swift
// Method 1: From CGImage (requires NSApplication)
func createTestNSImage(size: CGSize, color: NSColor) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    color.set()
    CGRect(origin: .zero, size: size).fill()
    image.unlockFocus()
    return image
}

// Method 2: From CGImage bridge
func createTestNSImage(from cgImage: CGImage) -> NSImage {
    NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
}

// Method 3: NSBitmapImageRep (most reliable in tests)
func createTestNSImageBitmap(size: CGSize, color: NSColor) -> NSImage {
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

### NSImage → CGImage in Tests
```swift
// May return nil in headless tests if NSApplication isn't initialized
let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)

// More reliable — use a specific graphics context
nsImage.lockFocus()
let context = NSGraphicsContext.current!.cgContext
let cgImage = nsImage.cgImage(forProposedRect: nil, context: NSGraphicsContext.current, hints: nil)
nsImage.unlockFocus()
```

## @MainActor and @testable Import

### The Isolation Propagation Problem
When your main target has `@MainActor` types and your test target uses `@testable import`:
```swift
@testable import CollageMaker

// CollageViewModel is @MainActor — this propagates to test code
struct CollageViewModelTests {
    // ERROR: CollageViewModel is @MainActor-isolated, but this test is not
    @Test func testSomething() {
        let vm = CollageViewModel()  // Cross-actor access
    }
}
```

### The Fix: Mark Test Structs as @MainActor
```swift
@MainActor
struct CollageViewModelTests {
    @Test func testSomething() async throws {
        let vm = CollageViewModel()
        // Now on MainActor — can access @MainActor properties
    }
}
```

**Note:** `@MainActor` test methods must be `async` because the test runner schedules them on the main actor.

## Swift Testing Framework — xcodebuild Quirks

### Running Specific Tests
```bash
# Run all tests in a test struct
xcodebuild test -only-testing:CollageMakerTests/CollageMakerTests.LayoutGeneratorTests

# Run a specific test
xcodebuild test -only-testing:CollageMakerTests/CollageMakerTests.LayoutGeneratorTests/testOneImage
```

### Swift Testing vs XCTest
- Swift Testing (`@Test`, `#expect`) requires explicit target specification
- XCTest UI tests may run by default — use `-only-testing:` to isolate
- Test output parsing differs between frameworks

### Bundle.module for Test Resources
```swift
// Access test resources (images, fixtures)
guard let url = Bundle.module.url(forResource: "test-photo", withExtension: "jpg")
else {
    Issue.record("Test resource not found")
    return
}
```

**Setup:**
1. Add resource files to test target
2. In Xcode: check "Copy items if needed"
3. Ensure test target's "Bundle Loader" is set correctly

## CGColorSpace in Tests

### Creating Color Spaces
```swift
// Preferred — always succeeds
let colorSpace = CGColorSpaceCreateDeviceRGB()

// May fail in some environments
guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
    fatalError("sRGB color space not available")
}

// For tests — use DeviceRGB for reliability
let colorSpace = CGColorSpaceCreateDeviceRGB()
```

## Summary: CollageMaker Testing Rules

1. **Always initialize `NSApplication.shared`** via `@Suite struct AppKitInit` before tests run
2. **Mark test structs as `@MainActor`** when testing `@MainActor` types with `@testable import`
3. **Use `[.byteOrder32Big, .noneSkipLast]`** for CGContext bitmap info in tests
4. **Use small test images** (100x100 or 400x225) — not 1920x1080
5. **Use `CGColorSpaceCreateDeviceRGB()`** instead of `CGColorSpace(name:)` for reliability
6. **Use `NSBitmapImageRep`** as fallback when CGContext fails
7. **Use `Bundle.module`** for test resources, not `Bundle.main`
8. **Use `-only-testing:`** with xcodebuild to target Swift Testing framework tests specifically
