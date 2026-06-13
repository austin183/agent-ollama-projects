import SwiftUI

struct StatusSidebar: View {
    @Bindable var viewModel: CollageViewModel

    var body: some View {
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
}
