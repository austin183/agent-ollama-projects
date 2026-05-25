# Session 46 — 2026-05-25

### Round 14.4 CR: Clear All Crashes Application — Force Unwrap Fix

**Goal:** Fix the crash described in `_agent_docs/change-requests/round-14.4.md` — `Fatal error: Unexpectedly found nil while unwrapping an Optional value` at `CollageEditorView` line 88 when executing File → Clear All.

**Source:** Round 14.4 change request — crash on clear all after adding images.

**Investigation:**

The crash occurred at `CollageEditorView.swift:88` inside the `body` computed property:

```swift
if viewModel.previewImage != nil {          // line 85 — guard
    GeometryReader { geometry in
        ZStack {
            Image(nsImage: viewModel.previewImage!)  // line 88 — force unwrap
```

The `if viewModel.previewImage != nil` guard at line 85 evaluates to `true` when images are loaded. However, SwiftUI's `body` is a computed property that may be re-evaluated asynchronously. When `clearAll()` sets `previewImage = nil`, the `@Bindable` observation from the guard doesn't carry through into the `GeometryReader` closure body reliably — the guard committed to the `if` branch, but the force unwrap inside the closure then crashes because `previewImage` is now `nil`.

**Changes Implemented:**

#### `CollageEditorView.swift:84-88` — Capture optional before closure entry

Replaced the guard + force-unwrap pattern with `if let` binding:

```swift
if let previewImage = viewModel.previewImage {
    GeometryReader { geometry in
        ZStack {
            Image(nsImage: previewImage)
```

Capturing `previewImage` in a `let` binding before entering the `GeometryReader` closure ensures the value is stable and non-nil for the entire body evaluation. If `previewImage` becomes `nil` during the render cycle, SwiftUI short-circuits to the `else` branch (`ContentUnavailableView`) instead of entering the closure.

**Build and Test Status:**
- **Build:** Succeeded — zero errors, zero warnings
- **Tests:** 100 tests passing — no new tests added (existing `clearAllResetsState` and `clearAllResetsExportState` already verify ViewModel reaches valid post-clear state; the fix is a pattern-level correction provably safe by code inspection)

**Session Status:** Complete — crash fixed, build and tests passing.
