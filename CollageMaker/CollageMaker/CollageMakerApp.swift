import OSLog
import SwiftUI

private let logger = Logger(
    subsystem: "austin183.indie.CollageMaker",
    category: "App"
)

@main
struct CollageMakerApp: App {
    @State private var viewModel = CollageViewModel()
    @State private var showingClearAlert = false

    init() {
        logger.info("App launched")
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .environment(\.showingClearAlert, $showingClearAlert)
        }
        .defaultSize(width: 1200, height: 750)
        .commands {
            SidebarCommands()
            CollageCommands(viewModel: viewModel, showingClearAlert: $showingClearAlert)
        }

        Settings {
            SettingsView()
        }
    }
}

private struct ShowingClearAlertKey: EnvironmentKey {
    static var defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var showingClearAlert: Binding<Bool> {
        get { self[ShowingClearAlertKey.self] }
        set { self[ShowingClearAlertKey.self] = newValue }
    }
}
