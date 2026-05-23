import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ExportPanel: View {
    @Bindable var viewModel: CollageViewModel

    private var displayFamily: String {
        viewModel.titleStyle.fontFamily.isEmpty ? "(System Default)" : viewModel.titleStyle.fontFamily
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Background")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Background Style", selection: $viewModel.backgroundStyle) {
                    Text("Solid").tag(BackgroundStyle.solid)
                    Text("Gradient").tag(BackgroundStyle.gradient)
                    Text("Image").tag(BackgroundStyle.image)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Background style")

                switch viewModel.backgroundStyle {
                case .solid:
                    NSColorPickerView(color: $viewModel.backgroundColor)
                        .accessibilityLabel("Background color")
                        .frame(height: 28)

                case .gradient:
                    HStack(spacing: 8) {
                        NSColorPickerView(color: $viewModel.gradientStartColor)
                            .frame(width: 32, height: 28)
                        Text("Start")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        NSColorPickerView(color: $viewModel.gradientEndColor)
                            .frame(width: 32, height: 28)
                        Text("End")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("Angle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $viewModel.gradientAngle, in: 0...360)
                            .accessibilityLabel("Gradient angle")
                            .accessibilityValue("\(Int(viewModel.gradientAngle)) degrees")
                            .frame(width: 80)
                        Text("\(Int(viewModel.gradientAngle))°")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                case .image:
                    HStack(spacing: 8) {
                        if let bgImage = viewModel.backgroundImage {
                            Image(nsImage: bgImage)
                                .resizable()
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        } else {
                            Image(systemName: "photo.badge.plus")
                                .frame(width: 32, height: 32)
                                .foregroundStyle(.secondary)
                        }

                        Button("Choose Background") {
                            chooseBackgroundImage()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Choose background image")
                        .accessibilityHint("Opens file picker")

                        Spacer()

                        Text("Opacity")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $viewModel.backgroundOpacity, in: 0...1)
                            .accessibilityLabel("Background image opacity")
                            .accessibilityValue("\(Int(viewModel.backgroundOpacity * 100)) percent")
                            .frame(width: 80)
                        Text("\(Int(viewModel.backgroundOpacity * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                AttributedStringEditor(
                    attributedString: $viewModel.titleAttrString,
                    titleStyle: viewModel.titleStyle
                )
                .accessibilityLabel("Title text editor")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Title Style")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                FontPickerPopover(selectedFamily: Binding(
                    get: { displayFamily },
                    set: {
                        viewModel.titleStyle.fontFamily = $0 == "(System Default)" ? "" : $0
                    }
                ))
                .accessibilityLabel("Title font family")

                HStack(spacing: 8) {
                    Text("Size")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $viewModel.titleStyle.fontSize, in: 12...120)
                        .accessibilityLabel("Title font size")
                        .accessibilityValue("\(Int(viewModel.titleStyle.fontSize)) points")
                    Text("\(Int(viewModel.titleStyle.fontSize))pt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }

                HStack(spacing: 8) {
                    Text("Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    NSColorPickerView(color: $viewModel.titleStyle.fontColor)
                        .accessibilityLabel("Title text color")
                        .frame(width: 32, height: 24)
                    Text("BG")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    NSColorPickerView(color: $viewModel.titleStyle.backgroundColor)
                        .accessibilityLabel("Title background color")
                        .frame(width: 32, height: 24)
                    Spacer()
                    Picker("Align", selection: $viewModel.titleStyle.alignment) {
                        Image(systemName: "text.alignleft").tag(NSTextAlignment.left)
                        Image(systemName: "text.aligncenter").tag(NSTextAlignment.center)
                        Image(systemName: "text.alignright").tag(NSTextAlignment.right)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 80)
                    .accessibilityLabel("Title alignment")

                    Toggle("Title BG", isOn: $viewModel.titleStyle.showBackground)
                    .accessibilityLabel("Show title background")
                }
            }

            Divider()

            Text("Export")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Quality: \(Int(viewModel.exportQuality * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $viewModel.exportQuality, in: 0.5...1.0)
                    .accessibilityLabel("Export quality")
                    .accessibilityValue("\(Int(viewModel.exportQuality * 100)) percent")
            }

            Button(action: {
                Task { [weak viewModel] in
                    await viewModel?.exportCollage()
                }
            }) {
                HStack {
                    if viewModel.isExporting {
                        ProgressView()
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "arrowshape.down.circle.fill")
                    }
                    Text(viewModel.isExporting ? "Exporting collage..." : "Export JPEG")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isProcessing || viewModel.images.isEmpty)
            .accessibilityLabel("Export collage as JPEG")
            .accessibilityHint("Opens save dialog")

            if let success = viewModel.exportSuccessMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(success)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding(.vertical, 4)
                .transition(.opacity)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding()
        .task(id: viewModel.exportSuccessMessage) {
            if viewModel.exportSuccessMessage != nil {
                try? await Task.sleep(for: .seconds(3))
                viewModel.dismissExportSuccess()
            }
        }
    }

    private func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.jpeg, .png, .tiff, .heic, .heif]

        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.begin { [weak viewModel] response in
            if response == .OK, let url = panel.url,
                let data = try? Data(contentsOf: url),
                let image = NSImage(data: data) {
                viewModel?.backgroundImage = image
                UserDefaults.standard.set(url.path, forKey: ViewModelUserDefaultsKeys.backgroundImagePath)
                viewModel?.updatePreview()
            }
        }
    }
}

private struct NSColorPickerView: NSViewRepresentable {
    @Binding var color: NSColor

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell()
        well.isContinuous = true
        well.alphaValue = 1.0
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        well.color = color
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        well.color = color
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(color: $color)
    }

    class Coordinator: NSObject {
        @Binding var color: NSColor

        init(color: Binding<NSColor>) {
            _color = color
            super.init()
        }

        @objc func colorChanged(_ sender: NSColorWell) {
            color = sender.color
        }
    }
}
