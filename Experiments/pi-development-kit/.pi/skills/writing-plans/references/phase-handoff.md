# Phase Handoff Consistency

Per-phase decomposition (`decompose-plan.md`) fixes *which* context a phase session loads. This reference covers the other half: keeping the loaded context **coherent** across phase boundaries. Drift observed in the field (2026-08-20, a Phase 6→7 handoff): unpinned ownership between modules, scenario prose contradicting the data model, worked-example constants never rechecked against the plan's own arithmetic, Givens that never reach the boundary their Then names, and handoff history no phase's "Context to load" named — each artifact correct individually, wrong in combination, costing the next session re-derivation and false REDs.

## The Rules

### 1. Pin ownership at authoring time

Whenever two modules could plausibly own a behavior (engine vs. UI layer, scheduler vs. visualizer, factory vs. consumer), the interface section states in one sentence who owns it. Any earlier-phase capability the app does *not* use is labeled **"tested capability, not used by the app"** so a later session doesn't wire it in.

- ❌ "The RAF dot loop calls `engine.onFrame` every frame." (owner unnamed; both readings defensible)
- ✅ "The app-level `createBeatDots` factory owns the RAF loop. The engine's visual clock (P-12) is a tested capability, not used by the app."

### 2. Recompute worked-example constants, and verify Givens reach the boundary they name

Each timing/count constant in a scenario table must derive from the plan's own unit-level worked examples (grid law, clamp tables). Run a 5-minute arithmetic pass over the phase's inlined tables before marking it ready. A table constant that contradicts a worked example in the *same plan* is a plan bug, not an implementation bug — fix the plan.

The pass must also run **three Given checks per row**. Three incidents (2026-08-24: an index pinned past the buffer length; 2026-08-29: `clampOffset(2.5, 3.0, 2.96) → 2.9` — 2.5 is inside `[0, 2.96]` and clamps to itself; 2026-08-30: a re-sync statement between a hook's entry and its guarded read washed a fully well-formed Given's pre-state, making the Then structurally unreachable) were all invisible to the constant pass and were only caught when TDD transcribed the rows into tests:

1. **Range sanity** — Given values must be well-formed against the row's own dimensions: index vs length, sample count vs buffer size, time vs duration, bound vs the range it bounds.
2. **Given reachability** (boundary rows only — clamps, quantize-then-reclamp, off-by-one, overflow) — run the Given through the pinned law (by hand, or a 30-second `node -e` one-liner over the plan's reference implementation) and confirm it **crosses or reaches** the boundary the Then names. The row's prose annotation ("at the bound, not at duration") is not the check — the arithmetic is. A Given that lands inside the safe region silently downgrades an edge pin into a trivial in-range pin.
3. **Ordering reachability** (rows whose pre-set state is touched inside a byte-for-pinned code block) — a row's Given can be fully well-formed yet its Then still unreachable: a statement *between* the hook's entry and the guarded read (e.g. an ok-branch re-sync that rewrites the field unconditionally) can **wash the pre-set state before the guard ever reads it**. Replay the pinned block's statement order against the Given and confirm the Then is reachable from the *post-wash* state. This is a distinct subtype from checks 1–2 — the contradiction is **structural, not arithmetic**, so running the Given through the law cannot catch it.

The same disposition applies **at build time**: when a row-level RED contradicts the plan's own reference implementation, the row is the plan bug — fix it in place in both `behavior-specs.md` and the phase file, with a dated correction note, then re-run the integrity check and flag it in the session summary. Never bend the implementation toward a wrong Then: a wrong-Then row doesn't merely fail to pin its intent, it *actively pins broken behavior*, and TDD will faithfully build it. The mirror holds for check-3 conflicts: when a row's Then is unreachable from a **byte-for-pinned block's** statement order, the pinned code is the contract and the row is the stale artifact — never move the pinned statement to satisfy the row (the wash exists for a reason, e.g. clamping the offset to the *new* duration; moving it violates the pin). Rewrite the row to pin the *actual* post-wash behavior, with a `NOTE (plan-flag)` comment naming the supersession, and record the contradiction in the session summary for plan correction — plan docs are the planning session's turf, not TDD's.

### 3. Hook semantics belong in the KB entry, not the scenario prose

Value range, base (zero/one-based), sentinel values, and who updates a data hook are pinned **once** in the context / known-behavior entry that every phase's "Context to load" already reaches. Scenario rows can then reference the hook without redefining its base, so prose and data model can't drift independently.

### 4. Handoff audit at phase close (standing step, closing agent)

Before flipping a phase to done in `index.md`'s phase map:

- [ ] Diff the **next** phase's "Context to load" list against what actually exists (files, session summaries, as-built modules)
- [ ] Diff the next phase's inlined scenario tables against the as-built code
- [ ] Fix plan inconsistencies in the plan (user-approved)
- [ ] When as-built diverges from the plan's literal text, add this phase's session summary to the next phase's "Context to load"

Cost: one grep + one arithmetic pass. Value: the next session starts with zero re-derivation.

### 5. Session-summary `next_steps` describe consumption, not existence

"engine.onFrame callback param exists" misled a Phase 6 session; "`createBeatDots` owns the app-level RAF loop; the engine's `onFrame` is NOT wired by the app" informs. When handing a hook forward, state how the next phase's interface will use it — or explicitly that it won't.

### 6. Delegated phase briefs: resolve source anchors, pin the builder/closer boundary

When a phase is handed to a subagent, the task text is the brief's contract. Two briefing defects observed in the field (2026-08-30, CR 003 Phase 5) are both one-line fixes at task-authoring time:

1. **Full as-built paths for every source anchor.** Plan `References` / `context.md` anchors are bare `file:line` — the directory is intentionally omitted by convention. When the brief names a source file, the name must be the *full* as-built path, checked against the plan's Directory tree in the same pass the rest of the context is loaded. A bare name that resolves to the wrong directory anchors the subagent's doc claims to the wrong module (it may recover — but only a careful one, at the cost of a confused first read).
2. **Explicit builder/closer assignment for the close checklist.** The close checklist spans two agents: items the builder runs (full suites, integrity check, grep sanity) and items that must wait for the parent (phase-map status flip, timeline milestone, commit — all downstream of the parent's world-review step). Name which is which in the brief; the agent definition alone doesn't cover it. Unassigned, a subagent will either do the closer items (stepping on the review-order step — the status line should describe the *reviewed* delta) or refuse them and burn a turn. The pattern that worked: list closer items under an explicit "Do NOT do — the closing session handles it."

### 7. Cumulative count gates re-base in one pass, or not at all

A plan with per-phase cumulative test-count gates ("287 baseline → 311 after Phase 1; 339 after Phase 2; …") bakes one baseline number into every phase's arithmetic. A +4-rows fix that lands after authoring (2026-08-30, CR 004: the live baseline was 291, the live gate 315) silently poisons **every** downstream gate — and the current phase's own "re-verify the baseline at phase start" step will *catch* the discrepancy without fixing the plan, because the inherited gates in the later phases were derived from the stale number. When a phase-start re-verification finds the baseline moved:

1. **Re-base every remaining phase's count gate in the same pass** — not just the current one. A re-base that stops at the current phase ships the same stale arithmetic three phases later.
2. **Leave a dated note at the plan's baseline line** ("re-based 2026-08-30: 287 → 291 after `d7a7801` (+4 rows)") so the next reader sees the re-base instead of re-deriving it — or "confirming" the new number against the old arithmetic and "correcting" it back.

Re-verification is a **per-phase, per-gate** duty, not a one-time step: re-check **every** count-gate family (unit **and** E2E) against the live suite at **every** phase start — a gate re-based in an earlier phase still drifts in later ones (2026-08-30, CR 004: the unit gate re-based at Phase 1 start, the plan's 48-E2E gate stale into Phase 2 while the live baseline was 49). Cost of the re-check: one test run; cost of missing it: a false RED/GREEN gate or a miscounted session summary. And when authoring, phrase each phase's count gate as "re-baseline live at phase start (unit + E2E both)" — a fixed number is a point-in-time snapshot, and the live suite is the only truth.

## Phase-Close Checklist

Run at every phase close, before marking it done:

- [ ] Ownership of every behavior this phase exposed is pinned in the plan (rule 1)
- [ ] Worked-example recompute pass over this and the next phase's scenario tables (rule 2)
- [ ] Every data hook referenced by the next phase has its semantics in the context entry (rule 3)
- [ ] Handoff audit: next phase's context load + inlined tables diffed against as-built (rule 4)
- [ ] Session summary `next_steps` state consumption, not existence (rule 5)
- [ ] If the phase was delegated: the brief carried full as-built paths for every source anchor, and each close-checklist item was assigned to builder or closer (rule 6)
- [ ] If the re-verified baseline differs from the plan's: every remaining phase's cumulative count gate re-based + dated note at the baseline line (rule 7)
