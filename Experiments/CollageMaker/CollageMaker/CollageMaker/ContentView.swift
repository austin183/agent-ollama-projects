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
                    ResizableDrawer(viewModel: viewModel)
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
        .frame(minWidth: 750, minHeight: 500)
        .task {
            let handle = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { _ in
                viewModel.saveSettings()
            }
            try? await Task.sleep(nanoseconds: .max)
            NotificationCenter.default.removeObserver(handle)
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

}

struct ResizableDrawer: View {
    @Bindable var viewModel: CollageViewModel
    @State private var drawerWidth: CGFloat = 300
    @State private var rightDrawerStartWidth: CGFloat = 0
    @State private var isHandleHovered = false

    init(viewModel: CollageViewModel) {
        self.viewModel = viewModel
        _drawerWidth = State(initialValue: viewModel.rightDrawerWidth)
    }

    var body: some View {
        HStack(spacing: 0) {
            resizeHandle
            detail
                .frame(width: drawerWidth)
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

    private var resizeHandle: some View {
        Rectangle()
            .fill(isHandleHovered
                  ? Color.secondary.opacity(0.6)
                  : Color.secondary.opacity(0.3))
            .frame(width: 4)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHandleHovered = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if rightDrawerStartWidth == 0 {
                            rightDrawerStartWidth = drawerWidth
                        }
                        let newWidth = rightDrawerStartWidth - value.translation.width
                        drawerWidth = max(200, min(800, newWidth))
                    }
                    .onEnded { _ in
                        viewModel.rightDrawerWidth = drawerWidth
                        rightDrawerStartWidth = 0
                    }
            )
    }
}
