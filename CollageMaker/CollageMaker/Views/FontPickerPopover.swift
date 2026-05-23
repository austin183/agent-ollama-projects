import AppKit
import SwiftUI

struct FontPickerPopover: View {
    @Binding var selectedFamily: String
    @State private var searchText = ""
    @State private var isPopoverPresented = false

    private var allFamilies: [String] {
        ["(System Default)"] + NSFontManager.shared.availableFontFamilies.sorted()
    }

    private var filteredFamilies: [String] {
        guard !searchText.isEmpty else { return allFamilies }
        return allFamilies.filter { $0.lowercased().contains(searchText.lowercased()) }
    }

    var body: some View {
        Button {
            isPopoverPresented.toggle()
        } label: {
            HStack {
                Text(selectedFamily)
                    .lineLimit(1)
                    .font(font(for: selectedFamily))
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $isPopoverPresented) {
            popoverContent
                .frame(width: 280, height: 340)
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search fonts", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredFamilies, id: \.self) { family in
                        Button {
                            selectedFamily = family
                            isPopoverPresented = false
                        } label: {
                            Text(family)
                                .font(font(for: family))
                                .padding(.horizontal)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(
                            selectedFamily == family ? Color.accentColor : Color.primary
                        )
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func font(for family: String) -> Font {
        guard !family.isEmpty, family != "(System Default)",
              let nsFont = NSFont(name: family, size: 16)
        else {
            return .system(size: 16)
        }
        return .init(nsFont)
    }
}
