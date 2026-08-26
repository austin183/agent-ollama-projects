# P0 Test Follow-Up — Recommendations & Next Steps

**Date:** 2026-07-02
**Parent:** [Test Plan](./2026-07-01-collagemaker-test-plan.md)
**Session:** [Session 006](../project-timeline/sessions/session-006-summary.json)
**Status:** All 156 P0 tests pass (150 unit + 6 E2E)

---

## Summary

All P0 test sets from the test plan are implemented and passing:

| Test File | Type | Tests | Assertions |
|---|---|---|---|
| `MyComponents/LayoutMathTest.html` | Unit (Mocha/Chai) | 93 | ~250 |
| `MyComponents/UndoManagerTest.html` | Unit (Mocha/Chai) | 20 | ~50 |
| `MyComponents/EdgeCasesTest.html` | Unit (Mocha/Chai) | 37 | ~90 |
| `test/e2e/workflow-tests.spec.cjs` | E2E (Playwright) | 6 | ~25 |
| **Total** | | **156** | **~415** |

---

## World Review Findings

A world-review subagent analyzed all test files from a real-world user experience perspective. Below are the categorized findings and recommended actions.

---

### 🔴 High Priority — Fix Before Phase 3

#### 0. Critical Bug: Broken Batch Undo/Redo Logic (UndoManager)

**Source:** diff-review-g31 subagent

**Problem:** The `beginBatch` / `endBatch` implementation in `MyESModules/State/UndoManager.js` is fundamentally broken.

- **Snapshot return vs. apply:** `endBatch` creates undo/redo functions that simply **return** a snapshot (`() => preSnapshot`) instead of **applying** that snapshot to the state. Because `UndoManager.undo()` and `redo()` call these functions and discard the return value, batch operations have **no effect** on the state.
- **Batch composition bug:** In `UndoManager.push()`, when a batch is active, it replaces `batchCommand.undo` with only the **latest** command's undo function. This means a batch only undoes the very last operation in the sequence, not the entire group.

**Evidence:** `UndoManagerTest.html` tests 3.1.11, 3.1.12, and 3.1.13 assert that state remains unchanged after a batch undo — effectively documenting the bug as intended behavior.

**Impact:** Any feature that relies on batched undo (crop drag sessions, multi-image operations) will silently fail to restore state on undo/redo. This is a blocker for Phase 3.

**Action:** Fix `UndoManager.endBatch()` so that undo/redo functions **apply** the snapshot to the state object (e.g., `Object.assign(state, snapshot)`) rather than returning it. Update the batch composition logic to accumulate all operations in the batch, not just the last one. Fix the 3 UndoManager batch tests to assert correct behavior.

---

#### 1. Replace `waitForTimeout()` with Assertion-Based Waits

**Problem:** All 6 E2E tests use hardcoded `waitForTimeout()` delays (100ms–3000ms) which are fragile in CI environments where server startup, image decode, and render timing vary.

**Current pattern:**
```javascript
await page.waitForTimeout(3000); // after image upload
await page.waitForTimeout(500);  // between layout changes
```

**Recommended pattern:**
```javascript
// Wait for images to actually appear in the library
await page.waitForSelector('.image-item', { state: 'visible' });

// Wait for canvas to be visible after layout change
await page.locator('#previewCanvas').waitFor({ state: 'visible' });

// Rely on Playwright auto-waiting for clicks/fills
await page.locator('#layoutStyleSelect').selectOption('mosaic');
```

**Action:** Refactor `test/e2e/workflow-tests.spec.cjs` to eliminate all `waitForTimeout()` calls in favor of explicit waits.

---

#### 2. Add Keyboard Shortcut E2E Tests

**Problem:** Only `Cmd+Z` / `Ctrl+Z` undo is tested (in 12.8.6). Core keyboard shortcuts are missing from E2E coverage.

**Missing tests:**
- `Cmd+Shift+Z` / `Ctrl+Shift+Z` redo via keyboard
- `Escape` to deselect panel (verify selection border disappears)
- Keyboard shortcuts with focus on slider/search input (verify no conflict)

**Action:** Add 3–4 E2E tests to `workflow-tests.spec.cjs` or a new `keyboard-tests.spec.cjs`.

---

#### 3. Add Crop Editing E2E Flow

**Problem:** The primary user interaction — selecting a panel and editing its crop — has zero E2E coverage. All crop tests are unit-level only.

**Recommended test flow:**
1. Upload 3 images
2. Click a panel on canvas to select it
3. Verify crop preview canvas appears with crop overlay
4. Drag crop region (simulate pointer events)
5. Verify main canvas updates with new crop
6. Click "Reset Crop" button
7. Verify crop returns to default centered position
8. Verify undo reverts the reset

**Action:** Add 1–2 E2E tests covering the full crop editing flow.

---

#### 4. Verify Undo/Redo Button State Synchronization

**Problem:** No test verifies that the Undo/Redo buttons correctly reflect their enabled/disabled state based on history.

**Missing tests (from test plan 12.6.8–12.6.10):**
- Undo button disabled on fresh page load
- Redo button disabled on fresh page load
- Undo button enabled after a crop adjustment
- Redo button enabled after an undo
- Redo button disabled after a new action following an undo

**Action:** Add 3–4 E2E assertions to existing workflow tests or a dedicated test.

---

### 🟡 Medium Priority — Improve P1 Coverage

#### 5. Add Drag-and-Drop Visual Feedback Test

**Problem:** Tests use `#fileInput` to upload, but the actual drag-and-drop flow (visual feedback, drop handling) is untested.

**From test plan 5.3.5–5.3.7:**
- Dragenter adds `drag-over` class to body
- Dragleave removes class (with counter for nested drags)
- Drop callback fires with filtered file list

**Action:** Add 1 E2E test that simulates drag-and-drop with visual feedback verification.

---

#### 6. Test "Clear All" + Selection State Cleanup

**Problem:** When a user selects a panel then clicks "Clear All", the `selectedPanelId` may become stale. No E2E test verifies the UI handles this gracefully.

**From test plan 8.4.1:**
- Select panel, then clear all → `selectedPanelId` should be reset to null
- No stale selection border should remain on canvas

**Action:** Add 1 E2E test covering this flow.

---

#### 7. Verify Theme Toggle Doesn't Break Canvas Rendering Context

**Problem:** Test 12.8.2 checks canvas visibility after theme toggle but not whether the canvas actually renders correctly (DPR scaling, color contexts, shadow rendering).

**Action:** Enhance 12.8.2 to verify canvas pixel content after theme toggle (e.g., use `page.screenshot()` comparison or pixel sampling).

---

### 🟢 Low Priority — Nice to Have

#### 8. Platform-Agnostic Keyboard Shortcuts

**Problem:** Test 12.8.6 uses `process.platform === 'darwin'` to choose between `Meta+z` and `Control+z`. In Linux CI, this may not match the browser's expected modifier behavior.

**Recommendation:** Use Playwright's built-in keyboard helpers or test both modifier combinations regardless of platform.

---

#### 9. Add Performance Baseline Tests

**Problem:** Section 9 (Performance) from the test plan is P2. Consider adding a simple baseline that measures render time for 10/30 panels to catch regressions.

**Action:** Add 2–3 performance smoke tests to the E2E suite (non-blocking, with generous thresholds).

---

## Diff Review Findings (diff-review-g31)

A diff-review subagent analyzed all uncommitted changes for code quality, correctness, and reliability issues.

### Test Duplication

**Source:** diff-review-g31 subagent

Two areas of redundant testing were identified across unit test files:

| Duplicated Test | File 1 | File 2 |
|---|---|---|
| 60-level undo cap | `UndoManagerTest.html` (3.1.9) | `EdgeCasesTest.html` (7.3.1) |
| Extreme aspect ratio math | `LayoutMathTest.html` (1.1.10–1.1.11) | `EdgeCasesTest.html` (8.1.6) |

**Recommendation:** Keep the tests in their more focused home (UndoManagerTest for undo cap, LayoutMathTest for aspect ratios) and remove the duplicates from EdgeCasesTest. This reduces maintenance burden and clarifies ownership.

### Playwright Config Assessment

**Source:** diff-review-g31 subagent

The `playwright.config.cjs` setup is sound:
- `workers: 1` and `fullyParallel: false` are appropriate to avoid race conditions during temp file creation/cleanup
- `timeout: 30000` is generous enough for image-heavy workflows
- `trace: 'on-first-retry'` balances debuggability with CI speed

**No changes needed.**

---

## Recommended Execution Order

1. **Blocker:** Fix UndoManager batch undo/redo logic (#0) — this is a production bug, not just a test gap
2. **Immediate:** Refactor E2E `waitForTimeout()` → assertion-based waits (#1)
3. **Before Phase 3:** Add keyboard shortcut tests (#2), crop editing flow (#3), undo/redo button state (#4)
4. **Phase 1 P1 tests:** Add drag-and-drop (#5), clear all cleanup (#6), theme rendering (#7)
5. **Ongoing:** Address platform shortcuts (#8), performance baselines (#9)
6. **Cleanup:** Remove test duplication (diff review findings)

---

## Test Infrastructure Notes

### Running Unit Tests
```bash
# All Mocha/Chai test files (auto-discovers *Test.html in MyComponents/)
cd CollageMaker && node scripts/run-tests.js

# Specific test file
node scripts/run-tests.js LayoutMathTest.html
```

### Running E2E Tests
```bash
# All Playwright E2E tests (requires dev server on :8000)
cd CollageMaker && npx playwright test --config=playwright.config.cjs

# Specific test file
npx playwright test --config=playwright.config.cjs workflow-tests.spec.cjs
```

### Dependencies
- `@playwright/test` installed at workspace root (`../package.json`)
- Chromium browser installed via `npx playwright install chromium`
- Mocha 10.2.0 + Chai 4.3.10 loaded via CDN (no install needed)
