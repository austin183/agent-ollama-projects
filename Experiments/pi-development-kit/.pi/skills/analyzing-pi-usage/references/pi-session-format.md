# Pi Session File Format (JSONL)

Reference for parsing pi agent session files. Verified against live data from
the pi-coding-agent distribution (`docs/session-format.md` in the package is
the upstream source of truth; this document covers the analytics-relevant
details and gotchas).

## Location & Layout

Sessions are stored as JSON Lines under:

```
~/.pi/agent/sessions/<encoded-cwd>/<timestamp>_<session-uuid>.jsonl
```

- **Encoded directory name**: the session's working directory with every `/`
  replaced by `-`, wrapped in `--…--`, e.g.
  `/Users/austin/workspace/austin183.github.io` →
  `--Users-austin-workspace-austin183.github.io--`.
- **The encoded path uses the real path** (symlinks resolved). On macOS that
  means `/tmp` sessions land under `--private-tmp-…--`. When filtering by
  project, resolve both sides (`os.path.realpath`) before matching.
- The sessions root can be overridden with the `PI_SESSIONS_ROOT` env var or
  the `--sessions-root` flag on the skill's scripts.
- One file = one session. **Forked sessions are separate files that replay
  the parent's history** (see gotchas).

## Entry Types

Each line is one JSON object with a `type` field. The first line is always the
session header.

### `session` (header, line 1)

```json
{"type":"session","version":3,"id":"01a00ba3-…","timestamp":"2026-08-16T17:34:34.696Z","cwd":"/Users/austin/workspace/austin183.github.io"}
```

Forks additionally carry `"parentSession": "<source session uuid>"`.

### `message`

```json
{"id":"8ced584","parentId":"1ef65b03","type":"message","timestamp":"…","message":{ … }}
```

Entries form a tree via `parentId` (a normal linear conversation is a chain;
branches and retracted turns make it a tree). The **session header id is the
only entry whose id is a full UUID**; all other entry ids are **8 hex chars**.

`message.role` variants:

- **`user`** — `content` is a string or a list of content blocks
  (`[{"type":"text","text":"…"}, …]`). The pi kit's role convention puts a
  `Role: <name>` marker on the first line of role-switch user messages;
  analytics attributes a turn to the nearest preceding user message's marker
  (default `main`).
- **`assistant`** — one entry per LLM turn:

  ```json
  {"role":"assistant","model":"qwen/qwen3.8-27b","provider":"lmstudio",
   "content":[ … ],
   "usage":{"input":1234,"output":56,"cacheRead":0,"cacheWrite":0,
            "reasoning":10,"totalTokens":1280,
            "cost":{"input":0.0,"output":0.0,"cacheRead":0.0,"cacheWrite":0.0,"total":0.0}}}
  ```

  `usage.cost` is an **object** on main-session turns. Providers that support
  prompt caching (Anthropic/OpenAI/Google) populate `cacheRead`/`cacheWrite`;
  **LM Studio (and similar) report 0** — analytics then falls back to the
  simulated LAG-delta estimate.
- **`toolResult`** — `{"role":"toolResult","toolName":"…","toolCallId":"…",
  "details":{…},"usage":null}`. The top-level `usage` is normally null;
  per-tool data lives in `details`.

  The **`subagent` tool** is the attribution source for delegated work:

  ```json
  {"role":"toolResult","toolName":"subagent","details":{"results":[
     {"agent":"reviewer","model":"anthropic/claude-…",
      "usage":{"input":100000,"output":2000,"cacheRead":50000,"cacheWrite":0,
               "cost":0.123,"contextTokens":102000,"turns":7},
      "stopReason":"end_turn","messages":[ …subagent transcript… ]}
  ]}}
  ```

  - `usage.cost` is a **flat number** on subagent results (unlike assistant
    turns).
  - A subagent that delegated further has nested runs under
    `messages[].details.results[]` (where `messages[].role == "toolResult"`);
    nested usage is **not** included in the parent result's `usage`, so
    recurse to attribute every run.

### `model_change`

`{"type":"model_change","modelId":"…","provider":"…","timestamp":"…"}` —
used to attribute compaction usage to the active model.

### `compaction`

`{"type":"compaction","timestamp":"…","usage":{…}}` — the context-compaction
summary generation is a single LLM call with its own usage (same shape as an
assistant turn). Count it as its own event, not as a turn in the session's
turn sequence (it breaks the LAG-delta cache model).

### `session_info`

`{"type":"session_info","name":"…"}` — the latest one is the session's
display name (used as the top-sessions title).

### Others

`thinking_level_change`, `label`, `custom`, branch/abort entries, … — carry
no usage; ignore for token accounting (but do count them for dedup).

## Gotchas

1. **Forked sessions duplicate history.** A fork file re-emits the parent's
   entries (same entry ids) plus new ones, and its header has
   `parentSession`. Summing files naively double-counts. Dedup by entry id
   with *first file wins*, processing files in header-timestamp order
   (originals always predate their forks).
2. **`input` includes cached context.** A 100K-context session re-sends most
   of it every turn, so raw input totals are dominated by repeats. Use
   measured `cacheRead` where present; otherwise the LAG-delta fallback:
   sort a session's assistant turns by timestamp and
   `uncached[n] = max(input[n] - input[n-1], 0)` (first turn keeps its full
   input). This is a model, not a measurement — label it simulated.
3. **Model IDs are recorded verbatim, and the spelling varies by context.**
   Main-session turns record the settings-form ID (e.g.
   `qwen/qwen3.8-27b` with a separate `provider` field), while subagent
   results record the provider-qualified form (`lmstudio/qwen/qwen3.8-27b`).
   The same physical model can therefore appear as two rows in by-model
   tables. Pricing normalizes this (`pricing_model_id()` strips the leading
   `lmstudio/` before the rate-table lookup); display is left verbatim.
4. **Timestamps are ISO-8601 UTC** (`…Z`). Analytics buckets by UTC day
   (`timestamp[:10]`).
5. **Malformed lines happen** (interrupted writes). Skip and count them;
   never fatal.
6. **Project matching**: sessions record `cwd` in the header — substring
   match with realpath resolution (gotcha in the layout section).
7. **Live sessions grow.** An in-progress session appends to its file; totals
   taken at different times legitimately differ.
