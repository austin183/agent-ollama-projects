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

Glob `_agent_docs/learnings/*.md` and match filenames to the diff area using the keyword map below. Pick the **top 3–5** most relevant files.

**Keyword map — organized by domain:**

| Diff area | Keywords to match | Example files |
|---|---|---|
| Rendering, CG, overlay, blend | `render`, `cgblend`, `layered`, `per-panel`, `background-image` | `cgblendmode-empty-context-learnings.md` |
| Concurrency, actor, Task, Sendable | `actor`, `async`, `swift6`, `computed-property-actor`, `generation-counter` | `swift6-synchronous-closure-concurrency-learnings.md` |
| @Observable, @Bindable, didSet | `observable`, `didset`, `version-counter`, `multi-field-cache`, `delegation-chain` | `observable-delegation-chain-learnings.md` |
| Gestures, drag, pinch, scroll | `gesture`, `pinch`, `scroll`, `drag`, `off-canvas`, `dynamic-zoom` | `pinch-zoom-anchor-old-vs-new-bounds.md` |
| Panels, crops, overlays | `crop`, `panel-swap`, `polygon`, `path-based`, `aspect-ratio` | `crop-preview-overlay-learnings.md` |
| Title, text, font | `title`, `attributed-string`, `coretext`, `swiftui-text` | `title-drag-position-learnings.md` |
| Coordinates, transforms | `coordinate`, `inverse-coordinate`, `shear`, `verify-data-flow` | `inverse-coordinate-transform-learnings.md` |
| Performance, debounce, throttle | `property-debounce`, `throttled`, `performance`, `gesture-render` | `property-debounce-strategy-learnings.md` |
| Architecture, extraction, refactoring | `rendering-lifecycle`, `fitmath`, `per-panel-incremental` | `rendering-lifecycle-extraction-learnings.md` |
| Testing | `testing-`, `cgpath-apply-compiler` | `testing-quality-gap-learnings.md` |
| Undo, persistence, settings | `undomanager`, `nsviarepresentable`, `navigation-split` | `undomanager-integration-learnings.md` |

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

If the diff changes `CollageAssembler.swift` and affects overlay rendering, include:
> "CGBlendMode on empty CGContext is intentional for layered rendering. The `renderOverlay()` method renders without blend mode (opacity only) and defers blend mode to SwiftUI's `.blendMode()` modifier where destination pixels exist. This avoids the multiply-on-transparent = black problem."

## Tips

- **Be selective** — 3–5 learnings is enough. More than 5 dilutes signal.
- **Summarize, don't paste** — Extract the key insight (2-3 sentences), not the full file.
- **Use diff-review-g31 for large diffs** — Gemma 31B catches different issues than the default model. Running both gives complementary coverage.
