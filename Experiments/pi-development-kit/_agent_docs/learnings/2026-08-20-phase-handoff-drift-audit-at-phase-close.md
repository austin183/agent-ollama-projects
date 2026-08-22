# Phase Handoff Drift: Pin Ownership and Audit the Next Phase's Context Before Closing

**Date:** 2026-08-20
**Context:** Metronomad Phase 6 (Beat Dots, TDD). The session *started* with the exact overthinking the plan decomposition was designed to prevent — ~20 minutes re-deriving which module owns the beat-dot RAF loop (the engine's P-12 visual clock, built in Phase 4, or the app-level `createBeatDots` loop the Phase 6 interface describes). Per-phase context isolation was working (the agent loaded only the right files); the files themselves were inconsistent. The same audit at phase close then found two *plan* bugs that would have burned Phase 7's first test: the E2E-1.2 timing table said count-in 2 flips at t0+1.0 s, but the plan's own grid law (T-04/P-01: `songStart = t_p + (N+1)·beat`) gives **t0+1.5 s** — outside the ±0.3 s window, a guaranteed false RED — and E2E-1.2's "beat 1 then beat 2 (data-beat)" used one-based prose while the implemented hook is **zero-based** ("-1", "0", "1", …).

## Why isolation alone was not enough

The 2026-08-19 decomposition learning fixed *which* context an agent loads. It assumed the loaded context is coherent. Phase 6 disproved that assumption in three independent ways:

1. **Unpinned ownership.** Phase 4 exposed the engine's visual clock (`onFrame`/`startVisualClock`/`stopVisualClock`, P-12) as a public capability. D9 says "the RAF dot loop calls it every frame" without naming the owning module. The Phase 5 session summary's `next_steps` said *"integration points already in place: engine.onFrame callback param"* — priming a Phase 6 agent to wire the engine loop. But Phase 6's pinned interface (`createBeatDots` with its own `startVisualClock`/`stopAll`) and B-01's window-level RAF mock describe an *app-level* loop. Both readings were defensible from the plan text; only the interface + scenario mocks disambiguate, and the agent had to discover that on its own.
2. **Scenario prose vs. data model.** "Shows beat 1 then beat 2" (behavior-specs E2E-1.2) vs. `activeBeatIndex: -1, // 0–3 lit dot` (createMetronomadData, Phase 1). Neither document cross-referenced the other; KB-6 named the hook without its semantics.
3. **Arithmetic never checked against the plan's own worked examples.** The Phase 7 table's "+1.0 s / 4 s lifecycle" contradicts T-04, which sits in the *same plan*. The plan was authored without a recompute pass.
4. **History outside the load list.** The as-built decisions (app-level loop, zero-based hook) were recorded in the Phase 6 session summary — which neither Phase 7's nor Phase 8's "Context to load" named. The handoff point was precisely where information was lost.

## The Rule

1. **Pin ownership at authoring time.** Whenever two modules could plausibly own a behavior (engine vs. UI layer, scheduler vs. visualizer, factory vs. consumer), the interface section states in one sentence who owns it — and any earlier-phase capability the app does *not* use is labeled "tested capability, not used by the app" (exemplar: engine P-12 visual clock vs. `createBeatDots`).
2. **Recompute every worked-example constant before a phase is marked ready.** Each timing/count constant in a scenario table must derive from the plan's own unit-level worked examples (grid law, clamp tables). A 5-minute arithmetic pass caught the +1.0 s bug that would have consumed a Phase 7 session.
3. **Hook semantics belong in the KB entry, not the scenario prose.** Value range, base (zero/one), sentinel values, and who updates it — pinned once where every phase's context load already reaches (KB-6 now carries the `data-beat` contract).
4. **Handoff audit at phase close (standing step, closing agent).** Before flipping a phase to done: diff the *next* phase's "Context to load" + inlined scenario table against the as-built code. Fix plan inconsistencies in the plan (user-approved), and — when as-built diverges from the plan's literal text — add this phase's session summary to the next phase's "Context to load". Cost: one grep + one arithmetic pass. Value: the next session starts with zero re-derivation.
5. **Session-summary `next_steps` describe consumption, not existence.** "engine.onFrame callback param exists" misled; "createBeatDots owns the app-level RAF loop; the engine's onFrame is NOT wired by the app" informs. When handing a hook forward, state how the next phase's interface will use it (or explicitly not use it).

## What Worked (this transition)

- **The handoff audit itself** — 30 minutes at phase close, comparing Phase 7/8's context loads against as-built Phase 6, found both plan bugs and the ownership gap before a fresh session could hit them. It should become a standing rule (item 4).
- **Session-summary chain stayed complete** (one per phase, 1–6) and its `key_decisions` were detailed enough that the audit needed no archaeology.
- **TDD batching** held: 6 small RED→GREEN batches (1–4 tests each), one refactor pass; the suite caught a real refactor regression (`_cancelLoop` clobbering `_hiddenPaused` set by the hidden path) — the Critical rule worked as specified.
- **Browser-faithful RAF mock** (Map id→cb; cancel *removes*) — the recording-only variant silently broke B-02; reusing the shape already in PlaybackEngineTest's in-page fakes avoided re-deriving it.

## Cost / Benefit

One audit session (~30 min) + four small plan edits, vs. a Phase 7 session that would have opened with a false RED (timing), a second false RED (data-beat base), and a third overthinking episode (which loop owns the dots) — i.e., most of a session re-derived from artifacts that were all *correct individually* and wrong in combination.

## Next Steps

- [x] `writing-plans` skill (pi-development-kit): add "Phase Handoff Consistency" section — ownership pinning (rule 1), worked-example recompute pass (rule 2), hook semantics in KB (rule 3), handoff audit at close (rule 4). Complements the existing decomposition rules from the 2026-08-19 learning. *(Done 2026-08-20: new `references/phase-handoff.md` incl. rule 5; SKILL.md section + checklist; decompose-plan working-convention cross-link.)*
- [x] `build-tdd` agent definition: one line for the Red phase — if the pinned interface appears to contradict an earlier phase's implementation, do not silently re-derive; pick the reading the pinned interface supports, and flag the contradiction in the session summary for plan correction. *(Done 2026-08-20: RED bullet + `next_steps` consumption discipline under What You Must Track.)*
- [x] `capturing-learnings` skill: documentation format names `agent_docs/thoughts/`, but project convention is `_agent_docs/learnings/` (dated rule-files, older ones archived) — update per the skill's own staleness note. *(Done 2026-08-20.)*
- [ ] Phase 7/8 context loads already corrected (2026-08-20); no further action until Phase 7's own close, when its handoff audit runs against Phase 8.

---
**Status:** In Progress (skill changes applied 2026-08-20; open item: Phase 7's own close handoff audit)
**Related:** `2026-08-19-plan-decomposition-per-phase-context-isolation.md` (predecessor — isolation; this is consistency), `_agent_docs/sessions/2026-08-20-001-build-tdd-phase6-beat-dots-progress-tdd.json`, `_agent_docs/plans/2026-08-17-metronomad-v1/{phase-7-e2e-suite.md, phase-8-docs-acceptance.md, context.md, behavior-specs.md}` (corrected)
