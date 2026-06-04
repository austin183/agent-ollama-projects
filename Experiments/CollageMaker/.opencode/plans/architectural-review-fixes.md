# CollageMaker Architectural Review — Execution Plan

**Generated:** 2026-06-04
**Status:** Phase 1 in progress
**Scope:** All 30 findings from `2026-06-04-full-architectural-review.md`

---

## Completed
- [x] C-2: Deleted `TitleMetrics.swift`

## Remaining by Phase

### Phase 1: Immediate (4 items, ~45 min)
- [ ] S-2: Remove `exportManager` double-init (CollageViewModel.swift:88)
- [ ] W-10: Fix force cast in ScrollPanView.swift:19
- [ ] C-1: Fix `isProcessing` race - reference-counted tracker
- [ ] C-2 (remaining): Update doc comment in TitleRendererCT.swift:217

### Phase 2: Refactoring (6 items, ~3 hr)
- [ ] W-5: Extract property change helper + refactor title setters
- [ ] W-2: Fix ExportManager DIP violation
- [ ] W-8: Extract cancelAllTasks() in PreviewManager
- [ ] W-9: Extract CTAttributedStringBuilder in TitleRendererCT
- [ ] W-7: BackgroundConfig computed CGColor properties
- [ ] W-3: Structured AssemblyConfig secondary init

### Phase 3: Architecture (3 items, ~3 hr)
- [ ] S-1: Convert GestureCoordinator to @Observable
- [ ] W-6: Extract business logic from Views
- [ ] W-4: CollageAssembler sub-renderer injection

### Phase 4: Polish (16 items, ~4 hr)
- [ ] S-3 through S-18 (see review doc for details)

### Phase 5: Tests (4 items, ~2 hr)
- [ ] RenderScheduler tests, ExportManager tests, ImageLibraryManager tests, Mock consolidation
