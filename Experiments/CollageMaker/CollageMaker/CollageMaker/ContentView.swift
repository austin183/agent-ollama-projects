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
                    .disabled(viewModel.isProcessing || viewModel.images.isEmpty)
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
            ImageLibrarySidebar(viewModel: viewModel, searchQuery: $searchQuery, isDetailCollapsed: $isDetailCollapsed)
            LayoutConfigSidebar(viewModel: viewModel, chooseMaskImage: { [weak viewModel] in
                Task { await viewModel?.chooseMaskImage() }
            })
            if !viewModel.images.isEmpty {
                StatusSidebar(viewModel: viewModel)
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
            if viewModel.images.isEmpty {
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
