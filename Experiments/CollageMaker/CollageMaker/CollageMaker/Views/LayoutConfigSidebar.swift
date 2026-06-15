import AppKit
import SwiftUI

struct LayoutConfigSidebar: View {
    @Bindable var viewModel: CollageViewModel
    let chooseMaskImage: () -> Void

    var layoutStyleBinding: Binding<LayoutStyle> {
        Binding(
            get: { viewModel.layoutManager.layoutStyle },
            set: { viewModel.setLayoutStyle($0) }
        )
    }

    var gutterBinding: Binding<CGFloat> {
        Binding(
            get: { viewModel.layoutManager.gutter },
            set: { viewModel.setGutter($0) }
        )
    }

    var diagonalSliceAngleBinding: Binding<CGFloat> {
        Binding(
            get: { viewModel.layoutManager.diagonalSliceAngle },
            set: { viewModel.setDiagonalSliceAngle($0) }
        )
    }

    var hexagonalSpacingBinding: Binding<CGFloat> {
        Binding(
            get: { viewModel.layoutManager.hexagonalSpacing },
            set: { viewModel.setHexagonalSpacing($0) }
        )
    }

    var doubleExposureMaskOpacityBinding: Binding<CGFloat> {
        Binding(
            get: { viewModel.layoutManager.doubleExposureMaskOpacity },
            set: { viewModel.setDoubleExposureMaskOpacity($0) }
        )
    }

    var body: some View {
        Section("Layout") {
            Picker("Style", selection: layoutStyleBinding) {
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
            .accessibilityValue(viewModel.layoutManager.layoutStyle.title)

            VStack(alignment: .leading) {
                HStack {
                    Text("Gutter")
                    Spacer()
                    Text("\(Int(viewModel.layoutManager.gutter))pt")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                Slider(value: gutterBinding, in: 0...20, step: 1)
                    .accessibilityLabel("Gutter width")
                    .accessibilityValue("\(Int(viewModel.layoutManager.gutter)) points")
            }

            if viewModel.layoutManager.layoutStyle == .diagonalSlices {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Slice Angle")
                        Spacer()
                        Text("\(Int(viewModel.layoutManager.diagonalSliceAngle))°")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    Slider(value: diagonalSliceAngleBinding, in: 0...75, step: 1)
                        .accessibilityLabel("Diagonal slice angle")
                        .accessibilityValue("\(Int(viewModel.layoutManager.diagonalSliceAngle)) degrees")
                }
            }

            if viewModel.layoutManager.layoutStyle == .hexagonal {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Hex Spacing")
                        Spacer()
                        Text("\(Int(viewModel.layoutManager.hexagonalSpacing))pt")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    Slider(value: hexagonalSpacingBinding, in: 0...30, step: 1)
                        .accessibilityLabel("Hexagonal spacing")
                        .accessibilityValue("\(Int(viewModel.layoutManager.hexagonalSpacing)) points")
                }
            }

            if viewModel.layoutManager.layoutStyle == .doubleExposure {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if let maskImg = viewModel.layoutManager.doubleExposureMaskImage {
                            Image(nsImage: maskImg)
                                .resizable()
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        } else {
                            Image(systemName: "photo.badge.plus")
                                .frame(width: 32, height: 32)
                                .foregroundStyle(.secondary)
                        }

                        Button("Choose Mask") {
                            chooseMaskImage()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Choose mask image")
                        .accessibilityHint("Opens file picker")

                        Spacer()

                        if viewModel.layoutManager.doubleExposureMaskImage != nil {
                            Button {
                                viewModel.setMaskImage(nil, path: nil)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove mask image")
                        }
                    }

                    HStack {
                        Text("Mask Opacity")
                        Spacer()
                        Text("\(Int(viewModel.layoutManager.doubleExposureMaskOpacity * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    Slider(value: doubleExposureMaskOpacityBinding, in: 0...1)
                        .accessibilityLabel("Mask opacity")
                        .accessibilityValue("\(Int(viewModel.layoutManager.doubleExposureMaskOpacity * 100)) percent")
                }
            }
        }
    }
}
