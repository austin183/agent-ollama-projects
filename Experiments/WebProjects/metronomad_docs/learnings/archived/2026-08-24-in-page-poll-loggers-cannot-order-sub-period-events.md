# In-page poll loggers cannot order events closer together than the poll period — use a MutationObserver for one-shot transition ordering

**Date:** 2026-08-24
**Context:** Metronomad CR 001 Phase 4 (waveform wiring + playhead), E2E-3.1: assert that the `ready` state transition lands **strictly before** the first `#waveformCanvas[data-loaded="true"]` frame (W-6: peak work must never delay the READY paint).

## The trap

The project's pinned E2E timing convention is the **5 ms in-page transition logger** (install a `setInterval(read, 5)` that records state changes, anchor `t0` in the same `evaluate` as the trigger, assert on the read-back log). It is the right tool for **continuous** signals — position tracking, monotonic advance, cadence — where sample density only has to be enough to *observe progression*.

It is the **wrong** tool for an **ordering** assertion between two **one-shot** transitions when the gap between them is shorter than the poll period. The gap here is one `setTimeout(0)` (~1 ms) + ~1 ms of peak extraction + a Vue flush ≈ **1.5–4 ms < the 5 ms period**. A poll resolves the order only if a sample lands inside the gap; the probability of missing the gap is ≈ gap/period — a 30–80 % flake, and the failure mode is silent (one frame shows `state=ready && loaded=true` and the ordering is simply unprovable). The plan itself prescribed the 5 ms logger for this row; the deviation was caught at authoring by computing the gap, not by a red test.

## Rules

1. **Before choosing an in-page capture mechanism, compute the gap between the two events in tick units** — which turn does each land in (same microtask flush? a macrotask apart? a `setTimeout(0)` + sync work apart?) — and compare it to the poll period. If gap < period, a poll cannot order them; do not argue your way to "it's usually fine".
2. **For one-shot transition ordering, use an in-page `MutationObserver`** recording each relevant attribute change with its `performance.now()` timestamp:
   ```js
   const record = (kind, value) => timeline.push({ t: performance.now() - t0, kind, value });
   const mo = new MutationObserver((ms) => {
     for (const m of ms) record(m.target === body ? 'state' : 'loaded', m.target.getAttribute('data-loaded') ?? body.dataset.state);
   });
   mo.observe(body, { attributes: true, attributeFilter: ['data-state'] });
   mo.observe(canvas, { attributes: true, attributeFilter: ['data-loaded'] });
   ```
   Observer callbacks run as microtasks after DOM mutation, so two transitions in **different Vue flushes** (guaranteed here: the READY flip is the ok-branch's flush; the paint is a later flush after the `setTimeout(0)` yield) get strictly ordered, sub-millisecond timestamps. No sampling gap, no flake.
3. **Keep the read-back in-page** — the convention's original motivation (node-side poll loops are starved under load) applies to observers just as much; read the timeline back in one `evaluate` and assert there.
4. **Do not abandon the 5 ms logger where it is right.** E2E-3.2 (playhead tracking during playback) in the same spec uses the logger exactly as pinned — same file, different signal shape. The choice is per-assertion, not per-spec.

## Secondary pattern (same phase): driving a pinned `setTimeout(0)` yield deterministically in unit tests

The D-E contract pins the analysis yield as `await new Promise((r) => setTimeout(r, 0))`. To assert *what happens at each continuation* (a superseded task writes nothing; the live task writes), the test must drive that exact mechanism — not replace it with a microtask:

```js
function withPinnedYields(run) {
    const realSetTimeout = window.setTimeout;
    const queue = [];
    window.setTimeout = (cb) => { queue.push(cb); return queue.length; };
    const flushYield = async () => {
        const next = queue.shift();
        if (next) next();
        await Promise.resolve();  // let the resumed task run to completion
        await Promise.resolve();
    };
    return Promise.resolve(run(flushYield)).finally(() => { window.setTimeout = realSetTimeout; });
}
```

Why it works: an `async` function runs **synchronously to its first await**, so by the time `await onFileDropped(...)` resolves, the fire-and-forget task's yield callback is already queued. Each `flushYield()` advances exactly one continuation, making interleavings (A's task dies, B's task applies) explicitly assertable. Two details that matter: restore the real `setTimeout` in `.finally` of the *returned promise* (the `run` body is async — restoring synchronously would break the awaits), and settle 1–2 extra microtasks after each flush (the resumed task completes one hop after the promise resolves). This is the yield-flush sibling of the skill's fake-timer-with-manual-ticks pattern (which serves `setInterval` schedulers) — same discipline, different mechanism, and it touches the one global the production code actually calls.

## Skill mapping (proposed — deferred to user/build-docs)

- `building-web-apps` → `references/testing-e2e.md`, "Sub-second timing assertions" section: add the applicability boundary (continuous-signal vs one-shot-ordering), the gap-computation rule, and the MutationObserver pattern with code.
- `references/testing-unit.md` (mock-VM / fake-timers area): add the FIFO `setTimeout` yield-flush pattern and its two gotchas (`.finally` restore; microtask settle after flush).
