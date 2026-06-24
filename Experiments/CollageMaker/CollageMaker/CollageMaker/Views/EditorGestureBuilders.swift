import SwiftUI

@MainActor
struct TitleDragGestureBuilder {
    let coordinator: GestureCoordinator
    let viewModel: CollageViewModel
    let titleCanvasFrame: CGRect?
    let previewSize: CGSize

    func build() -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                self.handleChanged(value: value)
            }
            .onEnded { _ in
                self.handleEnded()
            }
    }

    @MainActor
    private func handleChanged(value: DragGesture.Value) {
        if !coordinator.dragTitleLocked {
            guard titleCanvasFrame != nil else { return }
            switch viewModel.titleManager.hitTestTitle(location: value.startLocation, previewSize: previewSize) {
            case .resize(let edge):
                coordinator.dragTitleLocked = true
                coordinator.titleResizeEdge = edge
                viewModel.isDraggingTitle = true
                coordinator.oldTitleStyle = viewModel.titleStyle
            case .drag:
                coordinator.dragTitleOffset = viewModel.titleManager.computeTitleDragOffset(
                    startLocation: value.startLocation,
                    previewSize: previewSize
                )
                coordinator.dragTitleLocked = true
                coordinator.titleResizeEdge = TitleResizeEdge.none
                viewModel.isDraggingTitle = true
                coordinator.oldTitleStyle = viewModel.titleStyle
            case .none:
                break
            }
            return
        }

        if coordinator.titleResizeEdge != TitleResizeEdge.none {
            let (newWidth, posDelta) = viewModel.titleManager.computeTitleResize(
                screenLocation: value.location,
                edge: coordinator.titleResizeEdge,
                previewSize: previewSize
            )
            var style = viewModel.titleStyle
            style.width = newWidth
            style.positionX = style.positionX + posDelta
            viewModel.titleStyle = style
        } else {
            let (positionX, positionY) = viewModel.titleManager.computeTitleDragPosition(
                screenLocation: value.location,
                offset: coordinator.dragTitleOffset,
                previewSize: previewSize
            )
            var style = viewModel.titleStyle
            style.positionX = positionX
            style.positionY = positionY
            viewModel.titleStyle = style
        }
    }

    @MainActor
    private func handleEnded() {
        guard coordinator.dragTitleLocked else { return }
        if let oldStyle = coordinator.oldTitleStyle {
            viewModel.registerTitleStyleUndo(oldStyle: oldStyle)
        }
        coordinator.oldTitleStyle = nil
        viewModel.isDraggingTitle = false
        coordinator.dragTitleLocked = false
        coordinator.titleResizeEdge = TitleResizeEdge.none
        coordinator.dragTitleOffset = CGPoint.zero
        viewModel.finishTitleDrag()
    }
}

@MainActor
struct PanelSwapGestureBuilder {
    let coordinator: GestureCoordinator
    let viewModel: CollageViewModel
    let titleCanvasFrame: CGRect?
    let previewSize: CGSize

    func build() -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                self.handleChanged(value: value)
            }
            .onEnded { value in
                self.handleEnded(value: value)
            }
    }

    @MainActor
    private func handleChanged(value: DragGesture.Value) {
        guard !viewModel.isDraggingTitle else { return }

        if coordinator.dragSourcePanelId == nil {
            if titleCanvasFrame != nil,
               viewModel.titleManager.hitTestTitle(location: value.startLocation, previewSize: previewSize) != .none {
                return
            }
            if let id = viewModel.hitPanel(at: value.startLocation, previewSize: previewSize) {
                coordinator.dragSourcePanelId = id
                if let imgIdx = viewModel.getEffectiveImageIndex(for: id) {
                    coordinator.dragSourceImageIndex = imgIdx
                }
            }
        }
        if coordinator.dragSourcePanelId != nil {
            coordinator.dragTargetPanelId = viewModel.hitPanel(at: value.location, previewSize: previewSize)
            coordinator.dragCursorLocation = value.location
        }
    }

    @MainActor
    private func handleEnded(value: DragGesture.Value) {
        if viewModel.isDraggingTitle {
            coordinator.dragSourcePanelId = nil
            coordinator.dragTargetPanelId = nil
            coordinator.dragCursorLocation = nil
            return
        }
        if let sourceId = coordinator.dragSourcePanelId,
           let targetId = viewModel.hitPanel(at: value.location, previewSize: previewSize),
           sourceId != targetId {
            viewModel.swapPanelImages(sourceId: sourceId, targetId: targetId)
        }
        coordinator.dragSourcePanelId = nil
        coordinator.dragTargetPanelId = nil
        coordinator.dragCursorLocation = nil
    }
}

@MainActor
struct PinchGestureBuilder {
    let coordinator: GestureCoordinator
    let viewModel: CollageViewModel

    func build() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                self.handleChanged(value: value)
            }
            .onEnded { _ in
                self.handleEnded()
            }
    }

    @MainActor
    private func handleChanged(value: CGFloat) {
        if coordinator.pinchPanelId == nil, let id = viewModel.selectedPanelId {
            coordinator.pinchPanelId = id
            viewModel.beginPinch(panelId: id)
            viewModel.beginGestureUndo()
            viewModel.isLiveGesturing = true
        }
        if coordinator.pinchPanelId != nil {
            viewModel.pinch(magnification: value)
            if coordinator.shouldProcessPinch() {
                viewModel.applyPinchLive()
            }
        }
    }

    @MainActor
    private func handleEnded() {
        viewModel.isLiveGesturing = false
        if let id = coordinator.pinchPanelId {
            viewModel.applyPinch(panelId: id)
            viewModel.endGestureUndo(actionName: "Adjust Crop")
        }
        coordinator.pinchPanelId = nil
    }
}
