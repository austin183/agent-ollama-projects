import SwiftUI

struct ImageLibrarySidebar: View {
    @Bindable var viewModel: CollageViewModel
    @Binding var searchQuery: String
    @Binding var isDetailCollapsed: Bool

    private var filteredImages: [(index: Int, item: ImageItem)] {
        viewModel.imageLibrary.images.indexed(by: searchQuery)
    }

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search images", text: $searchQuery)
                .accessibilityLabel("Search images")
                .font(.caption)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))

        Section("Images") {
            if viewModel.imageLibrary.images.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Drop images here")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("or click Browse")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                ForEach(filteredImages, id: \.item.id) { index, item in
                    HStack {
                        Image(nsImage: item.thumbnail)
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .scaledToFill()

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.filename)
                                .lineLimit(1)
                                .font(.caption)
                            Text("#\(index + 1)")
                                .lineLimit(1)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        Button {
                            viewModel.imageCoordinator.removeImage(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Remove", role: .destructive) {
                            viewModel.imageCoordinator.removeImage(at: index)
                        }
                    }
                    .onTapGesture {
                        viewModel.imageCoordinator.selectPanelForImage(at: index)
                        isDetailCollapsed = false
                    }
                }
                .onMove { from, to in
                    viewModel.imageCoordinator.moveImages(from: from, to: to)
                }
            }

            Button {
                viewModel.imageCoordinator.browseImages()
            } label: {
                Label("Add Images", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add Images")
            .accessibilityHint("Opens file picker")
        }
    }
}
