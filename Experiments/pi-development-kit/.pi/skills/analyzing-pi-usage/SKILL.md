---
name: analyzing-pi-usage
description: Analyze pi agent token usage, cost, prefix-cache behavior, subagent attribution, and git productivity from pi's JSONL session files. Use when asked about token/cost usage, usage trends, model or role breakdowns, cache savings, subagent runs, or to generate the consolidated LLM usage & value report for a project.
---

# Analyzing pi Usage

Analyze what the pi agent is spending (tokens, cost, cache) and what it's
producing (commits, lines, tests), sourced from pi's own session JSONL files
(`~/.pi/agent/sessions/**/*.jsonl`) plus `git log`.

## Quick Start

All scripts live in `script/` and are run with `python3` (bash wrappers
included). Run from any directory; `--project` takes a project path
(substring match against each session's `cwd`, symlink-resolved).

```bash
cd .pi/skills/analyzing-pi-usage/script

# High-level summary (default when no section flags)
./analytics.sh --project /path/to/project

# Last 7 days, by model and by role
./analytics.sh --week --project /path/to/project --models --roles

# Cache approximation + subagent attribution
./analytics.sh --project /path/to/project --cache --subagents

# Raw JSON (for further processing)
./analytics.sh --project /path/to/project --summary --models --json

# Consolidated HTML report (the "LLM Usage & Value Report")
python3 generate_report.py --project /path/to/project --output report.html
python3 generate_report.py --project /path/to/project --json --output report.json
```

### `analytics.sh` flags

| Flag | Meaning |
| --- | --- |
| `--project <path>` | Filter by project directory (substring match) |
| `--since / --until <YYYY-MM-DD>` | Inclusive date range (UTC days) |
| `--days N` / `--week` / `--month` / `--all` | Range shortcuts |
| `--summary` | Overview (default when no section flags given) |
| `--models` / `--roles` / `--model-roles` | Usage by model, by role, cross-tab (`--agents` / `--model-agents` are aliases) |
| `--timeseries` / `--weekly` / `--monthly` / `--projects` | Trends |
| `--top-sessions [N]` | Top N sessions (default 20) |
| `--impact` | File change impact: measured from `Pi-Session:` commit trailers where present, date-matched estimate otherwise |
| `--cache` | Prefix cache approximation (measured where providers report it, else simulated) |
| `--subagents` | Per-run subagent attribution (pi-only capability) |
| `--json` | Raw JSON output |
| `--sessions-root <path>` | Override `~/.pi/agent/sessions` |

## Key Concepts

- **Role** — the pi kit's role convention (`Role: <name>` marker in user
  messages; default `main`). Roles map to categories for charts:
  `main` + `build-*` → build, `*-review`/`diff-review` → review,
  `planner`/`plan-bdd` → plan, rest → other.
- **Effective (cache-adjusted) tokens** — `uncached input + output +
  reasoning`. Where pi reports real `cacheRead` the split is measured;
  otherwise (e.g. LM Studio) a per-session LAG-delta model estimates it and
  the report labels it simulated.
- **Subagent runs** — pi persists each `subagent` tool result (agent, model,
  turns, context size, cost, stop reason) inside the *parent* session file,
  including nested delegations. The report's "Subagent Runs" section
  attributes every delegated run.
- **Change attribution** — agent commits end with a `Pi-Session: <uuid>`
  trailer naming the session that made the changes (convention in the
  `build-quick-work` agent). The report joins trailers to loaded sessions —
  per-session commits/lines with role and title — and "sessions with
  changes" becomes a measurement; commits without a trailer keep the
  date-matched estimate. `analytics.py --impact` prints both figures.
- **Costs** — actual recorded cost where the provider reports it; otherwise a
  cloud-equivalent estimate from `script/model_pricing.py` (add local models
  there for accuracy; unknown models use fallback rates and are warned).
- **Session summaries** — human-curated JSON companions in
  `[docs directory]/sessions/` (see `references/session-summary.json`);
  joined into the report's productivity section when present.

## Workflows

### Usage questions ("how many tokens did X cost?")

1. Run `analytics.sh` with the narrowest useful section flags.
2. Quote effective (cache-adjusted) numbers, not raw, when comparing work
   done — raw input is dominated by context re-sends.
3. For subagent-heavy sessions, add `--subagents` to see where delegation
   went.

### Full report for a project

1. `python3 generate_report.py --project <path> --output <path>/report.html`
2. Open the HTML; sections: Summary Metrics (tokens, cost, cache hit rate,
   code impact, productivity), Charts, Detailed Data Tables (models, roles,
   cross-tab, cache, session summaries, subagent runs, top sessions, commit
   efficiency).
3. The footer states the data sources and which cache numbers are simulated.

### Keeping session summaries current

- After each session, write a summary to `[docs directory]/sessions/` from
  `references/session-summary.json` — filename `YYYY-MM-DD-XXX-<role>-<description>.json`
  (per the role agents' conventions; fill every template field).
- Validate with `bash script/validate_summaries.sh --root <project>` (add
  `--strict` in CI).

## Data Format

See `references/pi-session-format.md` for the JSONL entry types, the
subagent tool-result shape, fork dedup, and other parsing gotchas. The
parser is `script/pi_sessions.py`.

## Tests

```bash
cd .pi/skills/analyzing-pi-usage
python3 -m pytest tests/ -v
```

Tests use synthetic session fixtures built in-memory (no dependency on the
host's `~/.pi`), plus the real fixture files captured under `tests/fixtures/`
during port verification.
