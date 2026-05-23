import SwiftUI

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

        CommandMenu("Layout") {
            Button("Uniform") {
                viewModel.layoutStyle = .uniform
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Hero") {
                viewModel.layoutStyle = .hero
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Mosaic") {
                viewModel.layoutStyle = .mosaic
            }
            .keyboardShortcut("3", modifiers: .command)
        }
    }
}
