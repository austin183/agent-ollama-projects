# Session 11 — 2026-05-13

### Bug Fixes: Scroll/pan consistency, @Observable computed property tracking

**Goal:** Make scroll/pan consistent with zoom (both target selected panel), fix background style picker and title field not updating preview.

**Bugs Discovered and Fixed:**

1. **Scroll/pan targets hovered panel, zoom targets selected panel** — `ScrollPanView.swift`. Scroll pan used hit-testing against `scaledPanelFrames` at gesture `.began` to find whichever panel the cursor hovered over, while zoom (`MagnificationGesture`) always targets `viewModel.selectedPanelId` because `MagnificationGesture.Value` is a `CGFloat` with no location data. Made scroll/pan consistent with zoom by replacing the hit-test with a check against `selectedPanelId`. Removed `hitTest(at:)` method and `scaledPanelFrames` parameter from `ScrollPanView`.

2. **Background style picker doesn't switch UI** — `CollageViewModel.swift`. The `backgroundStyle` property was a computed property backed by `UserDefaults` (`get` reads from `UserDefaults`, `set` writes to `UserDefaults`). `@Observable` can only auto-track **stored** properties — computed properties don't trigger observation. When the Picker changed the value, `UserDefaults` was updated but SwiftUI never knew, so the `switch viewModel.backgroundStyle` block in `ExportPanel` never re-rendered. Fixed by converting to a stored property with `didSet` persistence.

3. **Title changes don't update preview** — Same root cause as #2. The `title` property was computed (`get`/`set` from `UserDefaults`), so SwiftUI's `TextField` binding appeared to work locally but the ViewModel never triggered a re-render to call `updatePreview()`. The title only appeared in the preview when `backgroundStyle` changed, because that forced a body re-evaluation which happened to read the current title from the computed getter at render time. Fixed by converting to stored property with `didSet`.

4. **`CollageEditorView` never re-renders on ViewModel changes** — `CollageEditorView.swift` + `PanelCropEditor.swift`. Both views took `viewModel` as a plain `let` parameter instead of `@Bindable var`. Without `@Bindable`, SwiftUI doesn't set up observation for the `@Observable` ViewModel, so changes to `previewImage`, `panels`, `cropMap`, etc. never triggered view re-renders. Fixed by adding `@Bindable` to both views.

5. **All UserDefaults-backed properties need conversion** — Beyond `backgroundStyle` and `title`, the same issue affected `gutter`, `heroIndex`, `scrollSensitivity`, `exportQuality`, `gradientAngle`, `backgroundOpacity`, `backgroundColor`, `gradientStartColor`, `gradientEndColor`. All converted to stored properties with `didSet` persistence. Colors use helper methods (`saveColor`/`loadColor`) for `NSKeyedArchiver` round-trip, loaded in `init()`.

**Production Code Changes:**
- `Views/ScrollPanView.swift` — Replaced hit-test with `selectedPanelId` parameter; removed `scaledPanelFrames`, `hitTest(at:)`
- `Views/CollageEditorView.swift` — Added `@Bindable` to `viewModel` parameter; updated `ScrollPanView` call site
- `Views/PanelCropEditor.swift` — Added `@Bindable` to `viewModel` parameter
- `ViewModel/CollageViewModel.swift` — Converted all UserDefaults-backed computed properties to stored properties with `didSet` persistence. Added `saveColor`/`loadColor` helpers. Colors loaded from UserDefaults in `init()`.

**Remaining Bugs:**
- Background image selection via `chooseBackgroundImage()` sets `viewModel.backgroundImage` and calls `updatePreview()`, but the preview still doesn't show the image. Issue not yet resolved — may be related to `NSImage.cgImage(forProposedRect:)` returning nil, or the `Task.detached` preview pipeline not capturing the new image reference correctly.

**Current State:**
- Build: **SUCCEEDED** — zero errors, zero new warnings
- Tests: **Not yet re-run** (no ViewModel property access patterns changed that would affect tests)
- Scroll/pan consistency: **Fixed** (targets selected panel, matches zoom behavior)
- Background style picker: **Fixed** (UI switches between Solid/Gradient/Image)
- Title field: **Fixed** (changes trigger preview update)
- Background image: **Still broken** (image selected but not rendered in preview)

**Learnings Documented:**
- `_agent_docs/learnings/observable-computed-properties-learnings.md`
