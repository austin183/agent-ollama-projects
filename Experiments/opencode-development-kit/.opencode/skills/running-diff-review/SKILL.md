---
name: running-diff-review
description: Runs diff-review subagents with context from project learnings to reduce false positives. Use when invoking diff-review or diff-review-g31 subagents, before asking them to review code changes.
---

# Running Diff Review

Runs `diff-review` or `diff-review-g31` subagents with project learnings injected into the prompt, so they can distinguish intentional patterns from regressions.

## Workflow

Copy this checklist and track your progress:

```
Diff Review Progress:
- [ ] Step 1: Get the diff
- [ ] Step 2: Identify relevant learnings
- [ ] Step 3: Read top learnings
- [ ] Step 4: Invoke subagent with enriched prompt
- [ ] Step 5: Discuss findings with user
```

### Step 1: Get the diff

Run `git diff` to see uncommitted changes. Note which files and areas are affected.

### Step 2: Identify relevant learnings

Glob `[docs directory]/learnings/*.md` and match filenames to the diff area using the keyword map below. Pick the **top 3–5** most relevant files.

**Keyword map — organized by domain (customize for your project):**

| Diff area | Keywords to match | Example files |
|---|---|---|
| API, network, HTTP | `api`, `http`, `rest`, `grpc`, `endpoint`, `request` | `api-error-handling-learnings.md` |
| UI, rendering, display | `render`, `ui`, `display`, `layout`, `css`, `styling` | `ui-rendering-learnings.md` |
| State, data, store | `state`, `store`, `reactive`, `observable`, `cache` | `state-management-learnings.md` |
| Auth, security, permissions | `auth`, `security`, `permission`, `token`, `session` | `auth-flow-learnings.md` |
| Database, persistence, storage | `db`, `database`, `persistence`, `storage`, `migration` | `db-migration-learnings.md` |
| Performance, optimization | `performance`, `optimization`, `debounce`, `throttle`, `lazy` | `performance-learnings.md` |
| Testing | `testing`, `test`, `mock`, `fixture` | `testing-patterns-learnings.md` |
| Architecture, refactoring | `architecture`, `refactor`, `extraction`, `pattern` | `architecture-learnings.md` |

### Step 3: Read top learnings

Read the selected files (up to 5). Keep only the **Problem**, **Root Cause**, and **Fix** sections — skip "What Was Confusing" and "Next Steps" to save tokens.

### Step 4: Invoke subagent with enriched prompt

Call the `diff-review` or `diff-review-g31` subagent with a prompt that includes:

```
Before scanning the diff, here are learnings from prior sessions that document
intentional patterns for this project. Do NOT flag behavior matching these
patterns as bugs:

[For each learning, 2-3 sentences summarizing the intentional pattern]

Now review the current git diff:
[user's original review request]
```

### Step 5: Discussing findings with user

After the subagents return results, discuss the findings with the user before taking any corrective actions.

**Example enrichment:**

If the diff changes a rendering module and affects display logic, include a summary of the intentional pattern from your learnings:
> "The intentional pattern for [feature] is [description]. This avoids [problem] and was documented in [learning file]."

## Tips

- **Be selective** — 3–5 learnings is enough. More than 5 dilutes signal.
- **Summarize, don't paste** — Extract the key insight (2-3 sentences), not the full file.
- **Use diff-review-g31 for large diffs** — Gemma 31B catches different issues than the default model. Running both gives complementary coverage.
- **Customize the keyword map** — Update the table above to match your project's domain areas and learning file naming conventions.
