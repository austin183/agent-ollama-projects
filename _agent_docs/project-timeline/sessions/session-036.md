# Session 36 — 2026-05-21

### Phase 4 Low Priority + Phase 5 Nits: Final Review Fixes

**Goal:** Implement remaining issues from `_agent_docs/plans/2026-05-20-review-fixes.md` — Phases 4 and 5. Phases 1–3 were already completed in sessions 32–35.

**Source:** `_agent_docs/plans/2026-05-20-review-fixes.md` (Phases 4–5)

**Issues Fixed:**

#### Issue #9: Mosaic Layout Non-Deterministic

`LayoutGenerator.generateMosaic` used `Float.random(in: 0..<1)` for split ratios, making layouts non-reproducible.

**Fix:** Added optional `seed: UInt64?` parameter. When provided, uses a `SplitMix64` seeded PRNG. When `nil`, falls back to default randomness. Propagated `mosaicSeed: UInt64?` through `LayoutGenerator.generate()`.

**Files:** `Services/LayoutGenerator.swift`

#### Issue #10 (review): `exportCollage` NSSavePanel Blocking

`NSApplication.shared.runModal(for:)` blocks the main thread. This is unavoidable for `NSSavePanel`.

**Fix:** Added documentation comment explaining the blocking behavior is intentional and unavoidable.

**Files:** `ViewModel/CollageViewModel.swift:706`

#### Issue #11 (review): SettingsView Defaults Not Wired Into ViewModel

`SettingsView` stores `defaultTitle`, `defaultFontFamily`, `defaultFontSize` to `UserDefaults`, but `CollageViewModel` never read them.

**Fix:** Wired defaults into `titleAttrString` computed initializer as fallback values. When `defaultTitle` is set in Settings, the title is pre-populated with the configured font family and size.

**Files:** `ViewModel/CollageViewModel.swift:55-72`

#### Issue #12: Redundant Accessibility on Menu Items

`.accessibilityLabel` and `.accessibilityHint` on `Button` inside `Commands` are redundant — menu buttons derive accessibility from their labels.

**Fix:** Removed redundant modifiers from "Add Images" and "Export JPEG" command buttons.

**Files:** `Views/CollageCommands.swift`

#### Issue #13: Global Logging Helper Functions

`rectStr`, `pointStr`, `sizeStr` were global free functions causing namespace pollution.

**Fix:** Created `struct DebugHelpers` with static methods. Updated all callers in `CollageEditorView`.

**Files:**
- `Services/LoggingExtensions.swift` — wrapped in `DebugHelpers` struct
- `Views/CollageEditorView.swift` — 4 call sites updated

**Build and Test Status:**
- **Build:** SUCCEEDED — zero errors, 3 pre-existing warnings (unrelated)
- **Full unit test suite (CollageMakerTests):** ALL 107 tests PASS — zero failures

**Session Status:** Complete — all issues from the 2026-05-20 review fix plan are now resolved.
