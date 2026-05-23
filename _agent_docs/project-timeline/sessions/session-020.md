# Session 20 — 2026-05-15

### Round 4, Phase 3: Font Dropdown (Searchable, WYSIWYG)

**Goal:** Replace the `Menu` + `Picker` font selector in `ExportPanel` with a button that opens a `.popover` containing a search field and scrollable list of font families, each rendered in its own font (WYSIWYG preview).

**Files Created:**
- `Views/FontPickerPopover.swift` — Standalone component with bordered button, search `TextField`, `LazyVGrid`-style `LazyVStack` of font families, each rendered in its own typeface at 16pt. Selection closes the popover.

**Files Modified:**
- `Views/ExportPanel.swift` — Replaced `Menu` + `Picker` block with `FontPickerPopover`. Removed unused `fontFamilies` computed property, renamed `selectedFontFamily` to `displayFamily`.

**Implementation Details:**
- Button label shows the selected font rendered in its own typeface via `font(for:)` helper
- Popover is 280x340 with a search field and scrollable list
- Each font family rendered at 16pt using `NSFont(name:size:)`, falling back to `.system(size: 16)` for `(System Default)` or unavailable fonts
- Selection closes the popover by setting `isPopoverPresented = false`
- Binding maps `(System Default)` to `""` (empty string = system default in `TitleStyle`)

**Build Issues Encountered and Resolved:**
1. `Font.systemFont(ofSize:)` not available — SwiftUI `Font` uses `.system(size:)` instead. Fixed in `font(for:)` fallback path.

**Current State:**
- Build: **SUCCEEDED** — zero errors, zero new warnings
- Tests: **67 tests pass** (unchanged)
- Font picker popover: **Working** (search, WYSIWYG preview, selection dismisses)
