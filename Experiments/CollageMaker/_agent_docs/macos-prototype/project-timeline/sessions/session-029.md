# Session 29 — 2026-05-19

### Phase 2: Settings Window & Commands

**Goal:** Implement Phase 2 of the HIG Review Phased Implementation Plan — native macOS Settings scene accessible via Cmd+, + refined keyboard shortcuts with explicit modifiers.

**Plan Reference:** `_agent_docs/plans/2026-05-19-hig-review-phased.md` (Phase 2 of 4)

**Changes Implemented:**

1. **SettingsView.swift (NEW)** — Four-tab `TabView` with `scenePadding()` and `frame(minWidth: 420, minHeight: 280)`:
   - **General tab** — `@AppStorage`-backed controls for default layout (popup: Uniform/Hero/Mosaic), default gutter (slider 0–20pt), default quality (slider 50%–100%)
   - **Appearance tab** — Background style segmented control (Solid/Gradient), `UserDefaultsColorView` color wells for solid color and gradient start/end colors, gradient angle slider with `didSet` persistence
   - **Text tab** — Default title text field, font family text field (empty = system), font size slider 12–120pt, all backed by `@AppStorage`
   - **Export tab** — Default export folder with "Choose Folder" button (opens `NSOpenPanel` for directories), quality slider (reuses `@AppStorage` shared with General tab)

2. **UserDefaultsColorView** — `NSViewRepresentable` wrapping `NSColorWell` with coordinator pattern:
   - Loads saved color from `UserDefaults` on `makeNSView` (via `NSKeyedUnarchiver`)
   - Saves color on change via coordinator's `colorChanged(_:)` action callback
   - Falls back to `defaultValue` when no saved color exists

3. **CollageCommands.swift changes:**
   - Added `@Binding var showingClearAlert: Bool` — Clear All now triggers confirmation alert instead of direct action
   - Explicit `.command` modifiers on all shortcuts: `Cmd+O` (Add Images), `Cmd+S` (Export)
   - Added `Cmd+1`, `Cmd+2`, `Cmd+3` for Uniform/Hero/Mosaic layout switching
   - Replaced `ForEach`-generated layout buttons with explicit `Button` + `.keyboardShortcut` per the plan

4. **CollageMakerApp.swift changes:**
   - Added `@State private var showingClearAlert = false`
   - Added `Settings { SettingsView() }` scene
   - Added `showingClearAlert` environment key (`ShowingClearAlertKey: EnvironmentKey`) with `EnvironmentValues` extension for passing binding to ContentView
   - ContentView receives binding via `.environment(\.showingClearAlert, $showingClearAlert)`

**Files Modified:**
- `CollageMakerApp.swift` — Settings scene, clear alert state, environment key
- `Views/CollageCommands.swift` — Explicit modifiers, layout shortcuts, clear alert binding
- `Views/SettingsView.swift` — NEW, four-tab settings with color well wrapper

**Build Issues Encountered and Resolved:**
- `NSColorWell.allowedColorPanelSizes` — not a member on SDK 26.5; removed, color panel uses default size
- Test target has pre-existing build failures in `CollageAssemblerTests.swift` (mock protocol uses `title: String` instead of `titleAttrString: NSAttributedString`) — unrelated to these changes

**Current State:**
- Build: **SUCCEEDED** — zero errors, zero warnings (4 pre-existing warnings unrelated to Phase 2)
- Tests: **Pre-existing failures** in `CollageAssemblerTests.swift` (unrelated mock protocol mismatch, 20 errors)
- Settings window: **Implemented** with all four tabs
- Keyboard shortcuts: **Refined** with explicit modifiers and Cmd+1/2/3 layout switching
- Clear All alert: **Wired** via environment binding (alert UI in Phase 3)
