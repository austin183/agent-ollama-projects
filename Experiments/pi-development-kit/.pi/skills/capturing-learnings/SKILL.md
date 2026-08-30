---
name: capturing-learnings
description: Autonomously reviews a completed exercise, task, or session for insights worth preserving, and saves them as a dated learnings document when they add something new. Use after completing an exercise, task, or session, or when the user asks to capture learnings or debrief. Runs without asking the user questions; making no updates is a valid outcome.
---

# Capturing Learnings

Review a completed exercise, task, or session and persist any insights that will save time or prevent mistakes in future work.

**This skill runs autonomously.** Do not ask the user what mattered, what was confusing, or whether anything should be saved. Use your own judgment from the conversation context. Ending with no updates is an acceptable and common outcome — do not pad a document to justify running the skill.

## Workflow

Copy this checklist and track your progress:

```
Learnings Progress:
- [ ] Survey the conversation for candidate insights
- [ ] Check existing coverage
- [ ] Decide: record, extend, or skip
- [ ] Save and report
```

### Step 1: Survey for candidate insights

Re-read the completed work and note anything that falls in these categories:

- **What worked** — patterns, approaches, or tools that produced good results or saved time
- **Gaps** — missing context, confusing instructions, failed approaches, unexpected errors or behaviors
- **Skill mapping** — existing skills whose guidance was missing, wrong, or incomplete in practice

Prefer concrete, reusable insights ("pi subagent runs need `--no-session` or usage is double-counted") over vague ones ("testing was important").

### Step 2: Check existing coverage

Before recording anything, compare each candidate against:

- Existing skills under `.pi/skills/` (read the relevant ones)
- Existing documents under `_agent_docs/learnings/`

Discard candidates that are already covered, are one-off trivia unlikely to recur, or are model/general-knowledge facts that don't need saving.

### Step 3: Decide

- **Record** — genuinely new, reusable insights → save a new learnings document (Step 4)
- **Extend** — a candidate refines an existing skill or learnings doc → propose or make that targeted edit instead
- **Skip** — nothing new or relevant → make no file changes and say so briefly

### Step 4: Save and report

Save new learnings to `_agent_docs/learnings/` as a dated rule-file: `YYYY-MM-DD-<slug>.md`.

Use this structure:

```markdown
# [Topic] - Learnings [YYYY-MM-DD]

**Context**: [The exercise/task this came from, one line]

## Insights
- [Insight, stated as a reusable rule or fact]
- ...

## Suggested Skill Changes
- [Skill to update and the specific change] (omit if none)
```

Then report to the user in a few lines: what was recorded where (or that nothing was recorded and why). Do not wait for user input at any step.

## Notes

- The learnings location follows project convention (`_agent_docs/learnings/`, dated rule-files; archive older files as the folder grows). If the convention changes, update this skill.
- After recording, the `skills-best-practice` skill can be used to apply the suggested skill changes — but only when the user asks for that follow-up.
