# Phase 3: File Loading (P0)

**Depends on:** Phase 1 (template, app shell), Phase 2 (timeFormat for duration display).

**Context to load:**
- `context.md` → Design Decisions D3 (30-min guard), D8 (app states / non-blocking errors); Known Behaviors KB-2, KB-3, KB-7; File Layout & Module Interfaces (howlerSetup / codecSupport / fileLoader interfaces); Research Pitfalls 1 & 2
- Skill: `references/testing-unit.md` (mock only untriggerable error paths), `references/memory-management.md` (object URL revocation)
- Fixture source for the happy-path MP3: base64 in `_agent_docs/research/howler-research-test.html`

**TDD workflow:** start with 2–3 P0 scenarios (failing test → minimal code → run), then continue in small batches — don't write the full suite before the first green run.

## Overview

Drop/browse → decode → Ready, with all error paths and the memory lifecycle.

## Changes Required

- `MyESModules/Audio/{howlerSetup,codecSupport}.js` (H-01, H-02); `MyESModules/File/fileLoader.js` (F-01…F-09).
- Vue wiring: drop/browse handlers, "Decoding [name]…" state, Error overlay (U-14…U-16, U-20, V-05), filename truncation (U-21).
- `MyComponents/FileLoaderTest.html` — real `File` objects from base64 for the happy path; spy File for the codec-skip path; mocked `decodeAudioData` rejection only for F-04 (mock only the untriggerable error path, per skill guidance); `window.Howler` stubbed for H-01.

## Scenarios owned by this phase (canonical copy in `behavior-specs.md`)

**FileLoader — `createFileLoader({ codecs, maxDurationSec = 1800 })`** (codec provider injected: `codecs.check(ext) → bool`)

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| F-01 | P0 | `codecs.check` spy | `loadFile(null)` | Resolves `{ ok: false, code: 'noFile' }` — never throws on null (null-input guard convention) |
| F-02 | P0 | `codecs.check('ogg') === false`, spy File | `loadFile(file)` with ext `'ogg'` | Resolves `{ ok: false, code: 'codec' }` **without calling** `file.arrayBuffer()` or `decodeAudioData` (spies) |
| F-03 | P0 | Valid 3 s MP3 File, real AudioContext | `loadFile(file)` | Resolves `{ ok: true, buffer (3.0 s), duration: 3.0, fileName, objectUrl }`; exactly one `URL.createObjectURL` call |
| F-04 | P0 | File whose decode rejects (`EncodingError` via mock) | `loadFile(brokenFile)` | Resolves `{ ok: false, code: 'decode' }`; no throw escapes; the object URL created during the attempt **is revoked** |
| F-05 | P0 | Two files loaded in sequence | `loadFile(a)` then `loadFile(b)` | `a`'s object URL revoked (spy), `a`'s buffer no longer referenced; only `b`'s URL live. All exit paths (success, codec, decode, tooLong) leave no live orphan URL |
| F-06 | P1 | Decoded `buffer.duration > maxDurationSec` | `loadFile(longFile)` | `{ ok: false, code: 'tooLong' }`; URL revoked; buffer not returned |
| F-07 | P1 | File named "track" (no extension) | `loadFile(file)` | `{ ok: false, code: 'codec' }` (unknown extension = not supported) |
| F-08 | P1 | `onStateChange` callback injected | `loadFile(...)` | Fires `decoding` (with fileName) before the await and `idle` after — on success **and** failure (try/finally shape) |
| F-09 | P2 | Various names | `extractExt('Song (final).mp3')` / `('archive.tar.gz')` / `('noext')` | `'mp3'` / `'gz'` / `''` |

**howlerSetup / codecSupport**

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| H-01 | P0 | Stubbed `window.Howler` (lazy-ctx behavior) | `initHowler()` | Returns `{ ctx, masterGain }` with non-null `ctx`, numeric `ctx.currentTime`, and **`Howler.autoSuspend === false`** after the call (Pitfall-1 guard); `Howler.autoUnlock` left `true` |
| H-02 | P1 | `Howler.codecs` stub | `isSupportedCodec('mp3')` / `isSupportedCodec('')` | `Howler.codecs('mp3')` result / `false` |

**User + handler behavior this phase delivers**

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| U-14 | P0 | No-file state | User drops `track.ogg` | In Chromium (supported): proceeds to decode. In Safari (unsupported; manual): Error "This browser can't play .ogg files", stays No-file (Play disabled), announced |
| U-15 | P0 | No-file state | User drops a corrupt/garbage `broken.mp3` | Error "Couldn't decode broken.mp3 — the file may be corrupted"; state remains No-file; Play disabled; announced; **no cryptic DOMException text shown** |
| U-16 | P1 | A file failed to decode (error showing) | User drops a valid `song.mp3` | Prior error cleared; new file loads normally to Ready |
| U-20 | P1 | Ready | User drops a 40-minute file | Decode completes, guard fires: error "Song too long — maximum length is 30 minutes"; state No-file; buffer discarded, URL revoked |
| U-21 | P2 | Ready, 34-character filename | Rendered | Name truncated with ellipsis; full name available via `title` tooltip |
| V-05 | P0 | File drop | `onFileDropped(file)` | Wraps `fileLoader.loadFile` in try/finally: `decoding` false on **all** paths; on `ok` → `ready` + live region "<name> loaded"; on failure → `errorMessage` set, `appState` unchanged (U-15/U-16) |

## Success Criteria

**Automated:**
- [ ] F-01…F-09, H-01, H-02 pass via `node scripts/run-tests.cjs`.
- [ ] No unrevokeable object URL on any exit path (F-05 spy assertions).

**Manual:**
- [ ] User drops a real mp3 → Ready + duration shown; a garbage file → friendly decode error, app usable; a >30-min file → too-long error; (Safari) an .ogg → friendly codec error.
