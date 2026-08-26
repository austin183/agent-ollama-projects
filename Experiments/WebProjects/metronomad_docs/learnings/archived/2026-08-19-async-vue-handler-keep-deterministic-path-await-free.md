# Async Vue Handlers: Keep the Deterministic Path Await-Free

**Date:** 2026-08-19
**Context:** Metronomad Phase 5 — `onPlayToggle` needed to be `async` for one branch only: U-19 (a suspended AudioContext must resume — or fail friendly after `SCHEDULER.RESUME_TIMEOUT_MS` — before the sequence starts). The other branches (stop toggle, ready + running context) had no reason to be async.

## The Design Rule

An `async` function runs its body **synchronously up to the first `await` it actually reaches**. So if the common path never reaches an `await`, the handler behaves exactly like a sync function — and mock-VM tests can assert on it synchronously:

```javascript
async onPlayToggle() {
    if (this.isParamLocked) {          // stop path — no await, returns sync
        this._engine.stop();
        return;
    }
    if (!this.isReady) return;         // no await
    const ctx = this._clock;
    if (ctx && ctx.state !== 'running') {
        const resumed = await this._resumeWithTimeout(ctx);  // the ONLY await
        if (!resumed) { this.errorMessage = '…'; return; }
    }
    this._engine.startSequence(this._sequenceParams());      // reached sync when ctx is running
}
```

The V-01 tests call `vm.onPlayToggle()` with **no `await`** and assert `engine.calls` immediately — valid because with `_clock` undefined or `state === 'running'`, no `await` is reached.

## Why It Matters

- **Testability:** the deterministic scenarios (the bulk of the contract) stay synchronous — fast, and free of async-suite timing hazards (see `2026-08-18-mocha-runner-async-suite-undercount.md`). Only the genuinely async branch (never-settling resume → 750 ms real timer) is tested with `await`.
- **Behavior:** Vue click handlers don't care about the returned promise; keeping the fast path sync means no microtask delay between the click and the engine call — relevant for the "Stop within 50 ms" (U-04) class of guarantees.

## The Anti-Pattern

Placing an `await` *before* the guard checks (e.g., `const ctx = await maybeResume()` unconditionally) makes the whole handler async-in-practice: every mock-VM test must `await`, and the stop path gets an unnecessary microtask hop. Structure the `await` inside the branch that needs it.

## Generalization

Applies to any async handler/factory method whose async-ness is branch-local: push the `await` as deep into the branch as possible and keep the happy path await-free, so the synchronous contract surface stays synchronously testable.
