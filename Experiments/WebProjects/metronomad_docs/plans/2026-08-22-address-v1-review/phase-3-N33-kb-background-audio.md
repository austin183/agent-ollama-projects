# Phase 3 — N-33: KB-13 — backgrounded tab keeps audio playing (docs only)

**Source:** review N-33 — backgrounding the tab / mobile screen keeps audio playing (standard Web Audio; arguably what a metronome should do).

## Change (docs only)

Record **KB-13** in the v1 `context.md`: intended behavior — do not "fix" (e.g. pause on `visibilitychange`). Scoping decision: kept **separate** from KB-11 — KB-11 is a latent defect note (throttled scheduler compresses the count-in), KB-13 pins intended behavior (audio continues; the visualizer is the only thing that pauses, and it self-heals via D9).

## Success criteria

- [ ] KB-13 present in the v1 `context.md`. No code changes.

Status: ✅ done (2026-08-22)
