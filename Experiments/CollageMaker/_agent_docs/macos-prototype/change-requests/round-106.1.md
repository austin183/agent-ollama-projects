# Fix Pre-existing Test Bug: finishDragCancelsDebouncerAndSaves

The test `TitleManagerTests/finishDragCancelsDebouncerAndSaves()` has been failing since at least commit `0a705bb` (3+ commits ago). It asserts `updater.debouncedSaveCalls == 1`, but `TitleManager.finishDrag()` only calls `cancelDebouncer(id:)` and `updateImage(updater:)` — it never calls `debouncedSave()`. The `PreviewUpdatable` protocol does not have a `debouncedSave()` method.

**Fix**: Remove the `#expect(updater.debouncedSaveCalls == 1)` assertion from the test, or add `debouncedSave()` to `PreviewUpdatable` and wire it into `TitleManager.finishDrag()` if that was the original intent.

**Files**:
- `CollageMaker/CollageMakerTests/TitleManagerTests.swift:636` — the failing assertion
- `CollageMaker/CollageMaker/ViewModel/PreviewUpdatable.swift` — protocol definition
- `CollageMaker/CollageMaker/ViewModel/TitleManager.swift:91-94` — `finishDrag()` implementation
