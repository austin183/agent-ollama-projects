# Phase Handoff Consistency

Per-phase decomposition (`decompose-plan.md`) fixes *which* context a phase session loads. This reference covers the other half: keeping the loaded context **coherent** across phase boundaries. Drift observed in the field (2026-08-20, a Phase 6→7 handoff): unpinned ownership between modules, scenario prose contradicting the data model, worked-example constants never rechecked against the plan's own arithmetic, and handoff history no phase's "Context to load" named — each artifact correct individually, wrong in combination, costing the next session re-derivation and false REDs.

## The Rules

### 1. Pin ownership at authoring time

Whenever two modules could plausibly own a behavior (engine vs. UI layer, scheduler vs. visualizer, factory vs. consumer), the interface section states in one sentence who owns it. Any earlier-phase capability the app does *not* use is labeled **"tested capability, not used by the app"** so a later session doesn't wire it in.

- ❌ "The RAF dot loop calls `engine.onFrame` every frame." (owner unnamed; both readings defensible)
- ✅ "The app-level `createBeatDots` factory owns the RAF loop. The engine's visual clock (P-12) is a tested capability, not used by the app."

### 2. Recompute every worked-example constant before a phase is ready

Each timing/count constant in a scenario table must derive from the plan's own unit-level worked examples (grid law, clamp tables). Run a 5-minute arithmetic pass over the phase's inlined tables before marking it ready. A table constant that contradicts a worked example in the *same plan* is a plan bug, not an implementation bug — fix the plan.

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

## Phase-Close Checklist

Run at every phase close, before marking it done:

- [ ] Ownership of every behavior this phase exposed is pinned in the plan (rule 1)
- [ ] Worked-example recompute pass over this and the next phase's scenario tables (rule 2)
- [ ] Every data hook referenced by the next phase has its semantics in the context entry (rule 3)
- [ ] Handoff audit: next phase's context load + inlined tables diffed against as-built (rule 4)
- [ ] Session summary `next_steps` state consumption, not existence (rule 5)
