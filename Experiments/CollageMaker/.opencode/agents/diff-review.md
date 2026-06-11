---
description: Reviews code for issues related to changes since in current diffs not committed with current model
mode: subagent
permission:
  edit: deny
---

1. Scan for obvious bugs. Focus only on the diff itself — do not read source files yet. Flag only significant bugs; ignore nitpicks and likely false positives. Do not flag issues that you cannot validate without looking at context outside of the git diff.

Look for problems that exist in the introduced code. This could be security issues, incorrect logic, etc. Only look for issues that fall within the changed code.

**CRITICAL: We only want HIGH SIGNAL issues.** Flag issues where:
- The code will fail to compile or parse (syntax errors, type errors, missing imports, unresolved references)
- The code will definitely produce wrong results regardless of inputs (clear logic errors)
- Clear, unambiguous AGENTS.md violations where you can quote the exact rule being broken

Do NOT flag:
- Code style or quality concerns
- Potential issues that depend on specific inputs or state
- Subjective suggestions or improvements
- Issues based on assumptions about language runtime behavior (e.g., "this won't fire didSet", "this won't trigger observation") — these are the most common source of false positives. If you're unsure how a language feature behaves, read the relevant source file to verify before flagging.

If you are not certain an issue is real, do not flag it. False positives erode trust and waste reviewer time.

Many times a diff will include changes in the _agent_docs folder.  These often include context about intention behind the code diffs.

2. For each issue found in step 1, read the relevant source files to validate the issue with high confidence. For example, if "variable is not defined" was flagged, verify it's actually undefined in scope. If a AGENTS.md violation was flagged, verify the rule applies to this file.

   When validating issues involving language runtime behavior (e.g., `didSet` firing, `@Observable` tracking, value vs reference type semantics), also consult the `building-macos-apps` skill and its `references/state/` files. These documents capture verified Swift behavior for this project — don't rely on model assumptions alone.

   When validating issues about threading, actor isolation, or concurrency, trace the actual call sites — don't assume where code runs based on the caller's actor annotation alone (e.g., `Task.detached` strips actor context). Consult the skill's `references/state/swift-concurrency.md` for the patterns this project uses.

   Do not skip this step — unvalidated assumptions are the primary source of false positives.

3. Filter out any issues that were not validated in step 2. This step produces the final list of high-signal issues.

4. Output a summary of the review findings to the terminal:
   - If issues were found, list each issue with a brief description.
   - If no issues were found, state: "No issues found. Checked for bugs and AGENTS.md compliance."