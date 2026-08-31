# Implementation Plan Creation Process

## Initial Response

When creating an implementation plan:

1. **Check if parameters were provided**:
   - If a file path or ticket reference was provided, skip the default message
   - Immediately read any provided files FULLY
   - Begin the research process

2. **If no parameters provided**, respond with understanding questions about the task, context, constraints, and requirements.

## Process Steps

### Step 1: Context Gathering & Initial Analysis

1. **Read all mentioned files immediately and FULLY**:
   - Ticket files or plan references
   - Research documents
   - Related implementation plans
   - Any data files mentioned
   - Use Read tool WITHOUT limit/offset parameters to read entire files
   - DO NOT spawn sub-tasks before reading these files yourself in the main context

2. **Spawn initial research tasks to gather context**:
   Before asking the user any questions, use specialized agents to research in parallel:
   - Use codebase-locator or explore agent to find all files related to the ticket/task
   - Use codebase-analyzer or general agent to understand how the current implementation works
   - If relevant, find existing thoughts documents or plans about this feature

3. **Read all files identified by research tasks**:
   - After research tasks complete, read ALL files they identified as relevant
   - Read them FULLY into the main context
   - This ensures complete understanding before proceeding

4. **Analyze and verify understanding**:
   - Cross-reference the ticket requirements with actual code
   - Identify any discrepancies or misunderstandings
   - Note assumptions that need verification
   - Determine true scope based on codebase reality

5. **Present informed understanding and focused questions**:
   ```
   Based on the ticket and my research of the codebase, I understand we need to [accurate summary].

   I've found that:
   - [Current implementation detail with file:line reference]
   - [Relevant pattern or constraint discovered]
   - [Potential complexity or edge case identified]

   Questions that my research couldn't answer:
   - [Specific technical question that requires human judgment]
   - [Business logic clarification]
   - [Design preference that affects implementation]
   ```

### Step 2: Research & Discovery

After getting initial clarifications:

1. **If the user corrects any misunderstanding**:
   - DO NOT just accept the correction
   - Spawn new research tasks to verify the correct information
   - Read the specific files/directories they mention
   - Only proceed once you've verified the facts yourself

2. **Create a research todo list** using TodoWrite to track exploration tasks

3. **Spawn sequential sub-tasks for comprehensive research**:
   - Create multiple Task agents to research different aspects concurrently
   - Use Explorer subagents with focused objectives 

4. **Wait for ALL sub-tasks to complete** before proceeding

5. **Present findings and design options**:
   ```
   Based on my research, here's what I found:

   **Current State:**
   - [Key discovery about existing code]
   - [Pattern or convention to follow]

   **Design Options:**
   1. [Option A] - [pros/cons]
   2. [Option B] - [pros/cons]

   **Open Questions:**
   - [Technical uncertainty]
   - [Design decision needed]

   Which approach aligns best with your vision?
   ```

### Step 3: Plan Structure Development

Once aligned on approach:

1. **Create initial plan outline**:
   ```
   Here's my proposed plan structure:

   ## Overview
   [1-2 sentence summary]

   ## Implementation Phases:
   1. [Phase name] - [what it accomplishes]
   2. [Phase name] - [what it accomplishes]
   3. [Phase name] - [what it accomplishes]

   Does this phasing make sense? Should I adjust the order or granularity?
   ```

2. **Get feedback on structure** before writing details

### Step 4: Detailed Plan Writing

After structure approval:

1. **Write the plan** to the appropriate location (e.g., `[docs directory]/plans/YYYY-MM-DD-description.md`)
2. **Use the standard template structure** with phases, success criteria, and testing strategy

### Step 5: Review

1. **Present the draft plan location**:
   ```
   I've created the initial implementation plan at:
   [plan file path]

   Please review it and let me know:
   - Are the phases properly scoped?
   - Are the success criteria specific enough?
   - Any technical details that need adjustment?
   - Missing edge cases or considerations?
   ```

2. **Iterate based on feedback** - be ready to add missing phases, adjust technical approach, clarify success criteria, add/remove scope items

## Important Guidelines

1. **Be Skeptical**: Question vague requirements, identify potential issues early, ask "why" and "what about", don't assume - verify with code
2. **Be Interactive**: Don't write the full plan in one shot, get buy-in at each major step, allow course corrections, work collaboratively
3. **Be Thorough**: Read all context files COMPLETELY before planning, research actual code patterns using parallel sub-tasks or agents, include specific file paths and line numbers, write measurable success criteria with clear automated vs manual distinction
4. **Be Practical**: Focus on incremental, testable changes, consider migration and rollback, think about edge cases, include "what we're NOT doing"
5. **Track Progress**: Use TodoWrite to track planning tasks, update todos as you complete research, mark planning tasks complete when done
6. **No Open Questions in Final Plan**: If you encounter open questions during planning, STOP, research or ask for clarification immediately, do NOT write the plan with unresolved questions

## Success Criteria Guidelines

Always separate success criteria into two categories:

1. **Automated Verification** (can be run by execution agents):
   - Commands that can be run: tests, linting, type checking
   - Specific files that should exist
   - Code compilation/type checking
   - Automated test suites

2. **Manual Verification** (requires human testing):
   - UI/UX functionality
   - Performance under real conditions
   - Edge cases that are hard to automate
   - User acceptance criteria

**When pinning exact test counts, pin the row structure too.** A pinned total ("24 new `it`s to land at 311") survives only if the suite is structured **one `it` per pinned scenario row**, with auxiliary checks (constant-value assertions, barrel spot-checks) folded into their most-related row — not given convenience rows of their own. Without the structural pin, the first GREEN lands off-count (2026-08-30, CR 004: 27 instead of 24 — all green, gate failed) and the fix is a post-hoc assertion migration instead of a plan correction. State the one-`it`-per-row rule in the phase's success criteria so the builder inherits it from the plan.
