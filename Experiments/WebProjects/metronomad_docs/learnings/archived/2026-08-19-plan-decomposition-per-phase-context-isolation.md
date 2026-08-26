# Plan Decomposition: Isolate Per-Phase Context to Stop Agent Overthinking

**Date:** 2026-08-19
**Context:** Metronomad v1 implementation plan had grown to 555 lines / 50 KB as a single file. Working Phase 6 meant loading all 8 phases, every behavior table, and all design decisions — the agent couldn't tell what was relevant to the current task and overthought. Split the plan into `_agent_docs/plans/2026-08-17-metronomad-v1/` (index + context + behavior-specs + 8 phase files) and archived the original.

## What Worked

- **Three-tier split mapped cleanly onto the failure mode.** *Where are we* → `index.md` (overview, scope, phase map with status). *Why is the plan shaped this way* → `context.md` (design decisions, interfaces, testing strategy, known behaviors, references). *What do I do next* → `phase-N-*.md` (30–78 lines each).
- **"Context to load" lists are the anti-overthinking mechanism.** Each phase file names exactly which sections of `context.md` / `behavior-specs.md` and which skill references it needs. Explicit scope-of-attention beats an agent inferring relevance from a 50 KB file.
- **Inline the scenarios a phase owns; reference by ID what it consumes.** ID-only cross-references (`P-10…P-14`) forced file-hunting and re-reading. Inlining made each phase file a complete work order, while depends-on contracts (Phase 6 → engine's `getBeatGrid` P-10/P-12) stay as references — they're another phase's contract, not this phase's work.
- **One canonical copy of each table** (`behavior-specs.md`), with phase-file copies labeled "canonical copy in behavior-specs.md §X" — locality without drift.
- **Phase map with status in `index.md`** made "we are on Phase 6" durable across sessions. The original plan had no progress state at all — it lived only in conversation.
- **Archive with pointer, don't delete.** Original moved to `plans/archive/` with a prepended "superseded — do not work from it" header: history preserved, no second live source of truth.

## What Didn't Work / Gaps

- **No integrity verification step in the process.** The split was verified by eye + line counts. A mechanical check would guard against silent loss: every scenario/decision/KB ID in the original appears in exactly one canonical table, and every `D#/KB#/T#/…` reference in the new files resolves.
- **Decomposition exposed an ownership ambiguity in the original:** V-05 (`onFileDropped`) was claimed by both Phase 3 ("Vue wiring … V-05") and Phase 5 ("real handlers V-01…V-07"). Fixed softly (inlined only in Phase 3) but phase files should own scenario IDs **disjointly** — the decompose process should detect and surface overlaps.
- **Context granularity is a judgment call.** All stable detail went into one `context.md`; a much larger plan may need per-concern files (decisions.md, interfaces.md). Unclear until it hurts.
- **The threshold for splitting is undefined.** This plan crossed it clearly (555 lines, 8 phases, heavy cross-referencing) but nothing in the current `writing-plans` skill says when a plan should stay single-file vs. split.

## The Rule (for future plans)

1. **Threshold:** plan > ~200 lines **or** > 5 phases **or** > ~15 KB → decompose into a directory instead of a file.
2. **Layout:** `index.md` (navigation + phase map with status) · `context.md` (stable whole-plan detail) · `behavior-specs.md` if BDD (canonical scenario tables) · `phase-N-*.md` each.
3. **Phase-file template:** `Depends on` / `Context to load` (explicit reading list) / `Overview` / `Changes Required` / inlined owned scenarios / `Success Criteria`.
4. **Ownership:** each scenario ID is inlined in exactly one phase file; cross-phase dependencies are ID references.
5. **Integrity check after any split:** ID coverage (no ID lost) + reference resolution (no dangling D#/KB#/section pointers) + scenario-ownership disjointness.
6. **Working convention for agents:** when a plan directory exists, work from the current phase file + its Context to load list only; mark the phase complete in the index's phase map when done.
7. **Archive the original** with a "superseded" pointer header.

## Cost / Benefit

One session to split (mechanical, ~10 files); every subsequent phase session starts with ~100 lines of working context instead of 555, and the "what's relevant to this phase?" question no longer exists.

## Next Steps

- [ ] Update `writing-plans` skill with a "Plan Decomposition" section + phase-file template (items 1–3, 7 above)
- [ ] Consider a new `decomposing-plans` skill codifying the transform + integrity check (items 5–6)
- [ ] Fix the V-05 overlap in `phase-5-ui-integration.md` (make Phase 5's list V-01…V-04, V-06, V-07 with a "V-05 delivered in Phase 3" note)
- [ ] Add the working convention (item 6) to a project AGENTS.md when plan directories are in active use

---
**Status:** Open (skill changes pending sign-off)
**Related:** `_agent_docs/plans/2026-08-17-metronomad-v1/index.md` (the decomposed plan), `plans/archive/2026-08-17-metronomad-v1-implementation-plan.md` (original)
