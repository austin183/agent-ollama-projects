import AppKit
import SwiftUI

struct ColorWellView: NSViewRepresentable {
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
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
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
