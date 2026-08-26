# Phase 3 — N-3: Delete the dead object-URL lifecycle from fileLoader

**Source:** review N-3 · `fileLoader.js:56-91` — the object URL is created, tracked, and revoked but **never consumed** (decode uses `file.arrayBuffer()`; nothing in `App/` reads `result.objectUrl` — grep-verified at planning).

## Change

- Delete `currentUrl` tracking, `URL.createObjectURL`/`revokeObjectURL` calls, and `objectUrl` from the `loadFile` result and the JSDoc contract.
- Collapse the contract to **"exactly one decoded buffer live"** (the property that actually matters): `currentBuffer` + `release()` stay.
- `extractExt`: remove from the returned object (keep the internal function). Disposition at scoping: **private** — it has no production caller outside the loader; behavior stays pinned through the codec message path.
- Update `FileLoaderTest.html`: F-02/F-03/F-04/F-05/F-06 lose their URL assertions (zero-`createObjectURL` becomes the F-03 assertion); F-09 re-pins extension behavior via the codec message; the F-05 (release) test becomes "release() drops the buffer reference / is idempotent" (observable: a second loadFile after release still succeeds; the loader no longer exposes the URL surface).
- App side needs no change (`onFileDropped` never used `objectUrl`).

## Scenarios (inline; canonical in `behavior-specs.md` §7)

- **R-N3.1** — `loadFile` resolves `{ ok, buffer, duration, fileName }` with **no `objectUrl`**; `URL.createObjectURL` called zero times on every path.
- **R-N3.2** — `loader.extractExt` is `undefined`; `'archive.tar.gz'` → codec message ".gz files"; extensionless → unrecognized-type message (F-07 shape).

## Success criteria

- [ ] R-N3.1/R-N3.2 RED first, then green.
- [ ] No other file references `objectUrl` (grep).
- [ ] Both suites green at the item commit.

Status: ✅ done (2026-08-22)
