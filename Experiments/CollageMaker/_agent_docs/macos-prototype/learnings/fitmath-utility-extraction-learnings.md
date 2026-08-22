# FitMath Utility Extraction — Learnings 2026-05-25

**Purpose:** Document learnings from extracting shared aspect-ratio fit math (`FitMath`) and the regression it caused.

## What Worked

- **Single-source extraction** — Consolidating 6 duplicated if/else blocks (120+ lines of duplicated fit math) into two static methods (`FitMath.fit` and `FitMath.sourceRect`) reduced code significantly and made the algorithm easier to reason about.

- **Test suite caught the regression** — The existing `CropManagerTests` for `canvasToPreviewFrame` and `screenToCanvasPoint` passed because they test specific input/output pairs. The regression was caught by manual testing (panel selection failing), not by unit tests.

## What Didn't Work / Gaps

- **Swapped if/else branches in `FitMath.fit`** — The initial implementation filled the **height** when `sourceAspect > containerAspect`, but the correct behavior is to fill the **width**. The intuition is counterintuitive: when the source is *wider* than the container (higher aspect ratio), the **width** is the constraining dimension, so you fill the container's full width and derive height from the source's aspect ratio. Getting this backwards produced wrong fitted sizes that broke `screenToCanvasPoint`, which is used for canvas hit-testing — clicks never landed on the correct panel.

- **No unit test for `FitMath.fit` itself** — The extracted utility had no dedicated tests. The existing tests exercise the call sites (CropManager, CoordinateConverter) but don't test the utility in isolation with known inputs. A simple test like `#expect(FitMath.fit(CGSize(width: 1920, height: 1080), into: CGSize(width: 746, height: 821)).fittedSize.width == 746)` would have caught the branch swap immediately.

- **`FitMath.sourceRect` uses `>` while `FitMath.fit` uses `>=`** — The equality case (`sourceAspect == containerAspect`) is handled differently: `sourceRect` falls through the `else` branch (fills width), while `fit` takes the `>=` branch (also fills width). Both are correct for the equality case since both dimensions fill equally, but the inconsistency is a maintenance risk.

## Key Pattern: Aspect-Ratio Fit Branch Direction

The "fit source into container" algorithm has two branches determined by aspect ratio comparison:

```swift
// CORRECT: when source is wider (higher aspect), fill container width
if sourceAspect >= containerAspect {
    fittedSize = CGSize(width: containerWidth, height: containerWidth / sourceAspect)
} else {
    fittedSize = CGSize(width: containerHeight * sourceAspect, height: containerHeight)
}
```

**Mnemonic:** The branch that triggers on `>` (source is wider) fills the **width** (the constraining dimension). The `else` branch (source is taller) fills the **height**. It's easy to write the opposite — fill height when source is wider — which produces a result that's too small in one dimension and too large in the other.

## Relation to Existing Learnings

- **Coordinate systems** (`collagemaker-prototype-2-coordinate-systems-learnings.md`): Documents the broader fitted-size-inverted bug (scaling up vs down). This learning is about the specific if/else branch direction within the correct formula.

- **Aspect-ratio-constrained resize** (`aspect-ratio-constrained-resize-learnings.md`): Documents the dominant-dimension pattern for drag-to-resize. That pattern is related (both compare aspect ratios) but operates in the inverse direction (user drag → constrained dimensions vs source size → container fit).

## Skill Improvements

### `building-macos-apps` skill — Coordinate Systems reference

Add a note about the branch direction gotcha when extracting fit math:

> **Fit math branch direction:** When implementing "fit source into container," the `if sourceAspect > containerAspect` branch should fill the container's **width** (the constraining dimension), not the height. The wider source hits the width wall first. This is counterintuitive — the branch that triggers on "source is wider" fills width, not height.

### Testing patterns

When extracting a pure-math utility from duplicated code paths, write a dedicated test file for the utility before refactoring the call sites. Test with concrete known values (e.g., 1920x1080 into 746x821) to verify the fitted size and offset match expected values.

---
**Status:** Closed
**Follow-up:** None
