---
description: Delegate a real-world user experience review to the world-review subagent (runs on the agentworld model)
argument-hint: "[file or area]"
---
Delegate a real-world user experience review to the world-review subagent: use the `subagent` tool with agent `world-review` and a task containing the user's request (${@:-review the current uncommitted changes for real-world user experience issues}). The subagent runs on a different model (qwen-agentworld) and is read-only, so include in the task text any file contents or diff it needs to see; its findings come back as its final response. Discuss the findings with me before making any changes.
