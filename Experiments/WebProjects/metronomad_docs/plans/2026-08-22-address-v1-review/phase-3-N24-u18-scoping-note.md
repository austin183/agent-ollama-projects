# Phase 3 — N-24: Document the U-18 scoping (docs only)

**Source:** review N-24 — U-18 has no E2E variant (the contract suggested `ctx.suspend()` in `page.evaluate`); P-11 + V-07 are unit-adequate.

## Change (docs only)

In the v1 `behavior-specs.md` U-18 row, append the scoping note: **unit-adequate** — the self-stop + announcement contract is pinned by P-11 (engine watch) + V-07/R-I4 (app mapping); the `ctx.suspend()` E2E variant is **dropped** due to headless Chromium suspend quirks (autoplay-policy headless contexts do not reliably enter `suspended` on demand).

## Success criteria

- [ ] Note present on the v1 U-18 row. No code or test changes.

Status: ✅ done (2026-08-22)
