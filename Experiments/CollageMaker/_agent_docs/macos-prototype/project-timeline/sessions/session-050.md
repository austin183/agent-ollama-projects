# Session 50 — 2026-05-25

### Architectural Review Fixes — Item 1: Extract UserDefaults Persistence

**Goal:** Extract scattered UserDefaults persistence from CollageViewModel into a dedicated service, consolidating all keys and eliminating inline strings.

**Source:** `_agent_docs/plans/2026-05-25-architectural-review-fixes.md` — Item 1 (High priority).

**Problem:**
CollageViewModel had 13 `didSet` observers each mixing undo registration, `UserDefaults.standard.set(...)` persistence, and business logic side effects. Two inline key strings (`"titleAttrString"`, `"defaultFontSize"`) bypassed the centralized `ViewModelUserDefaultsKeys` enum. Color save/load helpers were private to the VM. Background image path persistence was split between the VM's `didSet` (only on nil) and `ExportPanel.chooseBackgroundImage()` (direct write).

**Investigation:**

Read all persisted properties and their `didSet` patterns:
- 13 persisted properties: `layoutStyle`, `titleAttrString`, `titleStyle`, `gutter`, `backgroundColor`, `exportQuality`, `backgroundStyle`, `gradientStartColor`, `gradientEndColor`, `gradientAngle`, `backgroundImage`, `backgroundOpacity`, `customImageOrder`
- Archiving strategies: NSKeyedArchiver (NSColor, NSAttributedString), JSON (`[Int]`), raw value (enums), Double (primitives)
- `TitleStyle` already has its own `saveToUserDefaults()` / `fromUserDefaults()` — should delegate, not duplicate
- Legacy migration path for `titleAttrString` (plain string → default title + font)

**Changes Implemented:**

#### New file: `Services/UserDefaultsPersistence.swift`

- `PersistenceBundle` struct — holds all 13 persisted values for VM initialization
- `@MainActor final class UserDefaultsPersistence`:
  - `Keys` enum consolidates ALL UserDefaults keys: 13 persisted properties + `defaultExportFolder` + legacy migration keys (`title`, `defaultTitle`, `defaultFontFamily`, `defaultFontSize`)
  - `save(_ viewModel:)` — persists all 13 properties; delegates to `TitleStyle.saveToUserDefaults()`; handles `backgroundImagePath` (saves on set, removes on nil)
  - `load() -> PersistenceBundle` — loads with full legacy migration for `titleAttrString`; `backgroundOpacity` preserves 1.0 default for missing key; `backgroundImage` validates file existence before loading
  - Private helpers: `saveColor`/`loadColor` (NSKeyedArchiver), `saveTitleAttrString`/`loadTitleAttrString` (with legacy fallback), `saveCustomImageOrder`/`loadCustomImageOrder` (JSON), `loadBackgroundImage` (file validation), `loadBackgroundOpacity` (default guard)

#### Modified: `ViewModel/CollageViewModel.swift`

- Injected `UserDefaultsPersistence` dependency via init parameter; added 3 init overloads:
  - `convenience init()` — defaults for production
  - `convenience init(saliencyAnalyzer:assembler:)` — defaults persistence for tests
  - `init(saliencyAnalyzer:assembler:persistence:)` — full injection
- Added `isInitializing` flag to suppress undo/persistence during property initialization from loaded bundle
- Removed inline `saveColor`/`loadColor` helpers, `jsonEncoder`/`jsonDecoder`
- Each of 13 `didSet` observers follows unified pattern: `guard !isInitializing` → undo → `persistence.save(self)` → side effect
- Added `backgroundImagePath: String?` tracked property; added `setBackgroundImage(_:path:)` method for coordinated assignment
- `clearAll` no longer touches UserDefaults directly — `backgroundImage = nil` triggers didSet chain
- `exportCollage` references `UserDefaultsPersistence.Keys.defaultExportFolder` instead of inline string
- `ViewModelUserDefaultsKeys` enum retained for backward compatibility (ExportPanel still references it — Item 2 will clean up)

**Build and Test Status:**
- **Build:** Succeeded — zero errors, zero warnings
- **Tests:** All 111 unit tests passing, 0 failures

**Session Status:** Complete — persistence service extracted, all keys consolidated, VM didSet observers simplified.
