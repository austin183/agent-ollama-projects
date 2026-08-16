# Iterating on Implementation Plans

## Initial Response

When iterating on an existing implementation plan:

1. **Parse the input to identify**:
   - Plan file path (e.g., `[docs directory]/plans/2026-07-02-feature-plan.md`)
   - Requested changes/feedback

2. **Handle different input scenarios**:

   **If NO plan file provided**:
   ```
   I'll help you iterate on an existing implementation plan.

   Which plan would you like to update? Please provide the path to the plan file.

    Tip: You can list recent plans in `[docs directory]/plans/`
   ```
   Wait for user input, then re-check for feedback.

   **If plan file provided but NO feedback**:
   ```
   I've found the plan at [path]. What changes would you like to make?

   For example:
   - "Add a phase for migration handling"
   - "Update the success criteria to include performance tests"
   - "Adjust the scope to exclude feature X"
   - "Split Phase 2 into two separate phases"
   ```
   Wait for user input.

   **If BOTH plan file AND feedback provided**:
   - Proceed immediately to Step 1
   - No preliminary questions needed

## Process Steps

### Step 1: Read and Understand Current Plan

1. **Read the existing plan file COMPLETELY**:
   - Use the Read tool WITHOUT limit/offset parameters
   - Understand the current structure, phases, and scope
   - Note the success criteria and implementation approach

2. **Understand the requested changes**:
   - Parse what the user wants to add/modify/remove
   - Identify if changes require codebase research
   - Determine scope of the update

### Step 2: Research If Needed

**Only spawn research tasks if the changes require new technical understanding.**

If the user's feedback requires understanding new code patterns or validating assumptions:

1. **Create a research todo list** using TodoWrite

2. **Spawn parallel sub-tasks for research**:
   - Use explore or codebase-analyzer agents to understand relevant code patterns

3. **Read any new files identified by research**:
   - Read them FULLY into the main context
   - Cross-reference with the plan requirements

4. **Wait for ALL sub-tasks to complete** before proceeding

### Step 3: Present Understanding and Approach

Before making changes, confirm your understanding:

```
Based on your feedback, I understand you want to:
- [Change 1 with specific detail]
- [Change 2 with specific detail]

My research found:
- [Relevant code pattern or constraint]
- [Important discovery that affects the change]

I plan to update the plan by:
1. [Specific modification to make]
2. [Another modification]

Does this align with your intent?
```

Get user confirmation before proceeding.

### Step 4: Update the Plan

1. **Make focused, precise edits** to the existing plan:
   - Use the Edit tool for surgical changes
   - Maintain the existing structure unless explicitly changing it
   - Keep all file:line references accurate
   - Update success criteria if needed

2. **Ensure consistency**:
   - If adding a new phase, ensure it follows the existing pattern
   - If modifying scope, update "What We're NOT Doing" section
   - If changing approach, update "Implementation Approach" section
   - Maintain the distinction between automated vs manual success criteria

3. **Preserve quality standards**:
   - Include specific file paths and line numbers for new content
   - Write measurable success criteria
   - Keep language clear and actionable

### Step 5: Review

1. **Present the changes made**:
   ```
   I've updated the plan at [plan file path]

   Changes made:
   - [Specific change 1]
   - [Specific change 2]

   The updated plan now:
   - [Key improvement]
   - [Another improvement]

   Would you like any further adjustments?
   ```

2. **Be ready to iterate further** based on feedback

## Important Guidelines

1. **Be Skeptical**: Don't blindly accept change requests that seem problematic, question vague feedback - ask for clarification, verify technical feasibility with code research, point out potential conflicts with existing plan phases

2. **Be Surgical**: Make precise edits, not wholesale rewrites, preserve good content that doesn't need changing, only research what's necessary for the specific changes, don't over-engineer the updates

3. **Be Thorough**: Read the entire existing plan before making changes, research code patterns if changes require new technical understanding, ensure updated sections maintain quality standards, verify success criteria are still measurable

4. **Be Interactive**: Confirm understanding before making changes, show what you plan to change before doing it, allow course corrections, don't disappear into research without communicating

5. **Track Progress**: Use TodoWrite to track update tasks if complex, update todos as you complete research, mark tasks complete when done

6. **No Open Questions**: If the requested change raises questions, ASK, research or get clarification immediately, do NOT update the plan with unresolved questions, every change must be complete and actionable

## Success Criteria Guidelines

When updating success criteria, always maintain the two-category structure:

1. **Automated Verification** (can be run by execution agents):
   - Commands that can be run: tests, linting, type checking
   - Specific files that should exist
   - Code compilation/type checking
   - Unit Tests, UI Tests, End to End Tests

2. **Manual Verification** (requires human testing):
   - UI/UX functionality
   - Performance under real conditions
   - Edge cases that are hard to automate
   - User acceptance criteria

## Example Interaction Flows

**Scenario 1: User provides everything upfront**
```
User: Iterate on plan [docs directory]/plans/2026-07-02-feature-plan.md - add test scenarios for section 3.3
Assistant: [Reads plan, researches patterns, updates plan]
```

**Scenario 2: User provides just plan file**
```
User: Iterate on plan [docs directory]/plans/2026-07-02-feature-plan.md
Assistant: I've found the plan. What changes would you like to make?
User: Split Phase 3 into two phases - one for backend, one for frontend testing
Assistant: [Proceeds with update]
```
