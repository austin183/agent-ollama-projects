---
name: capturing-learnings
description: Guides users through structured debriefs after exercises to identify what worked, what was missing, and how to improve. Use when the user completes an exercise, task, or session and wants to capture insights for future reference.
---

# Capturing Learnings

Capture structured insights from completed exercises to build better Skills iteratively. This skill follows a proven debrief process that identifies patterns, gaps, and improvement opportunities.

## When to use this Skill

- User completes an exercise, task, or session
- User wants to document what worked, what failed, or what was confusing
- User is building or refining Skills and needs systematic way to capture learnings
- User wants to preserve insights for future reference

## Debrief Template

After completing an exercise, guide the user through these structured questions:

### What Worked

```
What succeeded in this exercise?

- Specific patterns that produced good results
- Approaches that saved time or reduced errors
- Tools, libraries, or methods that performed well
- Any unexpected discoveries or "aha" moments
```

### What Didn't Work / Gaps

```
What was problematic or missing?

- Approaches that failed or produced poor results
- Missing context, information, or resources
- Confusing instructions or unclear requirements
- Bugs, errors, or unexpected behaviors
- Tools or libraries that caused issues
```

### What Was Confusing

```

What parts were unclear or ambiguous?

- Ambiguous requirements or specifications
- Unclear terminology or jargon
- Missing documentation or examples
- Poorly designed interfaces or APIs
- Any uncertainty about expected behavior
```

### Skill Mapping

```

How can these insights improve existing Skills?

- Which Skills should be updated based on these learnings?
- What new rules, patterns, or best practices should be added?
- What documentation needs expansion?
- What examples or evaluations should be created?
```

### Documentation Format

```

Where should these learnings be saved?

- Update existing skills document (if applicable)
- Create new skills document for this exercise
- Add to agent_docs/thoughts/ for future reference
- Document in a debrief file with date and purpose
```

> **Note**: Paths like `agent_docs/thoughts/` should not become outdated. If the location changes, update this skill to reflect the new location.

## Workflow Pattern

Copy this checklist and track your progress:

```
Task Progress:
- [ ] Complete exercise
- [ ] Run capturing-learnings
- [ ] Organize insights by category
- [ ] Map insights to skill improvements
- [ ] Save documentation
```

### Step 1: Complete Exercise

Finish the task or exercise completely before running capturing-learnings.

### Step 2: Run Capturing-Learnings

Present the debrief template to the user and ask them to answer each section.

### Step 3: Organize Insights

Group answers by category (worked, gaps, confusing, skill mapping).

### Step 4: Map to Improvements

Identify specific skills to update and document what changes are needed.

### Step 5: Save Documentation

Save learnings in an appropriate location (see Documentation Format above).

## Key Insight

The debrief process is essential for iterative Skill development because:
- Context gets cluttered after exercises
- Insights need to be persistent for future reference
- Systematic categorization helps identify patterns
- Clear documentation accelerates future work
- Lessons learned can be translated into improved Skills

## Debrief Structure

Learnings are most useful when saved with this structure:

```markdown
# [Topic] - Debrief [Date]

**Purpose**: [What this exercise was for]

## What Worked

[Details...]

## What Didn't Work / Gaps

[Details...]

## What Was Confusing

[Details...]

## Skill Improvements

[Specific changes to make...]

## Next Steps

[Actions to take...]

---
**Status**: [Open/Closed/In Progress]
**Follow-up**: [Related exercises or tasks]
```

## Using the Skills-Best-Practice Skill

After capturing learnings, use the skills-best-practice skill to:
- Review existing Skills for improvements
- Create new Skills based on patterns discovered
- Add evaluations to test new approaches
- Document learnings in the skills-best-practice documentation