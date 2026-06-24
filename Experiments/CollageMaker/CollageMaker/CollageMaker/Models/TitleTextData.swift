import AppKit
import Foundation

/// A single font run extracted from an NSAttributedString on the main actor.
struct TitleTextRun: Sendable {
    let range: NSRange
    let fontFamily: String?
    let symbolicTraitsRawValue: UInt32
}

/// Sendable representation of attributed text for crossing concurrency boundaries.
struct TitleTextData: Sendable {
    let text: String
    let runs: [TitleTextRun]

    /// Extract text and font run information from an NSAttributedString.
    /// Must be called on the main actor.
    @MainActor
    static func extract(from attrString: NSAttributedString) -> TitleTextData {
        var runs: [TitleTextRun] = []
        attrString.enumerateAttribute(.font, in: NSRange(location: 0, length: attrString.length), options: []) { value, range, _ in
            if let font = value as? NSFont {
                let rawValue = UInt32(font.fontDescriptor.symbolicTraits.rawValue)
                runs.append(TitleTextRun(
                    range: range,
                    fontFamily: font.familyName,
                    symbolicTraitsRawValue: rawValue
                ))
            } else {
                runs.append(TitleTextRun(
                    range: range,
                    fontFamily: nil,
                    symbolicTraitsRawValue: 0
                ))
            }
        }
        return TitleTextData(text: attrString.string, runs: runs)
    }
}
