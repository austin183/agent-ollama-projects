# Session 13 — 2026-05-14

### Round 3, Phase 1: Multiline Title + Font Controls

**Goal:** Implement Phase 1 of the round-3 plan: multiline title input, font family/size/color/alignment controls, and background pill toggle.

**Files Created:**
- `Models/TitleStyle.swift` — `Codable`/`Equatable` struct with `fontFamily`, `fontSize`, `fontColor`, `alignment`, `showBackground`. UserDefaults persistence via JSON encoding with `NSKeyedArchiver` round-trip for `NSColor`.

**Files Modified:**
- `Services/CollageAssembler.swift` — Added `titleStyle: TitleStyle` parameter to all 4 `CollageAssembly` protocol methods and implementations. `drawTitle()` now uses configurable font (with `NSFont.boldSystemFont` fallback when font name is empty or unavailable), `NSParagraphStyle` for alignment, configurable color, and conditional background pill.
- `ViewModel/CollageViewModel.swift` — Added `titleStyle: TitleStyle` stored property with `didSet` persistence. Passes `titleStyle` to assembler in `updatePreview()` and `exportCollage()`.
- `Views/ExportPanel.swift` — Replaced single-line `TextField` with `TextEditor` for multiline input. Added "Title Style" section with font picker (`Menu` + `Picker` over `NSFontManager.shared.availableFontFamilies`), size slider (12–120pt), color well (`NSColorPickerView`), alignment segmented control (left/center/right), and background toggle switch.
- `CollageMakerTests/CollageAssemblerTests.swift` — Added `titleStyle: .default` to all 10 assembler calls.
- `CollageMakerTests/CollageViewModelTests.swift` — Updated `MockAssembler` to accept `titleStyle` parameter on all 4 protocol methods.

**Build Issues Encountered and Resolved:**
1. `CodableNSColor` helper struct unnecessary — `NSColor` doesn't conform to `Codable`, so a wrapper struct claiming `Codable` conformance failed. Removed the helper, using `NSKeyedArchiver` directly in `TitleStyle.encode/init(from:)`.
2. Redundant `Codable` conformance — Declaring `struct TitleStyle: Codable` on the struct and `extension TitleStyle: Codable` on an extension caused "redundant conformance" errors. Moved custom `encode`/`init(from:)` into a single `extension TitleStyle` block without re-declaring the conformance.
3. `TextArea` not available — `TextArea` requires macOS 26+. Used `TextEditor` instead (available since macOS 12).
4. `TextEditor.border(NSColor, width:)` type mismatch — `.border()` expects `some ShapeStyle`, not raw `NSColor`. Replaced with `.background()` + `.overlay(RoundedRectangle.stroke())` pattern.

**Current State:**
- Build: **SUCCEEDED** — zero errors, zero new warnings
- Tests: **68 tests pass** (all existing tests updated with `titleStyle: .default`)
- Multiline title: **Working** (`TextEditor` in ExportPanel)
- Font controls: **Working** (family picker, size slider, color well, alignment, background toggle)
- Title rendering: **Working** (all style options applied in `drawTitle()`)
- UserDefaults persistence: **Working** (JSON-encoded `TitleStyle` with archived `NSColor`)

**Learnings Documented:**
- `_agent_docs/learnings/title-style-controls-learnings.md`
