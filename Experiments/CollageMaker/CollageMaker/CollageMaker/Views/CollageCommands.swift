import SwiftUI

@MainActor
struct CollageCommands: Commands {
    let viewModel: CollageViewModel
    @Binding var showingClearAlert: Bool

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Images…") {
                viewModel.browseImages()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Clear All") {
                showingClearAlert = true
            }
        }

        CommandGroup(replacing: .saveItem) {
            Button("Export JPEG…") {
                Task {
                    await viewModel.exportCollage()
                }
            }
            .keyboardShortcut("s", modifiers: .command)
        }

        CommandMenu("View") {
            Toggle("Show Saliency Overlay", isOn: Binding(
                get: { viewModel.showSaliencyOverlay },
                set: { viewModel.showSaliencyOverlay = $0 }
            ))
            .keyboardShortcut("h", modifiers: [.command, .shift])
        }

        CommandMenu("Layout") {
            Button("Uniform") {
                viewModel.setLayoutStyle(.uniform)
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Hero") {
                viewModel.setLayoutStyle(.hero)
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Mosaic") {
                viewModel.setLayoutStyle(.mosaic)
            }
            .keyboardShortcut("3", modifiers: .command)
        }
    }
}
