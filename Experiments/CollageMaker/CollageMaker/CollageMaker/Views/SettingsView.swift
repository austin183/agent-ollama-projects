import AppKit
import SwiftUI

struct UserDefaultsColorView: NSViewRepresentable {
    @Binding var color: NSColor
    let key: String
    let defaultValue: NSColor

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell()
        well.alphaValue = 1.0

        if let hex = UserDefaults.standard.string(forKey: key),
           let saved = NSColor(rgbaHex: hex) {
            color = saved
        } else {
            color = defaultValue
        }

        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        well.color = color
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(color: $color, key: key)
    }

    class Coordinator: NSObject {
        let colorBinding: Binding<NSColor>
        let key: String

        init(color: Binding<NSColor>, key: String) {
            self.colorBinding = color
            self.key = key
        }

        @objc func colorChanged(_ sender: NSColorWell) {
            colorBinding.wrappedValue = sender.color
            UserDefaults.standard.set(sender.color.rgbaHex, forKey: key)
        }
    }
}

struct SettingsView: View {
    @AppStorage(UserDefaultsPersistence.Keys.layoutStyle) private var defaultLayout = "hero"
    @AppStorage(UserDefaultsPersistence.Keys.gutter) private var defaultGutter: Double = 8
    @AppStorage(UserDefaultsPersistence.Keys.exportQuality) private var defaultQuality: Double = 0.92
    @AppStorage(UserDefaultsPersistence.Keys.defaultTitle) private var defaultTitle = ""
    @AppStorage(UserDefaultsPersistence.Keys.defaultFontFamily) private var defaultFontFamily = ""
    @AppStorage(UserDefaultsPersistence.Keys.defaultFontSize) private var defaultFontSize: Double = 48
    @AppStorage(UserDefaultsPersistence.Keys.defaultExportFolder) private var defaultExportFolder = ""
    @AppStorage(UserDefaultsPersistence.Keys.backgroundStyle) private var settingsBackgroundStyle = "solid"

    @State private var solidColor: NSColor = .black
    @State private var gradientStart: NSColor = .black
    @State private var gradientEnd: NSColor = .darkGray
    @State private var gradientAngleValue: Double = 0

    @State private var solidLoaded = false
    @State private var gradStartLoaded = false
    @State private var gradEndLoaded = false

    private var backgroundStyleRaw: BackgroundStyle {
        BackgroundStyle(rawValue: settingsBackgroundStyle) ?? .solid
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }

            appearanceTab
                .tabItem { Label("Appearance", systemImage: "paintpalette") }

            textTab
                .tabItem { Label("Text", systemImage: "textformat") }

            exportTab
                .tabItem { Label("Export", systemImage: "arrowshape.turn.up.right") }
        }
        .frame(minWidth: 420, minHeight: 280)
        .scenePadding()
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Defaults") {
                Picker("Default Layout", selection: $defaultLayout) {
                    ForEach(LayoutStyle.allCases) { style in
                        Text(style.title).tag(style.rawValue)
                    }
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Default Gutter")
                        Spacer()
                        Text("\(Int(defaultGutter))pt")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    Slider(value: $defaultGutter, in: 0...20, step: 1)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Appearance Tab

    private var appearanceTab: some View {
        Form {
            Section("Background") {
                Picker("Background Style", selection: $settingsBackgroundStyle) {
                    Text("Solid").tag("solid")
                    Text("Gradient").tag("gradient")
                }
                .pickerStyle(.segmented)

                if backgroundStyleRaw == .solid {
                    HStack {
                        Text("Color")
                        Spacer()
                        UserDefaultsColorView(color: $solidColor, key: UserDefaultsPersistence.Keys.backgroundColor, defaultValue: .black)
                            .frame(width: 32, height: 22)
                    }
                } else if backgroundStyleRaw == .gradient {
                    HStack {
                        Text("Start")
                        Spacer()
                        UserDefaultsColorView(color: $gradientStart, key: UserDefaultsPersistence.Keys.gradientStartColor, defaultValue: .black)
                            .frame(width: 32, height: 22)
                    }

                    HStack {
                        Text("End")
                        Spacer()
                        UserDefaultsColorView(color: $gradientEnd, key: UserDefaultsPersistence.Keys.gradientEndColor, defaultValue: .darkGray)
                            .frame(width: 32, height: 22)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Angle")
                            Spacer()
                            Text("\(Int(gradientAngleValue))°")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        Slider(value: $gradientAngleValue, in: 0...360, step: 1)
                            .onChange(of: gradientAngleValue) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: UserDefaultsPersistence.Keys.gradientAngle)
                            }
                    }
                    .onAppear {
                        gradientAngleValue = UserDefaults.standard.double(forKey: UserDefaultsPersistence.Keys.gradientAngle)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Text Tab

    private var textTab: some View {
        Form {
            Section("Title Defaults") {
                TextEditor(text: $defaultTitle)
                    .frame(minHeight: 80)

                displayFontPicker

                VStack(alignment: .leading) {
                    HStack {
                        Text("Font Size")
                        Spacer()
                        Text("\(Int(defaultFontSize))pt")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    Slider(value: $defaultFontSize, in: 12...120, step: 1)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var displaySettingsFont: String {
        defaultFontFamily.isEmpty ? "(System Default)" : defaultFontFamily
    }

    private var displayFontPicker: some View {
        FontPickerPopover(selectedFamily: Binding(
            get: { displaySettingsFont },
            set: {
                defaultFontFamily = $0 == "(System Default)" ? "" : $0
            }
        ))
    }

    // MARK: - Export Tab

    private var exportTab: some View {
        Form {
            Section("Export Settings") {
                HStack {
                    Text("Default Folder")
                    Spacer()
                    Button("Choose Folder") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.begin { response in
                            if response == .OK, let url = panel.url {
                                defaultExportFolder = url.path
                            }
                        }
                    }
                }

                if !defaultExportFolder.isEmpty {
                    Text(defaultExportFolder)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Quality")
                        Spacer()
                        Text("\(Int(defaultQuality * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    Slider(value: $defaultQuality, in: 0.5...1.0, step: 0.01)
                }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView()
}
