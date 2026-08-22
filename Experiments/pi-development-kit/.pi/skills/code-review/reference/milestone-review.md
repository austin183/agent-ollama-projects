# End-of-Milestone Full Codebase Review

Use this when a milestone/phase set has shipped and the whole implementation (not a diff) needs review — the standing format for end-of-milestone reviews. Day-to-day PR/diff review stays with the main SKILL.md checklist and the `diff-review` agent.

## Six Passes

One focused pass per area, over the full source plus its tests and docs:

| # | Pass | Focus |
|---|------|-------|
| 1 | Architecture & SOLID | Module boundaries, data flow, coupling, DIP consistency, single-source-of-truth |
| 2 | Core correctness | The domain's hardest subsystem: state machines, concurrency/interleaving, resource lifecycle, platform edge cases |
| 3 | App layer + interface | State consistency, lifecycle, a11y, template/UI binding behavior |
| 4 | Test suite | Coverage matrix vs the plan's behavior-specs, determinism, flake risk, mock fidelity |
| 5 | Spec compliance & docs | Requirement-by-requirement vs the spec, wording audit, AGENTS.md/context accuracy |
| 6 | World review | Real-world systems/UX: cross-platform, offline, other browsers, real user workflows |

Plus **direct verification** by the reviewing agent: re-run the full test suites and live-repro the top findings where feasible. Record the baseline (suite results, environment) at the top of the review.

## Output Contract (what makes a review plan-ready)

The `writing-plans` skill's light planning pass (`references/review-to-plan.md`) can convert this review into a plan in one session **only if** the review carries this shape:

Per finding (numbered `C-n` critical / `I-n` important / `N-n` nit, each with a one-line title):

- **Location:** `file:line` — verified, not recalled
- **What happens:** the observable defect or design problem
- **Why the tests are green:** the exact test gap that let it slip (which test exists, why it doesn't catch this)
- **Fix:** a concrete fix contract, implementable as written (plus the spec/KB updates it implies)

Plus, at the end:

- **Coverage/compliance matrices** (tests vs behavior-specs; requirements vs spec)
- **What's well-designed** — so the fix plan doesn't churn sound architecture
- **Tiered action plan** — 1) shippable gate (small, bounded sessions), 2) design hygiene, 3) nice-to-have backlog in suggested order

A review without named tests or locations produces a plan that needs a full planning session — the exact extra cost the contract exists to avoid.

## Worked Exemplar

The exercise that produced this reference: a six-pass review of a shipped v1 (1 CRITICAL, 9 IMPORTANT, 33 nits — every finding carried the four fields above) was converted one session later by the light planning pass (`writing-plans` skill, `references/review-to-plan.md`) into a three-phase plan directory. That review→plan round trip is the end-to-end shape this contract exists to make cheap.
