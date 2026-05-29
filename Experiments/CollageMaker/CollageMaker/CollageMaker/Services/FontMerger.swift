import AppKit

struct FontMerger {
    static func merge(
        _ existingFont: NSFont?,
        baseFamily: String,
        targetSize: CGFloat
    ) -> NSFont {
        let defaultFont: NSFont
        if baseFamily.isEmpty {
            defaultFont = NSFont.boldSystemFont(ofSize: targetSize)
        } else if let namedFont = NSFont(name: baseFamily, size: targetSize) {
            defaultFont = namedFont
        } else {
            defaultFont = NSFont.boldSystemFont(ofSize: targetSize)
        }

        guard let existing = existingFont else { return defaultFont }

        let traits = existing.fontDescriptor.symbolicTraits
        let baseDescriptor = defaultFont.fontDescriptor
        let mergedDescriptor = baseDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: mergedDescriptor, size: targetSize) ?? defaultFont
    }
}
