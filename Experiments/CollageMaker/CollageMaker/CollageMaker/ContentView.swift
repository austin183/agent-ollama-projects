import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

private let logger = Logger(
    subsystem: "austin183.indie.CollageMaker",
    category: "Sidebar"
)

struct ContentView: View {
    @Bindable var viewModel: CollageViewModel
    @Environment(\.showingClearAlert) private var showingClearAlert
    @State private var isDragging = false
    @State private var searchQuery = ""
    @State     private var isDetailCollapsed = false

    private var filteredImages: [(index: Int, item: ImageItem)] {
        if searchQuery.isEmpty {
            return viewModel.imageLibrary.images.enumerated().map { ($0.offset, $0.element) }
        } else {
            return viewModel.imageLibrary.images.enumerated()
                .filter { $0.element.filename.localizedCaseInsensitiveContains(searchQuery) }
                .map { ($0.offset, $0.element) }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            HStack(spacing: 0) {
                CollageEditorView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !isDetailCollapsed {
                    detail
                }
            }
            .frame(minWidth: 400, minHeight: 300)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Task { [weak viewModel] in
                            await viewModel?.exportCollage()
                        }
                    } label: {
                        Label("Export", systemImage: "arrowshape.down.circle.fill")
                    }
                    .disabled(viewModel.isProcessing || viewModel.imageLibrary.images.isEmpty)
                    .accessibilityLabel("Export collage as JPEG")
                    .accessibilityHint("Opens save dialog")

                    Button {
                        viewModel.browseImages()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .help("Add Images")
                    .accessibilityLabel("Add Images")
                    .accessibilityHint("Opens file picker")

                    Button {
                        isDetailCollapsed.toggle()
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .help("Toggle Right Sidebar")
                    .accessibilityLabel("Toggle Right Sidebar")
                }
            }
        }
        .alert("Clear All Images?", isPresented: showingClearAlert) {
            Button("Clear All", role: .destructive) {
                viewModel.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all images from the collage. Use Undo to reverse.")
        }
    }

    private var sidebar: some View {
        Form {
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
                                viewModel.removeImage(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("Remove", role: .destructive) {
                                viewModel.removeImage(at: index)
                            }
                        }
                        .onTapGesture {
                            viewModel.selectPanelForImage(at: index)
                            isDetailCollapsed = false
                        }
                    }
                    .onMove { from, to in
                        viewModel.moveImages(from: from, to: to)
                    }
                }

                Button {
                    viewModel.browseImages()
                } label: {
                    Label("Add Images", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add Images")
                .accessibilityHint("Opens file picker")
            }

            Section("Layout") {
                Picker("Style", selection: $viewModel.layoutStyle) {
                    ForEach(LayoutStyle.allCases) { style in
                        HStack {
                            Image(systemName: style.icon)
                            Text(style.title)
                        }
                        .tag(style)
                    }
                }
                .pickerStyle(.inline)
                .accessibilityLabel("Layout style")
                .accessibilityValue(viewModel.layoutStyle.title)

                VStack(alignment: .leading) {
                    HStack {
                        Text("Gutter")
                        Spacer()
                        Text("\(Int(viewModel.gutter))pt")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    Slider(value: $viewModel.gutter, in: 0...20, step: 1)
                        .accessibilityLabel("Gutter width")
                        .accessibilityValue("\(Int(viewModel.gutter)) points")
                }
            }

            if !viewModel.imageLibrary.images.isEmpty {
                Section("Status") {
                    HStack {
                        if viewModel.isProcessing {
                            ProgressView()
                                .frame(width: 16, height: 16)
                                .accessibilityHidden(true)
                            Text(viewModel.exportManager.isExporting
                                ? "Exporting collage..."
                                : "Analyzing \(viewModel.imageLibrary.images.count) image(s)...")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Processing status")
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .accessibilityLabel("Ready")
                            Text("Ready")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }

            if viewModel.panels.count < viewModel.imageLibrary.images.count {
                Section("Notice") {
                    Label(
                        "Only \(viewModel.panels.count) of \(viewModel.imageLibrary.images.count) images are in the layout",
                        systemImage: "info.circle"
                    )
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .overlay {
            if isDragging {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.9))
                    .overlay {
                        VStack {
                            Image(systemName: "square.and.arrow.down")
                                .font(.title2)
                            Text("Drop images")
                                .font(.headline)
                        }
                        .foregroundStyle(.tint)
                    }
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDragging) { providers in
            Task {
                await handleDrop(from: providers)
            }
            return true
        }
        .onTapGesture {
            if viewModel.imageLibrary.images.isEmpty {
                viewModel.browseImages()
            }
        }
    }

    private func handleDrop(from providers: [NSItemProvider]) async {
        logger.info("Drop received: \(providers.count) provider(s)")

        let handler = DropHandler()
        let loadedUrls = await handler.loadImageURLs(from: providers)

        if !loadedUrls.isEmpty {
            logger.info("Loaded \(loadedUrls.count) image(s) from drop")
            await viewModel.addImages(from: loadedUrls)
        }
    }

    private var detail: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let selectedId = viewModel.selectedPanelId,
                   let panel = viewModel.panels.first(where: { $0.id == selectedId }) {
                    PanelCropEditor(panel: panel, viewModel: viewModel)
                        .id(panel.id)
                }

                ExportPanel(viewModel: viewModel)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}
