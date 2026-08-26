# State that is supposed to SURVIVE a trigger is a platform invariant — and negative E2E rows need bounded in-page watchers

**Date:** 2026-08-25
**Context:** Metronomad CR 001 Phase 6 (tempo-suggestion integration). Two plan-pinned E2E rows were wrong in ways no failing test revealed: E2E-4.4's "focused mid-draft survives the file drop" (unreachable — see below), and the negative rows E2E-4.3/4.4's natural assertion shape ("no hint ever appears"), which a node-side poll would *always* pass. A third, quieter trap: filling in the Phase-4 no-op tempo task silently broke the pinned flush counts in **Phase 4's** tests.

## 1. Focus and input drafts do NOT survive load-type triggers (new platform invariant)

The plan's E2E-4.4 said: focus `#bpmInput`, type `"9"`, drop the file, and on detection resolving the field still shows the user's draft. In-page focus tracing (`focusin`/`focusout` + element-node identity via MutationObserver) showed a live mid-draft **never reaches detection time**:

1. **A drop moves focus** — native drop focus semantics; synthetic `DragEvent`s included. The focused field is already blurred by the time the load starts.
2. **Even a focus-preserving load blurs the field** — decoding flips `isReady`, and `#bpmInput` is `:disabled="!isReady"`; a focused element that becomes `disabled` loses focus (blur fires), and the app's commit-on-blur law (RD-1, `@blur="commitBpmEntry"`) then **commits the very draft** the W-16 gate protects.

So "draft survives the trigger" violated two platform/app invariants at once. The row was re-pinned in place to the reachable literal-step behavior (blur-commit 9→30, flag reset on load, prefill lands *visibly*); the no-clobber guarantee for a genuinely live mid-draft stays pinned at the P0 *unit* level (TD-U1.4/1.5), where focus and draft state are directly settable.

**Rule:** at test-construction time, run "state that must survive the trigger" through the same invariant checklist as the sibling platform-invariants learning (`2026-08-25-plan-pinned-ui-details-must-survive-platform-invariants.md`), now extended with the focus surface:
- Does the *trigger itself* move focus? (drops: yes; clicks: yes; keyboard: no.)
- Does anything the trigger causes flip `:disabled`/remove the focused element? (disabled-while-focused → blur; removed-from-DOM → blur.)
- Does the app have a commit-on-blur law that would then fire on the draft you're trying to preserve?
If any answer is yes, the "survives" step is unreachable — trace focus in-page before writing the assertion, and re-pin the row to the reachable behavior (with the protected behavior re-homed to a unit row if one exists).

## 2. Negative and repeat-action E2E assertions

Three traps, all from the Phase-6 E2E rows:

- **Repeat actions can't be signalled by already-satisfied state hooks.** On a same-file re-drop (E2E-4.2), `body[data-state]="ready"` and `canvas[data-loaded]="true"` were *already true from the first load* — waiting on them proves nothing about the second load. The usable signals are an actual write that must **change** (field value 140→120) or an ok-branch write that must **clear** (`tempoSuggestion` null→set). **Rule:** for the Nth repetition of an action, pick an assertion target whose value *transitions on that specific repetition*.
- **Absence can't be node-poll-asserted.** "The hint never appears" holds from t=0 — a node-side `expect`/poll passes even if detection later misfires, because the poll only samples *after* the wait and never observes the resolution window. The row needs a **bounded in-page watcher** (MutationObserver + a 5 ms sweep for a window that *dwarfs* the effect's budget — here 500 ms vs the <50 ms detection budget) that records if the element ever appeared, installed **before** the trigger, with an initial `check()` covering effects that finished before installation.
- **Live regions hold residue; name it.** After a successful load the `role="status"` live region holds `"<file> loaded"`, not `""`. "No tempo announcement" means "**still** the load announcement" — two of the first RED drafts asserted `""` and were test bugs, not app bugs. **Rule:** a negative live-region assertion names the expected residual content, never empty string.

## 3. Filling a no-op in a pinned multi-task hook changes the pinned-yield queue shape

The Phase-4 `_schedulePostLoadTasks` no-op tempo task never called `setTimeout(0)`. When Phase 6 gave it its real body (a yield per task), Phase 4's **own** WF-I1.2/1.4 tests — which pinned "two flushes are enough" — broke, because the queue now needs one more flush. The breakage surfaced in *another phase's* rows, not the phase that changed the code. **Rule:** when a pinned hook's task count or per-task yield count changes, re-audit every flush-driven test in the suite (grep for the flush helper) before declaring the phase green; a shared test-infrastructure pin (like a flush count) is a derived constant, not a behavior pin.

## Why it matters

All three failures are the same shape: the test as written *passes or fails for the wrong reason*. An unreachable "survives" step produces a test that exercises a different (still valuable, but different) contract than the plan claimed — discoverable only by tracing the trigger's side effects. A node-polled absence assertion is vacuous. A stale flush count fails a test that "has nothing to do with your change," burning debug time on the wrong module. Each was caught in the same session by asking "would this test still pass/fail if the app did the opposite of what I think?" — the cheapest form of test validation.

## Skill mapping (landed 2026-08-25)

- [x] `building-web-apps` → `references/testing-e2e.md`: (1) "Plan-Pinned UI Details vs. Platform Invariants" checklist gains the **focus/input-draft survival** surface (drop focus semantics, `:disabled`-while-focused blur, commit-on-blur interaction); (2) new section "**Negative and Repeat-Action Assertions**" (transition-pick for repeated actions, bounded in-page absence watchers, live-region residue naming).
- [x] Cross-referenced: `2026-08-25-plan-pinned-ui-details-must-survive-platform-invariants.md` (sibling checklist), `2026-08-22-refactor-contract-shape-goes-stale.md` (archived; rule 3 is its test-infrastructure variant), `2026-08-24-in-page-poll-loggers-cannot-order-sub-period-events.md` (why the watcher is in-page).
