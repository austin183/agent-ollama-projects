# Make Right Drawer Resizable

**Date:** 2026-06-21
**Change Request:** round-105
**Status:** completed

## Problem

The left sidebar of the `NavigationSplitView` is natively resizable by macOS (drag the divider between sidebar and detail). The right-hand drawer — a custom `HStack` inside the `detail` column — has no resize mechanism. Users cannot adjust its width.

## Current Architecture

- **`ContentView.swift`** — `NavigationSplitView` with `detail` as an `HStack(spacing: 0)` containing `CollageEditorView` (`maxWidth: .infinity`) and `detail` (conditionally shown based on `@State isDetailCollapsed`)
- **`CollageViewModel.swift`** — `@Observable` source of truth, no right drawer width tracking
- **`UserDefaultsPersistence.swift`** — Persists app settings via `PersistenceBundle` struct + `UserDefaults`

## Solution

Add a visible resize handle between the editor and detail panel with a `DragGesture`, backed by `CollageViewModel` state and `UserDefaults` persistence.

### Parameters

| Setting | Value |
|---------|-------|
| Default width | 300 pt |
| Minimum width | 200 pt |
| Maximum width | 800 pt |
| Handle width | 4 pt |
| Handle appearance | Visible — subtle vertical line (`Color.secondary.opacity(0.3)`) that darkens on hover |
| Cursor | `.resizeLeftRight` (matches native left sidebar divider) |

---

## Implementation Plan

### Task 1: Persistence Layer

**File:** `CollageMaker/CollageMaker/CollageMaker/Services/UserDefaultsPersistence.swift`

1. Add to `Keys` enum:
   ```swift
   static let rightDrawerWidth = "rightDrawerWidth"
   ```

2. Add to `PersistenceBundle` struct:
   ```swift
   var rightDrawerWidth: CGFloat
   ```

3. In `save(_:)`, append:
   ```swift
   defaults.set(Double(viewModel.rightDrawerWidth), forKey: Keys.rightDrawerWidth)
   ```

4. In `load()`, compute:
   ```swift
   let rightDrawerWidth = CGFloat(defaults.double(forKey: Keys.rightDrawerWidth))
   ```
   If the key doesn't exist (first launch), `defaults.double` returns `0`, so coerce:
   ```swift
   let rightDrawerWidth: CGFloat
   if defaults.object(forKey: Keys.rightDrawerWidth) != nil {
       rightDrawerWidth = CGFloat(defaults.double(forKey: Keys.rightDrawerWidth))
   } else {
       rightDrawerWidth = 300
   }
   ```

5. Add `rightDrawerWidth` to the `PersistenceBundle` initializer at the end of `load()`.

### Task 2: ViewModel Layer

**File:** `CollageMaker/CollageMaker/CollageMaker/ViewModel/CollageViewModel.swift`

1. Add property:
   ```swift
   var rightDrawerWidth: CGFloat = 300
   ```

2. In `init`, after loading the bundle (still inside `isInitializing = true` block):
   ```swift
   self.rightDrawerWidth = bundle.rightDrawerWidth
   ```

### Task 3: View Layer — Resize Handle

**File:** `CollageMaker/CollageMaker/CollageMaker/ContentView.swift`

1. Add `@State` for gesture base capture:
   ```swift
   @State private var rightDrawerStartWidth: CGFloat = 0
   @State private var isHandleHovered = false
   ```

2. Replace the current `HStack` (lines 22–29):
   ```swift
   HStack(spacing: 0) {
       CollageEditorView(viewModel: viewModel)
           .frame(maxWidth: .infinity, maxHeight: .infinity)

       if !isDetailCollapsed {
           resizeHandle
           detail
               .frame(width: viewModel.rightDrawerWidth)
       }
   }
   ```

3. Add `resizeHandle` computed property:
   ```swift
   private var resizeHandle: some View {
       Rectangle()
           .fill(isHandleHovered
                 ? Color.secondary.opacity(0.6)
                 : Color.secondary.opacity(0.3))
           .frame(width: 4)
           .contentShape(Rectangle())
           .cursor(.resizeLeftRight)
           .onHover { hovering in
               isHandleHovered = hovering
           }
           .gesture(
               DragGesture()
                   .onChanged { value in
                       // Capture base width on first tick (no .onStarted available)
                       if rightDrawerStartWidth == 0 {
                           rightDrawerStartWidth = viewModel.rightDrawerWidth
                       }
                       let newWidth = rightDrawerStartWidth - value.translation.width
                       viewModel.rightDrawerWidth = max(200, min(800, newWidth))
                   }
                   .onEnded { _ in
                       viewModel.debouncedSave()
                       rightDrawerStartWidth = 0
                   }
           )
   }
   ```

4. The `detail` property itself needs no changes — it already has `.frame(maxWidth: .infinity, alignment: .top)` on its inner `VStack`, which works correctly with an outer fixed width.

---

## Key Design Decisions

### Why `rightDrawerStartWidth - value.translation.width`

Dragging the handle to the **right** (positive `translation.width`) should **shrink** the drawer. Dragging **left** (negative translation) should **expand** it. Subtraction achieves this:
- Drag right 50pt → `startWidth - 50` → narrower
- Drag left 50pt → `startWidth - (-50)` → `startWidth + 50` → wider

### Why capture in `@State`, not read from `viewModel` each tick

Per the gestures skill (`swiftui-gestures.md` pitfall #8): `DragGesture.Value.translation` is cumulative from drag start. If we read `viewModel.rightDrawerWidth` inside `onChanged`, the `@Bindable` property returns the already-updated value each tick, causing compounding. The `@State` variable captures the base width once at gesture onset.

### Why `rightDrawerStartWidth == 0` as the "first tick" guard

SwiftUI has no `.onStarted` on `DragGesture` (skill reference, Key Finding #4). The standard pattern is to use a sentinel value in the first `onChanged` call. Since valid widths are always >= 200, `0` is a safe sentinel.

### Why persist via `debouncedSave()` on `onEnded`, not during drag

The width updates ~60fps during a drag. Persisting every tick would hammer `UserDefaults`. The existing `debouncedSave()` (300ms delay) is called once on `onEnded`, after the user releases the handle.

### Why no undo support

Drawer width is a UI preference, not a content edit. It follows the same convention as `gutter` and `exportQuality` — persisted but not undoable.

---

## Files Modified

| File | Change |
|------|--------|
| `Services/UserDefaultsPersistence.swift` | Add `rightDrawerWidth` key, bundle property, save/load |
| `ViewModel/CollageViewModel.swift` | Add `rightDrawerWidth` property, initialize from bundle |
| `ContentView.swift` | Add `@State` variables, `resizeHandle` computed property, wire `HStack` |

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Drawer shrinks below usable width | Hard minimum of 200 pt |
| Drawer covers entire editor | Hard maximum of 800 pt |
| Compounding width from re-reading binding | Base width captured in `@State` on first tick |
| Handle interferes with editor gestures | `contentShape(Rectangle())` on a 4pt view — narrow hit area, no gesture conflict with `CollageEditorView` |
| Detail view layout breaks at non-default width | `detail` already uses `maxWidth: .infinity` on inner content — fixed outer frame constrains it properly |

## Verification

1. Build and run: `bash script/build_and_run.sh run`
2. Verify handle is visible between editor and detail panel
3. Drag handle left/right — drawer resizes smoothly
4. Verify cursor changes to `.resizeLeftRight` on hover
5. Resize, quit, relaunch — width is restored
6. Toggle right sidebar off/on — handle disappears/reappears
7. Verify min (200pt) and max (800pt) clamping by dragging to extremes
