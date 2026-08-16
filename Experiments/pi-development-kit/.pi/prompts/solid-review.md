---
description: Delegate a SOLID principles review to the solid-review subagent
argument-hint: "[file or area]"
---
Delegate a SOLID principles review to the solid-review subagent: use the `subagent` tool with agent `solid-review` and a task containing the user's request (${@:-review the current uncommitted changes for SOLID violations}). The subagent is read-only, so include in the task text any file contents or diff it needs to see; its findings come back as its final response. Discuss the findings with me before making any changes.
