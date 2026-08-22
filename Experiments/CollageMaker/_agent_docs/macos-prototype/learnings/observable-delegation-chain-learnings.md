# @Observable Delegation Chain — Learnings

**Date:** 2026-05-28
**Session:** 58
**Purpose:** Document learnings from unifying `cropMap` ownership between `CollageViewModel` and `CropManager`, and the resulting SwiftUI observation bug.

---

## What Worked

- **Single source of truth via computed property delegation** — Converting a stored property on the ViewModel into a computed property that delegates to a sub-manager eliminates dual-state sync bugs. Pattern:
  ```swift
  // Before: dual state, manual sync at ~15 mutation sites
  var cropMap: [UUID: CropInfo] = [:]
  // ... cropMap = cropManager.cropMap (repeated everywhere)

  // After: single owner, computed property on ViewModel
  var cropMap: [UUID: CropInfo] {
      get { cropManager.cropMap }
      set { cropManager.cropMap = newValue }
  }
  ```

- **Grep-based sync line audit** — After removing the stored property, `grep "cropMap = cropManager"` confirmed all manual sync lines were eliminated. This is a reliable verification step for any SST unification.

- **Persistence error surfacing** — Changing `try?` to `try/catch` in `debouncedSave()` with error logging + `errorMessage` surface ensures persistence failures are visible rather than silently losing user data.

## What Didn't Work / Gaps

- **@Observable doesn't propagate through computed property delegation** — This is the critical gotcha. When `CollageViewModel.cropMap` became a computed property delegating to `cropManager.cropMap`, SwiftUI views that read `viewModel.cropMap` stopped receiving updates during drag gestures. The image moved (via `updatePreview()` which sets stored properties) but the overlay didn't re-render.

  Root cause: `CropManager` was a plain class, not `@Observable`. SwiftUI's observation tracking for `CollageViewModel` only covers its own stored properties. A computed property that reads `cropManager.cropMap` is just a function call — SwiftUI doesn't know `cropManager` is an observable dependency.

  **Fix (two parts, both required):**
  1. Make `CropManager` `@Observable` — so mutations to its properties emit observation events
  2. Have the view read `viewModel.cropManager.cropMap` directly — so SwiftUI registers `cropManager` as an observation dependency

  Reading through the computed property (`viewModel.cropMap`) is insufficient because SwiftUI's observation is attached to the `CollageViewModel` instance, not to transitively accessed objects.

- **UserDefaults test suite instability** — A computed property that creates a new `UserDefaults(suiteName: UUID())` on each access produces a different suite per read. Save and load go to different suites, causing every test assertion to fail. Must store the suite as a stable instance property initialized in `init`.

## Key Patterns

### @Observable Delegation Chain Rules

| Scenario | Observation Works? | Fix |
|---|---|---|
| Stored property on @Observable class | Yes | None needed |
| Computed property reading another object's property | **No** | Make delegate @Observable + read delegate directly in view |
| View reads through computed property (`vm.cropMap`) | **No** | Read delegate directly (`vm.cropManager.cropMap`) |
| View reads delegate directly but delegate is plain class | **No** | Add @Observable to delegate |

### Diagnostic Clues for Delegation Observation Bugs

If a view updates for some state changes but not others after refactoring:
1. Check if any properties changed from stored to computed
2. Check if the delegate object is `@Observable`
3. Check if the view reads the delegate directly (not through the computed property)
4. The symptom is often partial: stored properties still update, but the delegated property doesn't

### Eliminating Dual State — Verification Checklist

When unifying dual state (e.g., removing shadow copy from ViewModel):
1. Remove the stored property from the secondary owner
2. Add a computed property that delegates to the primary owner
3. Grep for `= primaryOwner.property` to find all manual sync lines
4. Remove each sync line
5. Verify grep returns zero matches
6. Build and run — check for observation gaps (views that stop updating)
7. If observation gaps appear: ensure delegate is `@Observable` + views read delegate directly

## Skill Improvements

- The `building-macos-apps` skill should document the @Observable delegation chain rules — this is a general SwiftUI/macOS pattern, not specific to CollageMaker
- The `testing-patterns.md` reference should include the UserDefaults test suite stability pattern

## Next Steps

- Consider documenting the delegation chain pattern in the building-macos-apps skill
- Session 2 of the arch review fixes (Phase 3: PreviewManager extraction, RenderQueue, ScrollPanManager decoupling) should re-apply these patterns

---
**Status:** Closed
**Follow-up:** Session 59 (Phase 3 arch review fixes)
