import AppKit
import Foundation
import Testing
@testable import CollageMaker

// MARK: - Note on Build Artifacts

// If tests that expect NSFont.boldSystemFont(ofSize:) to return a bold, sized font
// fail with a 12-point non-bold result (typically .monospacedDigit), the compiled
// artifacts are stale. Clean the build folder (Product → Clean Build Folder, ⇧⌘K)
// and re-run before investigating logic bugs.

@Suite struct FontMergerTests {

    // MARK: - Default font with empty family

    @Test func emptyFamilyReturnsBoldSystemFont() {
        let font = FontMerger.merge(nil, baseFamily: "", targetSize: 36)

        #expect(font.pointSize == 36)
        #expect(font.fontDescriptor.symbolicTraits.contains(.bold))
    }

    // MARK: - Default font with named family

    @Test func validNamedFamilyReturnsNamedFont() {
        let font = FontMerger.merge(nil, baseFamily: "Helvetica", targetSize: 24)

        #expect(font.pointSize == 24)
    }

    @Test func invalidNamedFamilyFallsBackToBoldSystemFont() {
        let font = FontMerger.merge(nil, baseFamily: "NonExistentFontFamilyXYZ123", targetSize: 24)

        #expect(font.pointSize == 24)
        #expect(font.fontDescriptor.symbolicTraits.contains(.bold))
    }

    // MARK: - Nil existing font

    @Test func nilExistingWithEmptyFamily() {
        let font = FontMerger.merge(nil, baseFamily: "", targetSize: 48)

        #expect(font.pointSize == 48)
    }

    @Test func nilExistingWithValidFamily() {
        let font = FontMerger.merge(nil, baseFamily: "Helvetica", targetSize: 48)

        #expect(font.pointSize == 48)
    }

    // MARK: - Trait merging: bold

    @Test func mergesBoldTrait() {
        let boldFont = NSFont.boldSystemFont(ofSize: 20)
        let merged = FontMerger.merge(boldFont, baseFamily: "Helvetica", targetSize: 36)

        #expect(merged.pointSize == 36)
        #expect(merged.fontDescriptor.symbolicTraits.contains(.bold))
    }

    // MARK: - Trait merging: italic

    @Test func mergesItalicTrait() {
        let baseDescriptor = NSFont.systemFont(ofSize: 20).fontDescriptor
        let italicDescriptor = baseDescriptor.withSymbolicTraits(.italic)
        let italicFont = NSFont(descriptor: italicDescriptor, size: 20) ?? NSFont.systemFont(ofSize: 20)
        let merged = FontMerger.merge(italicFont, baseFamily: "Helvetica", targetSize: 36)

        #expect(merged.pointSize == 36)
        #expect(merged.fontDescriptor.symbolicTraits.contains(.italic))
    }

    // MARK: - Trait merging: combined traits

    @Test func mergesMultipleTraits() {
        let descriptor = NSFont.systemFont(ofSize: 20).fontDescriptor.withSymbolicTraits([.bold, .italic])
        let combinedFont = NSFont(descriptor: descriptor, size: 20) ?? NSFont.systemFont(ofSize: 20)
        let merged = FontMerger.merge(combinedFont, baseFamily: "Helvetica", targetSize: 36)

        #expect(merged.pointSize == 36)
        #expect(merged.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(merged.fontDescriptor.symbolicTraits.contains(.italic))
    }

    // MARK: - Target size always applied

    @Test func targetSizeOverridesExistingSize() {
        let existing = NSFont.systemFont(ofSize: 12)
        let merged = FontMerger.merge(existing, baseFamily: "", targetSize: 72)

        #expect(merged.pointSize == 72)
    }

    // MARK: - Edge cases

    @Test func zeroTargetSizeDoesNotCrash() {
        let merged = FontMerger.merge(nil, baseFamily: "", targetSize: 0)

        #expect(merged.pointSize >= 0)
    }

    @Test func veryLargeTargetSize() {
        let merged = FontMerger.merge(nil, baseFamily: "", targetSize: 500)

        #expect(merged.pointSize == 500)
    }

    // MARK: - Base family takes precedence over existing font family

    @Test func baseFamilyOverridesExistingFamily() {
        let existing = NSFont(name: "Courier", size: 20) ?? NSFont.systemFont(ofSize: 20)
        let merged = FontMerger.merge(existing, baseFamily: "Helvetica", targetSize: 36)

        #expect(merged.pointSize == 36)
        #expect(merged.familyName == "Helvetica")
    }
}
