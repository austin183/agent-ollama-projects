# Triage review findings with evidence — an LLM perf estimate ran 10× high on a typed-array loop, and two of its fixes violated pinned scenarios

**Date:** 2026-08-24
**Context:** Metronomad CR 001 Phase 1, world-review over the new `MyESModules/Analysis/` modules. The reviewer flagged `extractPeaks` as **Critical**: "~43 M iterations for a 30-min stereo file… 0.4–0.9 s of main-thread jank… conflicts with the <50 ms budget," and recommended chunking via `requestIdleCallback` or a Web Worker.

## The trap

The estimate assumed 10–30 ns per iteration. A 10-line benchmark of the **actual worst case** (30 min stereo @ 48 kHz = 86.4 M samples/channel — the fileLoader's own cap — real input content, warmed-up V8) measured **59 ms**. Tight typed-array loops run at ~1 ns/iteration once optimized; the "Critical" was 7–15× overstated.

Worse, the recommended fixes were exactly what the plan had already considered and **explicitly deferred**: CR W-6 / plan "What We're NOT Doing" — stride-4 is the v1 mitigation, chunking is *the documented fallback if low-end measurement shows a hitch*. Accepting the finding at face value would have added async complexity to a deliberately pure module, contradicted a settled decision, and done it on the strength of an arithmetic estimate.

The same review produced two more overreaches, each caught by a different check:

- **Shrink the 20 000 001-sample test buffer** "to avoid GC jank/flakiness." But the buffer size *is* the behavior under test — the stride threshold is 20 M samples, and no smaller buffer crosses it. The suite ran 3× reliably green with both 80 MB allocations.
- **Copy the single-channel `mixDown` result** for mutation safety. This directly contradicts pinned WF-P1.9 (reference identity is asserted) and would copy up to ~345 MB for a 30-min file — the no-copy choice is a deliberate performance decision, documented in D-B.

## Rules

1. **Perf findings are claims, not facts.** Before acting on a "main-thread cost / jank / O(n) blowup" finding, benchmark the real worst-case shape (production N, channel count, content) and record the number. In this repo: copy the module to `/tmp` as `.mjs` (Node treats `.js` as CommonJS — rewrite the relative import), drive it with the worst case, `performance.now()` around a warmed-up call. The 59 ms became a citable constant for Phase 7's docs and answers every future "why not chunk?" without re-measuring.
2. **Diff the finding against pinned plan decisions before coding.** Severity labels carry no plan context. A finding that recommends reversing a settled disposition (W-6 here) is a discussion item with a one-line citation of the disposition — not an action item. The cross-cutting constraint "settled constraints are not re-litigated" applies to review findings exactly as it does to plan text.
3. **For test-size/allocation findings, ask "is the size the spec?"** If the input size is the behavior under test (threshold crossing, worst-case bound), shrinking the test to appease the concern *deletes the test*. Verify the reviewer's flakiness anxiety with repeated green runs (3 runs was enough here), then reject with the evidence.
4. **For contract-shaped findings (copy vs reference, guard vs no guard), diff against the pinned scenario rows.** WF-P1.9 pins reference identity; D-B pins the exact guard set (numberOfChannels/length — not `getChannelData` presence, not sampleRate). A "safety" suggestion that violates a pinned row is rejected, and the pin is what the next phase's tests will assert. Where the pin is silent and the concern is real (mutation risk), the fix is a JSDoc contract note ("do not mutate"), not a behavior change.
5. **Keep the measured number in the session summary and timeline.** It is the cheapest possible answer to the next phase's reviewer asking the same question, and it is the input the documented fallback (W-6 chunking) would be judged against on low-end hardware.
