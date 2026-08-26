# Refactor contracts: pin behavior, not code shape — "keep the existing structure" goes stale when the method's semantics change

**Date:** 2026-08-22
**Context:** Metronomad review-remediation Phase 2 (RD-6 teardown ownership flip). The plan's fix contract pinned a *code shape* — "the `else if (this._engine)` fallback … is retained as defense." The as-built code is a plain `if (this._engine)`, and it had to be.

## The trap

v1's `beforeUnmount` was:

```js
if (this._beatDots) {
    this._beatDots.stopAll();        // v1: stopAll internally called engine.dispose()
} else if (this._engine) {
    this._engine.dispose();          // reached only when the visualizer never mounted
}
```

The `else if` was **compensating for old semantics**: it existed because `stopAll` already owned the engine teardown, so the dispose branch only needed to fire when there was no visualizer.

Phase 2 changed `stopAll` to touch visualizer resources only (I-6). If the plan's pinned shape had been transcribed literally — `if (this._beatDots) stopAll(); else if (this._engine) dispose();` — the **normal path** (visualizer present, which is every successful mount) would run `stopAll()` and skip the `else` → `engine.dispose()` never called → scheduler intervals and sources leak on every unmount. The "retain as defense" instruction, applied to the *new* semantics, converts the defense branch into the leak.

The correct as-built shape is two **independent** guards:

```js
if (this._beatDots) { this._beatDots.stopAll(); this._beatDots = null; }
if (this._engine)   { this._engine.dispose();  this._engine = null; }
```

## Rules

1. **When a refactor changes what a referenced method does, every piece of surrounding control flow that interacted with the old semantics must be re-derived, not preserved.** "Keep the existing structure" is only safe when the method contract is unchanged. In plan fix-contracts, describe the *behavioral* target (who calls what, how many times) and treat any pinned syntax (`else if` vs `if`, guard ordering) as a hint to verify, not a literal to copy.
2. **The behavior test is what catches a literal transcription.** B-06 (unmount with everything mounted → `engine.dispose` called exactly once) fails against the naive `else if` port and passes against independent guards. When a phase flips ownership between two components, add the "normal path, everything present" ordering test — the fallback-variant test (R-I6.2's `_beatDots` absent case) alone would pass *both* shapes and never catch the leak.
3. **Flag shape deviations in the session summary for plan correction** (done here — RD-6's text is now known-stale for the `else if` sentence) rather than silently adapting: the plan is the contract for later phases, and a stale pinned shape in context.md is a trap for the next reader.

## Secondary observation: contract-change tests must RED against the old implementation

During R-I7.1 (delete all global monkey-patching from `BeatDotsTest.html`, inject fakes instead), the new injected-fake tests produced **10 real failures** against the old global-reading module. That RED is the proof the suite now pins the injection contract. In refactor-heavy phases where tests move *with* the code instead of strictly ahead, verify the direction: a *changed* test that passes unchanged against the old code is pinning nothing. (The build-tdd agent's "RED was real" check — run the new tests against the pre-refactor module before touching it.)

## Minor (plan-authoring)

Test-count success criteria like "the count drops by exactly P-12's size" are ambiguous when the phase also *adds* rows (removals-gross vs net). Here: 142 − P-12 + 4 new rows = 145. Write the arithmetic explicitly (`baseline − removed + added = expected`) so future phases don't have to interpret.
