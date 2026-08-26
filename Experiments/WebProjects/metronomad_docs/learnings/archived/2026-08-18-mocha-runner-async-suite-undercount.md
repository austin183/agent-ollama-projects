# In-Browser Mocha Runner: Mid-Run Extraction Silently Undercounts Async Suites

**Date:** 2026-08-18
**Context:** Metronomad Phase 3 (File Loading) — first async unit suite (real MP3 decoding) run through `scripts/run-tests.cjs`

## Problem

`FileLoaderTest.html` registered 14 tests, but the first run reported:

```json
{ "passes": 8, "failures": 0, "pendings": [] }
```

8 passing, 0 failing — a snapshot that looks like a *clean pass* but actually means 6 in-flight tests were invisible. The missing 6 were all async (real `decodeAudioData` calls, 100–500 ms each); the 8 that "passed" were the synchronous tests that had finished before extraction ran.

## Root Cause: Extraction Races the First Rendered Result

The runner (adapted from `CollageMaker/scripts/run-tests.js`) waits for `#mocha .test` — the **first** rendered test result — and then immediately extracts `runner.passes()/failures()`. For all-synchronous suites (Phase 2's 34 pure-math tests, and most of CollageMaker's suites) the whole run completes before the first DOM result is painted, so extraction is safe. The moment a suite contains meaningful async work, extraction fires mid-run and the result is a silent partial pass.

Worse: because `failures` is a live array read at extraction time, a *failing* async test that hadn't finished yet also vanishes. The failure mode is indistinguishable from success.

## Solution: Wait for Run Completion Before Extracting

Robust completion signal — every registered test accounted for:

```js
await page.waitForFunction(() => {
    const runner = (typeof mocha !== 'undefined' && mocha._runner) ||
        (window.Mocha && window.Mocha.runner);
    if (!runner || !runner.stats) return false;
    const s = runner.stats;
    // Done when every registered test is accounted for.
    return s.tests > 0 &&
        s.tests === s.passes + s.failures + s.pending;
}, { timeout: 30000 });
```

Notes:
- `runner.stats.tests` is the total registered count; during the run it exceeds the sum of the three outcome buckets, and equals it only at completion.
- Avoided `runner.state === 'finished'` — the Runner state value set varies across Mocha versions and wasn't worth betting extraction on.
- Keep the 30 s `waitForFunction` timeout as a fall-through so a hung suite still produces a (partial) report instead of crashing the runner.

**Status:** fixed in `Metronomad/scripts/run-tests.cjs`.

## Skill Mapping

- **`building-web-apps` → `references/testing-unit.md`** should gain a warning in the "Unit Tests — Mocha + Chai" section: the in-browser pattern is fine for sync suites, but any suite with real async work (decoding, timers, RAF flushes that await) needs the runner to wait for run completion before extracting results; "N passing / 0 failing" with N < registered tests is the signature of a mid-run snapshot, not a clean pass.
- **CollageMaker's original `scripts/run-tests.js` has the same latent issue** (its suites happen to be synchronous). If the runner is ever shared/extracted, apply the completion wait there too.

## Related Gotcha (same session)

chai `deep.equal` distinguishes `['idle']` from `['idle', undefined]` (different array lengths). Event-recorder test helpers that push `[state, detail && detail.fileName]` record a trailing `undefined` for detail-less events and silently break every "no detail" assertion. Normalize absent details to an explicit sentinel (`null`) in the recorder. Candidate for the "Chai CDN Limitations" section of `testing-unit.md`.

---
**Status:** Closed (fix landed in Metronomad runner; skill update pending build-docs)
**Follow-up:** Phase 4 (PlaybackEngine) suites use injected fake timers and are mostly synchronous, but the completion wait is now the baseline for any Metronomad test page
