# Window Management

macOS 15+ SwiftUI window and scene customization. For older deployment targets, use AppKit bridging or availability guards.

**See also:** `references/windowing.md` — Scene types (`WindowGroup`, `Window`, `DocumentGroup`) and when to use each.

## Workflow

1. Classify the window role: main navigation, utility, About/support, media playback, welcome, or borderless custom surface
2. Adjust toolbar/title presentation
3. If toolbar hidden, add drag region with `WindowDragGesture`
4. Refine behavior: minimize, restoration, resize, launch
5. Set default/ideal placement
6. If SwiftUI modifiers aren't enough, use `appkit-interop` for `NSWindow` bridge

## Toolbar and Title

- `.toolbar(removing: .title)` — keep title for accessibility/menus, hide visually
- `.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)` — extend content to top edge
- `.toolbarVisibility(.hidden, for: .windowToolbar)` — remove toolbar entirely
- Remove custom toolbar backgrounds before layering new SwiftUI toolbar APIs
- Keep logical title meaningful even when hidden

## Drag Regions

When toolbar background or whole toolbar is hidden:

```swift
.overlay(alignment: .top) {
  Color.clear
    .frame(height: 48)
    .contentShape(Rectangle())
    .gesture(WindowDragGesture())
    .allowsWindowActivationEvents(true)
}
```

- Attach to transparent overlay or non-interactive header region
- For media players with controls, insert drag overlay between content and controls
- Pair with `.allowsWindowActivationEvents(true)` for click-then-drag activation

## Background and Materials

- `.containerBackground(.thickMaterial, for: .window)` — frosted utility/About window
- Prefer system materials over hardcoded translucent colors

## Window Behavior

- `.windowMinimizeBehavior(.disabled)` — utility windows where minimizing adds no value
- `.restorationBehavior(.disabled)` — About panels, transient windows, first-run surfaces
- `.defaultLaunchBehavior(.presented)` — welcome windows that should appear at launch
- Keep restoration enabled for primary document/navigation windows

## Window Placement

```swift
.defaultWindowPlacement { content, context in
  let idealSize = content.sizeThatFits(.unspecified)
  let displayBounds = context.defaultDisplay.visibleRect
  let fittedSize = clampToDisplay(idealSize, displayBounds: displayBounds)
  return WindowPlacement(size: fittedSize)
}
.windowIdealPlacement { content, context in
  let idealSize = content.sizeThatFits(.unspecified)
  let displayBounds = context.defaultDisplay.visibleRect
  let zoomedSize = zoomToFit(idealSize, displayBounds: displayBounds)
  let position = centeredPosition(for: zoomedSize, in: displayBounds)
  return WindowPlacement(position, size: zoomedSize)
}
```

- Default placement = where new window first appears
- Ideal placement = zoom behavior (Window menu, Option-click green button)
- Always consider external displays and rotated/narrow screens

## Borderless Windows

- `.windowStyle(.plain)` — borderless or highly custom chrome
- Must provide clear drag/move affordance and visible context
- Keep one clear path back to regular window management

## Examples

```swift
Window("About", id: "about") {
  AboutView()
    .toolbar(removing: .title)
    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    .containerBackground(.thickMaterial, for: .window)
}
.windowMinimizeBehavior(.disabled)
.restorationBehavior(.disabled)
```

```swift
WindowGroup("Player", for: Video.self) { $video in
  PlayerView(video: video)
}
.defaultWindowPlacement { content, context in
  let idealSize = content.sizeThatFits(.unspecified)
  let displayBounds = context.defaultDisplay.visibleRect
  let fittedSize = clampToDisplay(idealSize, displayBounds: displayBounds)
  return WindowPlacement(size: fittedSize)
}
```

## Guardrails

- Do not use `.toolbar(removing: .title)` to hide a title you forgot to set
- Do not hide toolbar without replacing drag affordance
- Do not disable restoration on main document/navigation window
- Do not hardcode one monitor size for player/document windows
- Do not reach for `NSWindow` before checking SwiftUI modifiers
- Do not leave a plain borderless window without drag or close path
