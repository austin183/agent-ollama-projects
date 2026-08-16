---
description: Delegate a review of the uncommitted git diff to the diff-review subagent
argument-hint: "[focus areas]"
---
Delegate a high-signal review of the current uncommitted git diff to the diff-review subagent: use the `subagent` tool with agent `diff-review` and a task containing the user's request (${@:-review the current uncommitted git diff}) plus any relevant learnings from [docs directory]/learnings/ (if the running-diff-review skill is in your context, follow its enrichment workflow; otherwise pick the few most relevant learnings files yourself). The diff itself must be included in the task text since the subagent runs in its own context. Discuss the findings with me before making any changes.
