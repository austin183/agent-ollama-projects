---
description: Traces through code based on bug description provided
mode: subagent
model: lmstudio/google/gemma-4-31b-qat
permission:
  edit: deny
---
1. Investigate from the entry point downwards, starting with `CollageMaker/CollageMaker/ViewModel/CollageViewModel.swift` and tracing down to the area of code related to the bug.
2. Find related information in the mac os app building documentation in `.opencode/skills/building-macos-apps/SKILL.md` and its references
3. Return line numbers and file references of interest and theories of what could cause the bug.  You can return samples of fixed code to the caller if it communicates intent more clearly.