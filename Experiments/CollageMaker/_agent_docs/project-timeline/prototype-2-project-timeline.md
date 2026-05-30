# CollageMaker Prototype 2 — Project Timeline

**Date:** 2026-05-10
**Status:** In Progress

---

## Sessions

| # | Date | Summary |
|---|------|---------|
| 1 | 2026-05-10 | Build complete app from scratch: models, services, ViewModel, views, app wiring ([details](sessions/session-001.md)) |
| 2 | 2026-05-10 | 7 test files, 64 tests all passing. Refactored CollageAssembler for testability ([details](sessions/session-002.md)) |
| 3 | 2026-05-10 | Added OSLog telemetry, fixed drag-and-drop and layout style picker bugs ([details](sessions/session-003.md)) |
| 4 | 2026-05-10 | Fixed gutter slider infinite recursion, panel gesture targeting, added panel selection ([details](sessions/session-004.md)) |
| 5 | 2026-05-11 | Fixed coordinate system Y-flip, moved preview assembly to background thread ([details](sessions/session-005.md)) |
| 6 | 2026-05-11 | Fixed drag/pinch direction inversions, added live preview during gestures ([details](sessions/session-006.md)) |
| 7 | 2026-05-12 | Quick wins: scrollable detail panel, mosaic cap 20, warning section, add button ([details](sessions/session-007.md)) |
| 8 | 2026-05-12 | Sidebar overhaul: thumbnails, hero strip, search, image reordering ([details](sessions/session-008.md)) |
| 9 | 2026-05-12 | Preview debounce, cached hit areas, popover image picker for large sets ([details](sessions/session-009.md)) |
| 10 | 2026-05-13 | Replaced drag pan with two-finger scroll via NSViewRepresentable ([details](sessions/session-010.md)) |
| 11 | 2026-05-13 | Fixed scroll/pan consistency, @Observable computed property tracking, @Bindable views ([details](sessions/session-011.md)) |
| 12 | 2026-05-14 | Fixed background image rendering, gradient coverage, live gradient controls ([details](sessions/session-012.md)) |
| 13 | 2026-05-14 | Multiline title, font family/size/color/alignment controls, background toggle ([details](sessions/session-013.md)) |
| 14 | 2026-05-14 | Title drag-to-position on canvas with live preview ([details](sessions/session-014.md)) |
| 15 | 2026-05-14 | Panel drag-to-reorder with customImageOrder permutation ([details](sessions/session-015.md)) |
| 16 | 2026-05-15 | Panel editor crop preview with dim overlay cutout ([details](sessions/session-016.md)) |
| 17 | 2026-05-15 | Fixed overlapping title/panel gestures — title takes priority ([details](sessions/session-017.md)) |
| 18 | 2026-05-15 | Fixed hero layout, then removed hero index feature per user request ([details](sessions/session-018.md)) |
| 19 | 2026-05-15 | Fixed crop coordinates traveling with image on panel swap ([details](sessions/session-019.md)) |
| 20 | 2026-05-15 | Searchable WYSIWYG font picker popover ([details](sessions/session-020.md)) |
| 21 | 2026-05-16 | Alignment SF Symbols, BG toggle label, text alignment within box fix ([details](sessions/session-021.md)) |
| 22 | 2026-05-16 | Resizable title text box with left/right edge handles ([details](sessions/session-022.md)) |
| 23 | 2026-05-16 | Fixed scroll coordinate jump after panel swap — CropManager panelAssignments sync ([details](sessions/session-023.md)) |
| 24 | 2026-05-17 | SOLID review: extracted coordinate math, 40 new tests (106 total pass) ([details](sessions/session-024.md)) |
| 25 | 2026-05-17 | Attributed string title editor, BG color picker, export panel reorganization ([details](sessions/session-025.md)) |
| 26 | 2026-05-18 | Title color fix, box height fix, editor display decoupling, style sync ([details](sessions/session-026.md)) |
| 27 | 2026-05-18 | Fixed title resize handle / panel drag overlap — preemptive region exclusion in panel gesture ([details](sessions/session-027.md)) |
| 28 | 2026-05-19 | HIG Phase 1: Undo/Redo foundation — UndoManager on 11 properties + 5 methods, export state tracking, default export folder ([details](sessions/session-028.md)) |
| 29 | 2026-05-19 | HIG Phase 2: Settings window (4 tabs) + refined commands — explicit Cmd+O/S modifiers, Cmd+1/2/3 layouts, Clear All alert wiring ([details](sessions/session-029.md)) |
| 30 | 2026-05-19 | HIG Phase 4: Accessibility, progress & polish — VoiceOver labels/values/hints on all controls, specific progress labels, export success feedback (auto-dismiss 3s), sidebar Liquid Glass, gesture undo batching ([details](sessions/session-030.md)) |
| 31 | 2026-05-19 | Fix: title text box overflow — font trait merging in `titleCanvasFrame` and `titleMinWidth` to match `drawTitle` rendering ([details](sessions/session-031.md)) |
| 32 | 2026-05-20 | Phase 1 critical fixes: CGImage off-main-thread in SaliencyAnalyzer, async `addImages`, async `handleDrop` ([details](sessions/session-032.md)) |
| 33 | 2026-05-20 | Phase 2 high priority: extracted `ScrollPanManager`, introduced `AssemblyConfig` to collapse 14-param protocol methods ([details](sessions/session-033.md)) |
| 34 | 2026-05-21 | Phase 3 medium priority: `FontMerger` + `TitleMetrics` deduplication, CropManager instance wrapper removal, background image path persistence, `buildMoveMapping` edge case tests + bounds fix ([details](sessions/session-034.md)) |
| 35 | 2026-05-21 | Phase 3 test verification: fixed `buildMoveMapping` fatal range error (`to == fromFirst`), added `@Suite(.serialized)` to 5 test suites to eliminate `NSGraphicsContext.current` race condition — all unit tests passing ([details](sessions/session-035.md)) |
| 36 | 2026-05-21 | Phase 4 + Phase 5: seeded mosaic RNG, NSSavePanel doc comment, SettingsView defaults wired into ViewModel, redundant accessibility removed, `DebugHelpers` struct for logging — all review fixes complete ([details](sessions/session-036.md)) |
| 37 | 2026-05-21 | Round 11 CR: title editor UX polish (repositioned style buttons, button outlines, BG checkbox icon), BG color bug fix (re-entrancy guard, color well init), alignment persistence on reopen, quality slider dedup, Settings title editor parity ([details](sessions/session-037.md)) |
| 38 | 2026-05-21 | Round 12 CR: style button hit areas (contentShape on outline), title drag offset tracking to eliminate jumpiness ([details](sessions/session-038.md)) |
| 39 | 2026-05-22 | Round 13 CR: ExportPanel reorder (Background above Title, Export controls grouped), right sidebar toggle button, removed left sidebar scroll reflection ([details](sessions/session-039.md)) |
| 40 | 2026-05-22 | Round 14 CR: sidebar image click selects corresponding canvas panel + Panel Editor, scroll/zoom gestures on Panel Editor crop preview ([details](sessions/session-040.md)) |
| 41 | 2026-05-22 | Round 14.1 CR: replaced scroll/pinch with click-and-drag on Panel Editor, corner resize handles for zoom, bolded corner handles matching Title box style ([details](sessions/session-041.md)) |
| 42 | 2026-05-22 | Round 14.2 CR: fixed inverted scroll direction, added missing top-left corner resize, fixed drag direction and sensitivity ([details](sessions/session-042.md)) |
| 43 | 2026-05-22 | Round 14.3 CR: fixed overlay jump on corner resize — container-to-source conversion now accounts for letterboxing offset ([details](sessions/session-043.md)) |
| 44 | 2026-05-22 | AGENTS.md review and progressive disclosure — trimmed inline details, added skill reference links for testing, build, coordinates, windowing ([details](sessions/session-044.md)) |
| 45 | 2026-05-23 | Round 15 CR: performance degradation fix — capped undo stack at 60, guarded `titleStyle.didSet` undo during drag, reverted unnecessary scroll debounce ([details](sessions/session-045.md)) |
| 46 | 2026-05-25 | Round 14.4 CR: fixed Clear All crash — force unwrap `previewImage!` in CollageEditorView replaced with `if let` capture before GeometryReader closure ([details](sessions/session-046.md)) |
| 47 | 2026-05-25 | Round 14.5 CR: proportional corner resize in Panel Editor — crop overlay now maintains panel aspect ratio ([details](sessions/session-047.md)) |
| 48 | 2026-05-25 | Round 15.1 CR: dynamic zoom limits — pinch zoom-out now reaches full image extent, zoom-in capped at 2x, corner-drag clamped ([details](sessions/session-048.md)) |
| 49 | 2026-05-25 | Round 15.2 CR: right sidebar collapse fix — switched to 2-column NavigationSplitView, editor + panel in HStack, proper space reclamation on toggle ([details](sessions/session-049.md)) |
| 50 | 2026-05-25 | Arch review Item 1: extracted UserDefaultsPersistence service — consolidated all keys, PersistenceBundle for init, simplified 13 didSet observers ([details](sessions/session-050.md)) |
| 51 | 2026-05-25 | Arch review Items 2, 3, 4: fixed ExportPanel.chooseBackgroundImage duplication, removed test extension duplication, extracted FitMath utility for aspect-ratio fit math ([details](sessions/session-051.md)) |
| 52 | 2026-05-25 | Arch review Items 5, 6: split AssemblyConfig into LayoutConfig/TitleConfig/BackgroundConfig sub-configs, reduced CollageAssembly protocol from 4 to 2 methods with NSImage wrappers in default extension ([details](sessions/session-052.md)) |
| 53 | 2026-05-26 | Arch review Item 7: added missing tests for ScrollPanManager, TitleMetrics, FontMerger — 3 new files, 32 tests, 150 total passing ([details](sessions/session-053.md)) |
| 54 | 2026-05-26 | Round 16 concurrency modernization (4 changes: DispatchWorkItem→Task, thread-safe image loading, redundant MainActor.run removal, debounced persistence) + panel selection staleness fix (replaced @State frame cache with on-the-fly GeometryReader computations) ([details](sessions/session-054.md)) |
| 55 | 2026-05-27 | Round 17 performance instrumentation (Logger+ContinuousClock timing on 5 operations, 2 performance tests for scroll/preview path) + scheme diagnostics audit + SwiftUI Instruments walkthrough ([details](sessions/session-055.md)) |
| 56 | 2026-05-27 | Round 18 per-panel incremental rendering — `renderPanel`/`renderBackground` methods, layered ZStack in editor, debounced single-panel updates during live gestures, full composite restored on gesture end ([details](sessions/session-056.md)) |
| 57 | 2026-05-27 | Round 18.1 panel editing bugs — async gap fix (don't clear panel cache on gesture end), separate title rendering layer, `isLiveGesturing` wired in panel editor ([details](sessions/session-057.md)) |
| 58 | 2026-05-28 | Full arch review fixes Session 1 — C2 unified cropMap (CropManager sole owner), M2 SettingsView centralized keys, M3 surface persistence errors, M4/M6 docs/annotations, 6 minor fixes, FitMathTests + UserDefaultsPersistenceTests (23 new tests, 172+ total), Panel Editor overlay observation fix ([details](sessions/session-058.md)) |
| 59 | 2026-05-28 | Full arch review fixes Session 2 — C1 extracted PreviewManager (@Observable rendering lifecycle class), C3 added RenderQueue serial dispatch for NSGraphicsContext thread safety, M1 decoupled ScrollPanManager to pure accumulator, PreviewManagerTests + concurrent assembler tests (11 new tests) ([details](sessions/session-059.md)) |
| 60 | 2026-05-28 | Session 2 completion — fixed PreviewManagerTests structural bug (missing closing brace, `.default` → `TitleStyle.default`), all 8 PreviewManagerTests + 3 concurrent assembler tests passing, Session 2 marked complete ([details](sessions/session-060.md)) |
| 61 | 2026-05-29 | Round 19 CR: debounced overlay crop gestures — `cropMapVersion` counter for @Observable tracking, `applyOverlayCropLive`/`finishOverlayCrop` split, PanelCropEditor wired to live/finish, pan/pinch live paths extended ([details](sessions/session-061.md)) |
| 62 | 2026-05-29 | Round 19.1 CR: title drag/resize responsiveness — guarded `updatePreview()` during drag, debounced title-only render at 150ms, `finishTitleDrag()` on gesture end ([details](sessions/session-062.md)) |
| 63 | 2026-05-29 | Round 19.2 CR: title font size slider performance — dedicated `setTitleFontSize`/`setTitleFontFamily` setters with 150ms debounced title-only render, ExportPanel bindings routed through setters ([details](sessions/session-063.md)) |
| 64 | 2026-05-29 | Arch review Phase 1 quick fixes — 6 issues: dead code removal, @Observable on CropManager, unified perfLogger subsystem, FitMath zero-dimension guards (+6 tests), NSColorWell guard removal, LayoutGenerator force-unwrap simplification ([details](sessions/session-064.md)) |
| 65 | 2026-05-29 | Arch review Phase 2 refactors — 6 issues: CollageAssembler rendering dedup, CollageAssembly protocol split (ISP), TitleMetrics caching in VM, NSKeyedArchiver→RGBA hex encoding, scroll pan collapsed into CropManager, LayoutGenerator strategy pattern ([details](sessions/session-065.md)) |
| 66 | 2026-05-30 | Arch review Phase 3 major restructuring — 4 issues: extracted ExportManager (@Observable export lifecycle), extracted ImageLibraryManager (@Observable image operations), extracted GestureCoordinator (ObservableObject for 8 gesture @State vars), Settings defaults doc comment ([details](sessions/session-066.md)) |
