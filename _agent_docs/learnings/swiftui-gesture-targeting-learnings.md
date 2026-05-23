# CollageMaker Prototype 2 — Gesture Targeting & State Recursion Learnings

**Date:** 2026-05-10
**Purpose:** Document learnings from Session 4 bug fixes: gutter slider freeze and panel gesture targeting.

## What Worked

- **`DragGesture.startLocation` hit-testing** — Using `startLocation` in the first `onChanged` callback to lock onto the target panel gave reliable per-panel gesture routing. The drag gesture at the parent level with a `@State dragPanelId` flag correctly scoped pan operations to the touched panel.
- **Parent-level gesture management** — Moving all gestures from per-panel overlays to the parent `CollageEditorView` eliminated the "last overlay wins" problem entirely.
- **Tap gesture for panel selection** — A single `.onTapGesture` with `panelAt(location:in:)` hit-testing at the parent level gave clear visual feedback (white border) and predictable pinch targeting.

## What Didn't Work / Gaps

- **`.onReceive($property)` infinite recursion** — `ContentView.swift:111-114`. The Slider bound to `$viewModel.gutter`, then `.onReceive(viewModel.$gutter.dropFirst())` called `updateGutter()` which re-assigned `gutter = value`, triggering `$gutter` again. Infinite loop on the main thread, app froze. The binding already mutates the property; `.onReceive` should only trigger side effects (like `regenerateLayout()`), not re-assign the same value.

- **`.onAppear` for gesture initialization** — `PanelGestureOverlay` called `beginPan`/`beginPinch` in `.onAppear`. Since all overlays appear, the last one to render always wins, routing all gestures to that panel. `.onAppear` is not the right lifecycle hook for gesture targeting.

- **`simultaneousGesture` on multiple ZStack overlays** — The approach of overlaying clear `Rectangle`s with `.simultaneousGesture(drag)` and `.simultaneousGesture(magnify)` per panel appeared correct in theory but failed in practice. `simultaneousGesture` is designed to let gestures compete with other gestures, not to isolate per-region targeting. All overlay gestures fire simultaneously, and the last one to call `beginPan`/`applyPan` wins. This is fundamentally different from the documented "Approach 1: ZStack with Overlay Rectangles" in `swiftui-gestures.md`.

- **`MagnificationGesture` has no location** — Unlike `DragGesture`, `MagnificationGesture.Value` is a `CGFloat` with no `location` or `startLocation` property. Cannot hit-test which panel the pinch occurred over. Must target the selected panel instead.

- **`.onStarted` doesn't exist on `DragGesture`/`MagnificationGesture`** — These gesture types have no `.onStarted` modifier. The initial gesture state must be captured in the first `.onChanged` callback using a `@State` flag.

## What Was Confusing

- **Why `simultaneousGesture` on overlays didn't work** — The gesture reference documented "ZStack with Overlay Rectangles" as the recommended approach. But `simultaneousGesture` means "fire alongside other gestures," not "fire only for this region." With overlapping clear rectangles in a ZStack, all gestures compete and the last one wins. The documented approach needs correction.

- **`.onReceive` pattern double-edged** — The `.onReceive(publisher.dropFirst())` pattern is recommended over `.onChange(of:)` for reliable reaction to `@Published` changes. But when the property being observed is the same one being mutated by a binding, it creates a feedback loop. The pattern is safe when the observed property changes externally, but dangerous when the `.onReceive` handler re-assigns the same property.

## Skill Improvements

### `building-swiftui-macos-apps/REFERENCES/swiftui-gestures.md`

1. **Correct "Approach 1: ZStack with Overlay Rectangles"** — This approach does NOT work with `.simultaneousGesture`. The documented code uses `.gesture()` which may work, but `.simultaneousGesture()` causes all overlays to fire simultaneously with the last one winning. Replace with the parent-level gesture + hit-testing approach.

2. **Add "Approach 1 (Corrected): Parent Gesture with Hit Testing"** — Document the working pattern:
   - Single `DragGesture` at parent level with `@State dragPanelId` flag
   - Hit-test `startLocation` on first `onChanged` to lock target panel
   - `MagnificationGesture` targets the selected panel (no location available)
   - `.onTapGesture` at parent level for panel selection with visual indicator

3. **Add "MagnificationGesture has no location"** — Document that `MagnificationGesture.Value` is `CGFloat` only. Cannot hit-test panel under pinch. Target the selected panel instead.

4. **Add "No `.onStarted` on DragGesture/MagnificationGesture"** — These types don't have `.onStarted`. Use `@State` flag in first `onChanged` for gesture initialization.

### `building-swiftui-macos-apps/SKILL.md` — Common Pitfalls

5. **Add `.onReceive` infinite recursion pitfall** — When a binding mutates a `@Published` property and `.onReceive($property)` re-assigns the same property, it creates an infinite loop. `.onReceive` should only trigger side effects, not re-assign the observed property.

6. **Add `simultaneousGesture` on ZStack overlays pitfall** — `.simultaneousGesture` on multiple overlays causes all to fire simultaneously. Use parent-level gesture with hit-testing instead.

7. **Update gesture pitfall #22** — Current text says "gesture applies to selected item, not region under cursor." Should specify that `simultaneousGesture` on ZStack overlays causes last-one-wins behavior.

### `macos-swiftui-patterns/SKILL.md`

8. **Add `.onReceive` feedback loop warning** — In the State Ownership section, note that `.onReceive($property)` handlers must not re-assign the same property they observe.

## Next Steps

- Update `swiftui-gestures.md` with corrected gesture targeting approach
- Update `building-swiftui-macos-apps/SKILL.md` with new pitfalls
- Continue manual testing: verify export flow, hero/mosaic layouts, edge cases

---
**Status:** Open
**Follow-up:** Update gesture reference and skill pitfalls
