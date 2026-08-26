# Phase 3 — N-14: Post-await guard in the resume path

**Source:** review N-14 · `createMetronomadMethods.js:186-207` — unmount inside the resume await (up to 750 ms) leaves `this._engine` null after the `await` → unhandled TypeError at `this._engine.startSequence(...)`.

## Change

In `onPlayToggle`, immediately after `const resumed = await this._resumeWithTimeout(ctx);`:

```js
if (!this._engine) return; // unmounted during the resume await (N-14)
```

before the `!resumed` error branch (an unmounted VM must not be written to either).

## Scenarios (inline; canonical in `behavior-specs.md` §7)

- **R-N14.1** — suspended context, resume promise pending; null `_engine` before it settles; `await onPlayToggle()` → no `startSequence`, no `errorMessage`, no throw.

## Success criteria

- [ ] R-N14.1 RED first (mock-VM with a controllable resume promise), then green.
- [ ] U-19 suite still green; both suites green at the item commit.

Status: ✅ done (2026-08-22)
