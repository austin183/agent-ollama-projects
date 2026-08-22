# @Observable Body Re-evaluation Cascade — Learnings 2026-06-21

**Purpose**: Capture learnings from session 123 — eliminating drag flicker caused by `@Observable` mutations triggering full SwiftUI body re-evaluations of sibling views.

## What Worked

- **Struct isolation prevents body re-evaluation cascades** — Extracting high-frequency state into a self-contained SwiftUI struct limits re-evaluation scope. When a `DragGesture` updates `@State` on a dedicated struct, only that struct's `body` re-evaluates — parent and sibling views are untouched.

```swift
// Parent view — never re-evaluates during drag
struct ContentView: View {
    var body: some View {
        HStack(spacing: 0) {
            ExpensiveEditorView(viewModel: viewModel)  // not re-evaluated
            if !isCollapsed {
                ResizableDrawer(viewModel: viewModel)  // isolated
            }
        }
    }
}

// Isolated struct — only this body re-evaluates per drag tick
struct ResizableDrawer: View {
    @Bindable var viewModel: CollageViewModel
    @State private var drawerWidth: CGFloat = 300

    var body: some View {
        HStack(spacing: 0) {
            resizeHandle
            detailPanel.frame(width: drawerWidth)
        }
    }

    private var resizeHandle: some View {
        Rectangle()
            .gesture(
                DragGesture()
                    .onChanged { _ in drawerWidth = ... }  // only ResizableDrawer.body invalidates
                    .onEnded { _ in viewModel.drawerWidth = drawerWidth }  // sync once on release
            )
    }
}
```

- **Sync-to-viewmodel-on-release pattern** — During drag, state lives in local `@State`. On `onEnded`, the final value is written to the `@Observable` ViewModel once. This gives smooth interaction (no cascading re-evaluations) with persistence (ViewModel reflects the final state).

## What Didn't Work / Gaps

- **`@Observable` mutation during drag — Full body cascade** — Writing to a `@Observable` property on every `DragGesture.onChanged` tick (~60fps) fires `objectWillChange` each time. All `@Bindable` observers re-render, including sibling views that don't depend on the changed property. The `CollageEditorView` with its `GeometryReader` and panel overlay tree re-evaluated ~60 times per drag, causing visible flicker.

- **Local `@State` on parent view — Doesn't isolate siblings** — Moving the width from `viewModel.rightDrawerWidth` to `@State` on `ContentView` still flickered. `@State` mutations invalidate the view they belong to — `ContentView.body` re-evaluated, which includes `CollageEditorView` in its body tree. The sibling still re-renders even though it doesn't read the changed `@State`.

- **`.cursor()` modifier unavailable in macOS SwiftUI** — The plan specified `.cursor(.resizeLeftRight)` but this modifier does not exist in macOS SwiftUI. Use `NSCursor.resizeLeftRight.push()` / `NSCursor.pop()` in `onHover` instead.

## What Was Confusing

- **Why local `@State` didn't help** — The intuition was that avoiding `@Observable` mutations would prevent re-renders. But `@State` invalidations work the same way — they invalidate the view struct they're declared on. If that struct's body includes a sibling view, the sibling re-evaluates regardless of whether it reads the changed state. The fix requires a separate struct boundary.

- **Why native split view is smooth** — `NSSplitView` operates at the AppKit layer. Resizing it triggers an AppKit layout pass (frame changes) without any SwiftUI body re-evaluations. The custom `HStack` resize must go through SwiftUI's rendering pipeline, making body evaluation scope the performance bottleneck.

## Key Patterns

### Body Re-evaluation Scope

| State Location | Invalidates | Sibling Re-evaluates? |
|---|---|---|
| `@Observable` property | All `@Bindable` observers | Yes |
| `@State` on parent view | Parent's body | Yes |
| `@State` on isolated struct | Only that struct's body | **No** |
| AppKit layout (e.g., `NSSplitView`) | Layout pass only | No |

### When to Use Struct Isolation

Extract a self-contained struct when:
1. A gesture or animation updates state at high frequency (~60fps)
2. The state change triggers `@Observable` or `@State` invalidations
3. A sibling view has an expensive body (e.g., `GeometryReader`, complex overlays)
4. The sibling doesn't depend on the changing state

### Diagnostic Clues for Cascade Flicker

If a view flickers during a gesture but the gesture target itself looks fine:
1. The flickering view is likely re-evaluating its body unnecessarily
2. Check if the gesture updates `@Observable` state — every mutation invalidates all observers
3. Check if the gesture updates `@State` on a parent view — all children re-evaluate
4. The fix is struct isolation: move the state to a sibling struct

---
**Status**: Completed
**Follow-up**: None
