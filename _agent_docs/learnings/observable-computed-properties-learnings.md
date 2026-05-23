# @Observable Computed Properties & View Binding — Learnings

**Date:** 2026-05-13
**Session:** 11
**Purpose:** Document learnings from debugging background style picker, title field, and preview update issues in CollageMaker.

---

## What Worked

- **`@Bindable` on `@Observable` views** — Adding `@Bindable var viewModel: CollageViewModel` to views that consume an `@Observable` class enables SwiftUI to auto-track all stored property changes. Without it, the view receives the initial value but never re-renders when properties change.
- **Stored properties with `didSet` persistence** — Converting `UserDefaults`-backed computed properties to stored properties with `didSet` gives you both `@Observable` tracking and persistence. Pattern:
  ```swift
  var title: String = UserDefaults.standard.string(forKey: "title") ?? "" {
      didSet { UserDefaults.standard.set(title, forKey: "title") }
  }
  ```
- **Color persistence helpers** — Extracting `saveColor`/`loadColor` methods avoids repeating `NSKeyedArchiver` boilerplate across multiple color properties.
- **Consistent interaction targeting** — Making scroll/pan target the selected panel (matching zoom) is simpler than hit-testing and provides consistent UX.

## What Didn't Work / Gaps

- **`@Observable` cannot track computed properties** — This is the core limitation. `@Observable` synthesizes observation code at compile time for stored properties only. A computed property like:
  ```swift
  var backgroundStyle: BackgroundStyle {
      get { BackgroundStyle(rawValue: UserDefaults...) ?? .solid }
      set { UserDefaults.standard.set(newValue.rawValue, ...) }
  }
  ```
  Will persist correctly but **never triggers SwiftUI re-renders** when `set` is called. The Picker/TextField/Slider binding appears to work (the value is stored), but no dependent views re-render.

- **Plain `let` parameter on `@Observable` view** — A view declared as:
  ```swift
  struct MyView: View {
      let viewModel: CollageViewModel  // @Observable class
  }
  ```
  Receives the ViewModel as a value but SwiftUI does **not** set up observation. The view renders once with the initial state and never updates. Must use `@Bindable var` instead.

- **Symptom was subtle** — The title TextField showed the typed text locally (because `TextField` manages its own text storage), but the preview never updated because `updatePreview()` was only called from `backgroundColor`'s setter (which was also computed). The title only appeared when switching background styles because that forced a full body re-evaluation, which happened to read the current `title` from the computed getter at render time.

## Key Patterns

### @Observable Property Rules

| Property Type | Triggers Re-render? | Persistable? |
|---|---|---|
| Stored (`var x = value`) | Yes | No (in-memory only) |
| Stored + `didSet` | Yes | Yes (write to disk in `didSet`) |
| Computed (`get`/`set`) | **No** | Yes (but invisible to SwiftUI) |

### View Binding Rules

| Declaration | Observes @Observable? | Safe? |
|---|---|---|
| `@Bindable var viewModel: MyViewModel` | Yes | Yes |
| `let viewModel: MyViewModel` | **No** | No — stale after first render |
| `@StateObject` + `@ObservedObject` | N/A (legacy) | Use for `ObservableObject` only |

### Diagnostic Clues

If a binding "works locally" (TextField shows text, Slider moves) but dependent views don't update:
1. Check if the ViewModel property is computed instead of stored
2. Check if the consuming view uses `@Bindable` (or `@ObservedObject` for legacy)
3. Check if `updatePreview()`/side effects are called in the property's `didSet` or `willSet`

## Remaining Bugs

- **Background image not rendering in preview** — `chooseBackgroundImage()` in `ExportPanel` sets `viewModel.backgroundImage = image` and calls `viewModel.updatePreview()`. The `backgroundImage` property is a plain stored `NSImage?`, so observation should work. The `updatePreview()` method captures `backgroundImage` and passes it to `assemblePreviewWithCGImages`, which converts to `CGImage` via `nsImage.cgImage(forProposedRect:)`. Possible failure points:
  - `cgImage(forProposedRect:)` returns `nil` for certain image formats
  - The `Task.detached` capture window doesn't include the newly assigned image
  - `drawImageBackground` in `CollageAssembler` silently returns early on `nil` CGImage (line 331: `guard let bgImage = backgroundImage else { return }`)
  - Needs investigation with print/logging in the preview pipeline

## Next Steps

- Debug background image rendering: add logging in `updatePreview()` to verify `backgroundImage` is non-nil at capture time, and in `assemblePreviewWithCGImages` to verify `bgCGImage` conversion succeeds
- Re-run test suite after all the property conversions to ensure no regressions
- Consider a systematic audit: search for remaining computed properties on `@Observable` classes that should be stored

---
**Status:** Closed
**Follow-up:** Debug background image rendering; re-run tests
