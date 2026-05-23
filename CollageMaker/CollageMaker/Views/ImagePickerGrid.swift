import SwiftUI

struct ImagePickerGrid: View {
    let images: [ImageItem]
    @Binding var selection: Int
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = ""

    private var filteredImages: [(index: Int, item: ImageItem)] {
        if searchQuery.isEmpty {
            return images.enumerated().map { ($0.offset, $0.element) }
        } else {
            return images.enumerated()
                .filter { $0.element.filename.localizedCaseInsensitiveContains(searchQuery) }
                .map { ($0.offset, $0.element) }
        }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 64), spacing: 8)
    ]

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search", text: $searchQuery)
                .padding(8)

            Divider()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(filteredImages, id: \.item.id) { index, item in
                        Button {
                            selection = index
                            dismiss()
                        } label: {
                            VStack(spacing: 4) {
                                Image(nsImage: item.thumbnail)
                                    .resizable()
                                    .frame(width: 48, height: 48)
                                    .scaledToFill()
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(
                                                selection == index ? Color.accentColor : Color.clear,
                                                lineWidth: 2
                                            )
                                    )
                                Text(item.filename)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(
                                selection == index ? Color.accentColor.opacity(0.1) : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
    }
}
