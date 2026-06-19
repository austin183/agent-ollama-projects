import SwiftUI

/// Renders the canvas background: layered mode background image or composite preview.
struct CanvasBackgroundView: View {
    let viewModel: CollageViewModel
    let geometrySize: CGSize

    var body: some View {
        if viewModel.isLayeredMode {
            if let bg = viewModel.previewBackgroundImage {
                Image(nsImage: bg)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geometrySize.width, height: geometrySize.height)
            }
        } else if let previewImage = viewModel.previewImage {
            Image(nsImage: previewImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: geometrySize.width, height: geometrySize.height)
                .id("preview")
        }
    }
}
