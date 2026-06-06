import AppKit
import Combine
import SwiftUI

private func normalizeForEditor(_ attrString: NSAttributedString, fontFamily: String, alignment: NSTextAlignment) -> NSAttributedString {
    let normalized = NSMutableAttributedString()
    let editorFontSize: CGFloat = 14

    attrString.enumerateAttribute(.font, in: NSRange(location: 0, length: attrString.length), options: []) { value, range, _ in
        let newFont = FontMerger.merge(value as? NSFont, baseFamily: fontFamily, targetSize: editorFontSize)

        let sub = NSMutableAttributedString(attributedString: attrString.attributedSubstring(from: range))
        sub.addAttribute(.font, value: newFont, range: NSRange(location: 0, length: sub.length))
        sub.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: 0, length: sub.length))
        normalized.append(sub)
    }

    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = alignment
    normalized.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: normalized.length))

    return normalized
}

struct AttributedStringEditor: View {
    @Binding var attributedString: NSAttributedString
    var titleStyle: TitleStyle

    @StateObject private var textViewHolder = StyleableTextViewHolder()
    @State private var boldActive = false
    @State private var italicActive = false
    @State private var underlineActive = false

    var body: some View {
        VStack(spacing: 4) {
            AttributedStringEditorView(
                attributedString: $attributedString,
                titleStyle: titleStyle,
                textViewHolder: textViewHolder,
                onSelectionChange: { isBold, isItalic, isUnderline in
                    boldActive = isBold
                    italicActive = isItalic
                    underlineActive = isUnderline
                }
            )
            .frame(minHeight: 50)
            .padding(4)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )

            HStack(spacing: 4) {
                styleButton("B", isOn: boldActive) {
                    toggleBold()
                }
                styleButton("I", italic: true, isOn: italicActive) {
                    toggleItalic()
                }
                styleButton("ABC", isOn: underlineActive) {
                    toggleUnderline()
                }
                Spacer()
            }
        }
    }

    private func styleButton(_ label: String, italic: Bool = false, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .fontWeight(isOn ? .bold : .regular)
                .italic(italic)
                .underline(isOn)
                .font(.caption)
                .frame(width: 24, height: 20)
                .background(isOn ? Color.secondary.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private func syncBinding() {
        guard let textView = textViewHolder.textView,
              let textStorage = textView.textStorage else { return }
        let normalized = normalizeForEditor(textStorage, fontFamily: titleStyle.fontFamily, alignment: titleStyle.alignment)
        attributedString = normalized
    }

    private func fontIsBold(_ font: NSFont) -> Bool {
        font.fontDescriptor.symbolicTraits.contains(.bold)
    }

    private func fontIsItalic(_ font: NSFont) -> Bool {
        font.fontDescriptor.symbolicTraits.contains(.italic)
    }

    private func fontWithBold(_ font: NSFont, toggle: Bool) -> NSFont? {
        var traits = font.fontDescriptor.symbolicTraits
        if toggle {
            traits.insert(.bold)
        } else {
            traits.remove(.bold)
        }
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? NSFont.boldSystemFont(ofSize: font.pointSize)
    }

    private func fontWithItalic(_ font: NSFont, toggle: Bool) -> NSFont? {
        var traits = font.fontDescriptor.symbolicTraits
        if toggle {
            traits.insert(.italic)
        } else {
            traits.remove(.italic)
        }
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: font.pointSize)
    }

    private func toggleBold() {
        guard let textView = textViewHolder.textView, let textStorage = textView.textStorage else { return }
        let sel = textView.selectedRange
        guard sel.length > 0 || sel.location != NSNotFound else { return }

        let clampedLoc = min(sel.location, max(0, textStorage.length - 1))

        if sel.length > 0 {
            textStorage.enumerateAttribute(.font, in: sel, options: []) { value, range, _ in
                if let font = value as? NSFont {
                    let isBold = fontIsBold(font)
                    if let newFont = fontWithBold(font, toggle: !isBold) {
                        textStorage.addAttribute(.font, value: newFont, range: range)
                    }
                }
            }
        } else {
            let currentFont = (textStorage.attribute(.font, at: clampedLoc, effectiveRange: nil) as? NSFont)
                ?? NSFont.boldSystemFont(ofSize: 14)
            let isBold = fontIsBold(currentFont)
            if let newFont = fontWithBold(currentFont, toggle: !isBold) {
                textStorage.addAttribute(.font, value: newFont, range: sel)
                textView.typingAttributes[.font] = newFont
            }
        }
        refreshStyleState()
        syncBinding()
    }

    private func toggleItalic() {
        guard let textView = textViewHolder.textView, let textStorage = textView.textStorage else { return }
        let sel = textView.selectedRange
        guard sel.length > 0 || sel.location != NSNotFound else { return }

        let clampedLoc = min(sel.location, max(0, textStorage.length - 1))

        if sel.length > 0 {
            textStorage.enumerateAttribute(.font, in: sel, options: []) { value, range, _ in
                if let font = value as? NSFont {
                    let isItalic = fontIsItalic(font)
                    if let newFont = fontWithItalic(font, toggle: !isItalic) {
                        textStorage.addAttribute(.font, value: newFont, range: range)
                    }
                }
            }
        } else {
            let currentFont = (textStorage.attribute(.font, at: clampedLoc, effectiveRange: nil) as? NSFont)
                ?? NSFont.boldSystemFont(ofSize: 14)
            let isItalic = fontIsItalic(currentFont)
            if let newFont = fontWithItalic(currentFont, toggle: !isItalic) {
                textStorage.addAttribute(.font, value: newFont, range: sel)
                textView.typingAttributes[.font] = newFont
            }
        }
        refreshStyleState()
        syncBinding()
    }

    private func toggleUnderline() {
        guard let textView = textViewHolder.textView, let textStorage = textView.textStorage else { return }
        let sel = textView.selectedRange
        guard sel.length > 0 || sel.location != NSNotFound else { return }

        let clampedLoc = min(sel.location, max(0, textStorage.length - 1))
        let currentStyle = (textStorage.attribute(.underlineStyle, at: clampedLoc, effectiveRange: nil) as? NSNumber)?.intValue ?? 0

        if currentStyle > 0 {
            textStorage.removeAttribute(.underlineStyle, range: sel)
        } else {
            textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: sel)
        }
        refreshStyleState()
        syncBinding()
    }

    private func refreshStyleState() {
        guard let textView = textViewHolder.textView, let textStorage = textView.textStorage else { return }
        let sel = textView.selectedRange
        let loc = min(sel.location, max(0, textStorage.length - 1))

        if let font = textStorage.attribute(.font, at: loc, effectiveRange: nil) as? NSFont {
            boldActive = fontIsBold(font)
            italicActive = fontIsItalic(font)
        }
        let ulStyle = (textStorage.attribute(.underlineStyle, at: loc, effectiveRange: nil) as? NSNumber)?.intValue ?? 0
        underlineActive = ulStyle > 0
    }
}

class StyleableTextViewHolder: ObservableObject {
    let objectWillChange = PassthroughSubject<StyleableTextViewHolder, Never>()
    var textView: NSTextView? {
        didSet {
            DispatchQueue.main.async {
                self.objectWillChange.send(self)
            }
        }
    }
}

struct AttributedStringEditorView: NSViewRepresentable {
    @Binding var attributedString: NSAttributedString
    var titleStyle: TitleStyle
    @ObservedObject var textViewHolder: StyleableTextViewHolder
    var onSelectionChange: (Bool, Bool, Bool) -> Void

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView(frame: .zero)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = NSColor.clear
        textView.textColor = NSColor.labelColor
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainerInset = NSSize(width: 4, height: 4)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = titleStyle.alignment

        let editorFontSize: CGFloat = 14
        let editorFont: NSFont
        if titleStyle.fontFamily.isEmpty {
            editorFont = NSFont.boldSystemFont(ofSize: editorFontSize)
        } else {
            editorFont = NSFont(name: titleStyle.fontFamily, size: editorFontSize)
                ?? NSFont.boldSystemFont(ofSize: editorFontSize)
        }

        let defaultAttributes: [NSAttributedString.Key: Any] = [
            .font: editorFont,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle,
        ]
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = defaultAttributes

        if textView.textStorage?.string != attributedString.string {
            let normalized = normalizeForEditor(attributedString, fontFamily: titleStyle.fontFamily, alignment: titleStyle.alignment)
            textView.textStorage?.setAttributedString(normalized)
            attributedString = normalized
        }

        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.onSelectionChange = onSelectionChange
        textViewHolder.textView = textView

        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        guard let textStorage = textView.textStorage else { return }

        context.coordinator.fontFamily = titleStyle.fontFamily
        context.coordinator.alignment = titleStyle.alignment

        let editorFontSize: CGFloat = 14
        let targetFont: NSFont
        if titleStyle.fontFamily.isEmpty {
            targetFont = NSFont.boldSystemFont(ofSize: editorFontSize)
        } else {
            targetFont = NSFont(name: titleStyle.fontFamily, size: editorFontSize)
                ?? NSFont.boldSystemFont(ofSize: editorFontSize)
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = titleStyle.alignment
        textView.defaultParagraphStyle = paragraphStyle

        // Only update typingAttributes when font actually changed.
        // Unconditional assignment can trigger textDidChange and start
        // a re-render cascade that interferes with other UI controls.
        let currentFont = textView.typingAttributes[.font] as? NSFont
        if currentFont?.fontName != targetFont.fontName || currentFont?.pointSize != targetFont.pointSize {
            var typingAttrs = textView.typingAttributes
            typingAttrs[.font] = targetFont
            typingAttrs[.foregroundColor] = NSColor.white
            typingAttrs[.paragraphStyle] = paragraphStyle
            textView.typingAttributes = typingAttrs
        }

        // Only re-normalize when font family or alignment actually changed.
        let storageFont = textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let currentAlignment = (textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment
        if storageFont?.fontName == targetFont.fontName,
           storageFont?.pointSize == targetFont.pointSize,
           currentAlignment == titleStyle.alignment {
            return
        }

        // Block textDidChange during programmatic update to prevent cascade:
        // setAttributedString → textDidChange → binding write → titleAttrString.didSet
        // → updatePreview → SwiftUI re-render → updateNSView (infinite loop)
        context.coordinator.isUpdating = true
        defer { context.coordinator.isUpdating = false }

        let normalized = normalizeForEditor(textStorage, fontFamily: titleStyle.fontFamily, alignment: titleStyle.alignment)
        let sel = textView.selectedRange
        textStorage.setAttributedString(normalized)
        textView.selectedRange = sel
        attributedString = normalized
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(attributedString: $attributedString, fontFamily: titleStyle.fontFamily, alignment: titleStyle.alignment)
    }

    class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        @Binding var attributedString: NSAttributedString
        var textView: NSTextView?
        var fontFamily: String
        var alignment: NSTextAlignment
        var onSelectionChange: ((Bool, Bool, Bool) -> Void)?
        var isUpdating = false

        init(attributedString: Binding<NSAttributedString>, fontFamily: String, alignment: NSTextAlignment) {
            _attributedString = attributedString
            self.fontFamily = fontFamily
            self.alignment = alignment
            super.init()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView, let newStorage = textView.textStorage else { return }
            guard !isUpdating else { return }
            isUpdating = true
            defer { isUpdating = false }

            let normalized = normalizeForEditor(newStorage, fontFamily: fontFamily, alignment: alignment)
            attributedString = normalized
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = textView else { return }
            let sel = textView.selectedRange
            let loc = min(sel.location, max(0, textView.textStorage?.length ?? 0 - 1))

            var isBold = false
            var isItalic = false
            var isUnderline = false

            if let textStorage = textView.textStorage, loc < textStorage.length {
                if let font = textStorage.attribute(.font, at: loc, effectiveRange: nil) as? NSFont {
                    let descriptor = font.fontDescriptor
                    isBold = descriptor.symbolicTraits.contains(.bold)
                    isItalic = descriptor.symbolicTraits.contains(.italic)
                }
                let ulStyle = (textStorage.attribute(.underlineStyle, at: loc, effectiveRange: nil) as? NSNumber)?.intValue ?? 0
                isUnderline = ulStyle > 0
            }

            onSelectionChange?(isBold, isItalic, isUnderline)
        }
    }
}
