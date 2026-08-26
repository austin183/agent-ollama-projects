# Phase 3 — N-27: _refocusPlayStopButton disabled-branch test

**Source:** review N-27 — the "never focus a disabled button" branch is untested (the mock button is always `disabled: false`).

## Change (test only)

`UiHandlersTest.html`: a V-01-adjacent test — build the VM locked (e.g. `appState: 'playing'`), replace `vm.$refs.playStopBtn` with a fake button whose `disabled: true` (and a `focus()` that sets `focused`), call `onPlayToggle` (stop path) → `engine.stop()` called but `focused === false`.

## Scenarios (inline; canonical in `behavior-specs.md` §7)

- **R-N27.1** — locked + disabled toggle → stop happens, focus does not.

## Success criteria

- [ ] R-N27.1 green at the item commit (no production change — it pins the existing guard).

Status: ✅ done (2026-08-22)
