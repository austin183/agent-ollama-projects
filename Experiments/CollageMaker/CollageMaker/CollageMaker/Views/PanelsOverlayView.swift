import SwiftUI

/// Renders layered-mode panel overlays and double exposure overlay.
struct PanelsOverlayView: View {
    let viewModel: CollageViewModel
    let panelFrames: [UUID: CGRect]
    let geometrySize: CGSize

    var body: some View {
        if viewModel.isLayeredMode {
            ForEach(viewModel.panels) { panel in
                PanelOverlay(
                    panel: panel,
                    scaledFrame: panelFrames[panel.id],
                    viewModel: viewModel
                )
            }

            if let overlayImg = viewModel.overlayImage {
                Image(nsImage: overlayImg)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geometrySize.width, height: geometrySize.height)
                    .blendMode(overlayBlendMode(from: viewModel.overlayBlendMode))
            }

            if let titleImg = viewModel.titleImage {
                Image(nsImage: titleImg)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geometrySize.width, height: geometrySize.height)
            }
        }
    }
}
