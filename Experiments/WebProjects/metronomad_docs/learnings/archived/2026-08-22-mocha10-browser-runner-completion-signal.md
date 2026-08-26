# Mocha 10 Browser Runner: the "completion" wait is vacuously true — await the Runner's `end` event

**Date:** 2026-08-22
**Context:** Metronomad Phase 1 (I-9) — hardening `scripts/run-tests.cjs` so it can no longer report green with zero tests. While re-deriving a *reliable* completion signal, I found the wait condition documented in the project skill (`references/testing-unit.md` ~L77–97, `SKILL.md` L177) and in `2026-08-18-mocha-runner-async-suite-undercount.md` is **dead code** under mocha 10.2.0.

## What the existing guidance claims

Wait for the run to settle before extracting:

```js
const s = runner.stats;
return s.tests === s.passes + s.failures + s.pending;
```

and asserts (testing-unit.md L95): *"`runner.stats.tests` is the total registered count; mid-run it **exceeds** the sum of the three outcome buckets and equals it only at completion."*

## What is actually true in mocha 10.2.0

1. **`mocha._runner` does not exist.** The bundled `Mocha.prototype.run` creates `const runner = new this._runnerClass(...)` and `return`s it — it never assigns `this._runner`. Grepping the bundle for `_runner` (excluding `_runnerClass`/`_previousRunner`) returns zero hits. So `(typeof mocha !== 'undefined' && mocha._runner)` is **always falsy**.
2. **`stats.tests` counts *completed* tests, not the registered total.** `createStatsCollector` wires `runner.on('test end', () => { stats.tests++; })`, with `passes++` / `failures++` / `pending++` on the matching end events. So `tests` and (one of) `passes+failures+pending` increment **in lockstep on every test end** — the equality `tests === passes + failures + pending` holds at **every** instant, not only at completion. The documented wait condition is **vacuously true**.

## Why it was never noticed

Because `mocha._runner` is always undefined, `waitForFunction` never satisfied the runner branch, rode the **full 30 s timeout** per file, and fell through to the DOM fallback (parsing `#mocha .passes em` / `.failures em`). The DOM is final well before 30 s, so the numbers came out **correct but slow** (~30 s × file count ≈ 2.5 min for 5 files). The broken gate was **masked by the timeout fallthrough** — it looked like it was working. That's the insidious part: a dead completion condition is invisible when a generous timeout silently does the real work.

## The correct completion signal

The Runner's **`end`** event (`EVENT_RUN_END` — emitted when the root suite completes, *after* the HTML reporter has rendered final stats). The Runner is reachable **only** as the return value of `mocha.run()`. Inject an init script that wraps `mocha.run` *before* the test page's own `load` listener (init scripts run first, so their listener dispatches first on `load`):

```js
await context.addInitScript(() => {
    window.__mochaRun = null; // { unavailable } | { settled, runner }
    window.addEventListener('load', () => {
        if (typeof mocha === 'undefined' || typeof mocha.run !== 'function') {
            window.__mochaRun = { unavailable: true };   // CDN blocked
            return;
        }
        const originalRun = mocha.run;
        mocha.run = function (...args) {
            const runner = originalRun.apply(mocha, args);
            window.__mochaRun = { settled: false, runner };
            runner.on('end', () => { window.__mochaRun.settled = true; });
            return runner;
        };
    }, { once: true });
});
// ...navigate, then:
await page.waitForFunction(() => {
    const run = window.__mochaRun;
    return !!run && (run.unavailable || run.settled);
}, null, { timeout: 30000 });
```

Then read `window.__mochaRun.runner.stats` (final at `end`) for `passes`/`failures`/`pending`, and parse the `.fail` DOM for failure detail. A blocked CDN, a run that never starts, or a hung suite now resolve to a **fast, named** per-file error (sub-second) instead of a 30 s stall.

## Rules

- **Never** gate in-browser Mocha completion on `runner.stats.tests === passes + failures + pending` — in mocha 10 it is an always-true identity, not a completion gate.
- **Don't rely on `mocha._runner`** — the v10 browser build does not expose the runner on the instance.
- **Await the Runner's `end` event**, reached via the return value of `mocha.run()` (wrap it in an init script).
- Keep a timeout fall-through, but make it **diagnostic** — name the failure ("mocha.run() never reached", "Mocha unavailable (no runner)", "did not settle (N tests complete)") — rather than a silent stall that happens to land on the right answer.

## Bonus false-green found in the same pass

The v1 runner exited **0 even when individual tests failed** — it only threw when *every* file failed. "Green" CI output did not mean "no failing tests." The hardened runner collects per-file errors (including `N failing test(s)` with each failing title + first error line, printed) and exits **non-zero on any per-file failure**.

## Skill handoff (build-docs)

`references/testing-unit.md` ~L77–97 and `SKILL.md` L177 document the vacuous wait and the false "`stats.tests` = total registered" claim. Correct both to the capture-the-returned-runner-and-await-`'end'` pattern above, and note that `mocha._runner` does not exist in the mocha 10 browser build. This **supersedes** the "Solution" section of `2026-08-18-mocha-runner-async-suite-undercount.md` (the undercount *symptom* it describes is real; its proposed fix is not).
