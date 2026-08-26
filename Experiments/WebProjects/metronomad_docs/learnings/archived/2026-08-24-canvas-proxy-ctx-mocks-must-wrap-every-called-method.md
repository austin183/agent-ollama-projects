# Canvas 2D Proxy ctx mocks: wrap EVERY method production calls, and read the record off the plain object — never through the proxy

**Date:** 2026-08-24
**Context:** Metronomad CR 001 Phase 3, `MyComponents/WaveformViewTest.html` (WF-V1.1…WF-V1.10). First suite in this repo whose production code draws on a canvas through an injected fake. The skill's `canvas-2d.md` "Canvas 2D Context Mocking" pattern was followed, and it has two latent gaps that cost a full debugging round.

## Trap 1 — an unwrapped host method called through the proxy throws `Illegal invocation`

The skill pattern wraps only the methods you anticipate (`fillRect`, `fillText`, …) and returns `target[prop]` for everything else. That fallback is a **landmine**: canvas context methods type-check their `this`. When production calls an unwrapped method,

```js
ctx.beginPath(); // via the proxy: get trap returns target['beginPath'],
                 // called with this = the PROXY → TypeError: Illegal invocation
```

The failure is not "missing method" — it is a bare `Illegal invocation` with no hint about which call site, and it surfaces inside the production module's RAF callback, so the stack points at the module, not the mock. The fix: **wrap every method the production code can call, and re-apply with the real ctx as `this`**:

```js
const wrap = (name) => (...args) => { rec[name].push(args); return real[name].apply(real, args); };
// get trap: if (prop === 'beginPath') return () => { rec.beginPath++; return real.beginPath(); };
```

Audit the production render function's full call surface (`setTransform`, `clearRect`, `beginPath`, `moveTo`, `lineTo`, `stroke`, …) before the first GREEN run, not after the first red stack.

## Trap 2 — the proxy's `get` trap returns the *wrapper function* for tracked properties

If the trap serves tracked properties from the proxy (`ctx.moveTo`), the test reads **a function**, not the recorded calls — `expect(ctx.moveTo).to.have.lengthOf(300)` fails with `expected [Function] to deeply equal …`, which looks like an implementation bug. The record must be a **plain object exposed separately** from the proxy:

```js
function makeRecordingCtx() {
    /* …build proxy with traps… */
    return { proxy, rec };   // production gets proxy; assertions read rec
}
const rctx = makeRecordingCtx();
fakeCanvas.getContext = () => rctx.proxy;
expect(rctx.rec.moveTo).to.have.lengthOf(300);  // never fakeCanvas.ctx.moveTo
```

## Secondary trap (same phase, different shape) — "mocha.run() was never reached" is a disjunction

The in-browser runner's broken-page signal (the pinned R-11 shape for missing barrel exports) fires for **any** page-level failure before `mocha.run()` settles — including the new test page simply forgetting its trailing `window.addEventListener('load', () => mocha.run())` listener. Symptom that distinguishes the two: after fixing the pinned cause (the barrel export), the signal **persists identically**. Disambiguate in one probe before suspecting the implementation: load the page with Playwright and check (a) `pageerror` (module link failures report here; a missing `mocha.run()` listener does not), and (b) whether `window.mocha.run()` invoked manually executes the registered tests. A silent page + registered tests + manual run works = the page scaffolding is incomplete, not the module.

## Rules

1. **Wrap the full call surface.** Before the first GREEN run of a canvas-rendering test, list every ctx method the render path invokes; each gets a wrapper that records + re-applies with the real ctx as `this`. Properties (`strokeStyle`, `lineWidth`) go through the `set` trap — they are safe unwrapped.
2. **Return `{ proxy, rec }` from the ctx factory.** Production receives the proxy; assertions read `rec`. If a test is tempted to assert through the fake canvas (`canvas.ctx.moveTo`), that is the bug — the proxy serves functions there.
3. **A persistent "mocha.run() was never reached" after fixing the pinned cause is scaffolding, not implementation.** Run the one-page Playwright probe (pageerror + manual `mocha.run()`) before touching production code.
4. **Test-expectation arithmetic for cumulative call logs must account for full repaints.** A renderer that clears-and-redraws every frame appends the *entire* scene per render (300 + 301 + 300 = 901, not 900). Compute the running total render-by-render; "previous total + new elements" is the usual mistake.
5. **Pick binary-exact inputs for strict-equality position assertions.** `(90/300)·3 === 0.9` is `false` in float64 (it is `0.8999999999999999`). Choose coordinates whose fraction of the width is dyadic (75 of 300 → `0.75`), or use `closeTo` only for values that are genuinely computed (never for the pinned contract values like the plan's 50 % → `1.5` example, which *is* dyadic and must stay exact).

## Skill mapping (applied 2026-08-24)

Applied to `skills/building-web-apps/references/testing-unit.md` (the "Canvas 2D Context Mocking" section actually lives there, not in `canvas-2d.md`):

- **"Canvas 2D Context Mocking"** — both traps documented up front (unwrapped host method → bare `Illegal invocation` surfacing in the production module's RAF callback; `get` trap serves the wrapper function so assertions through the proxy/canvas read a function). Example rewritten as `makeRecordingCtx` returning `{ proxy, rec }`: audited `METHODS` list wrapped with record + `apply` on the real ctx, `set` trap for properties, `bind(target)` passthrough for un-audited methods, assertions read `rec`. Added the full-repaint cumulative-log rule (300 + 301 + 300 = 901) as a key pattern.
- **"In-Browser Runner"** — disjunction bullet added after the diagnostic-failure bullet: "mocha.run() never reached" also covers a test page missing its `load → mocha.run()` listener; persistent-identical signal is the telling symptom; one-page Playwright probe (`pageerror` + manual `mocha.run()`) is the disambiguation step.
- **"Tolerance Precision in Positioning Tests"** — dyadic-input rule added: strict-equality position assertions need binary-exact fractions (75/300 → `0.75`; `(90/300)·3 === 0.9` is false in float64); plan-pinned contract values like 50 % → `1.5` are dyadic and must stay exact.
