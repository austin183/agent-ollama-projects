# Code Review Best Practices

## Contents
- Review process
- Quality assurance
- Mentoring
- Resolving conflicts

## Review Process

### 1. Context First
1. Read commit message and PR description
2. Review related design documents
3. Understand intended behavior and edge cases

### 2. Design First
1. Evaluate overall design and architecture
2. Check SOLID principles and separation of concerns
3. Verify the approach is sound

### 3. Detailed Review
1. Read code systematically
2. Run tests and check coverage
3. Verify style compliance

### 4. Feedback
1. Highlight positives along with improvements
2. Be specific and actionable
3. Ask questions instead of making demands

## Quality Assurance

### Approval Criteria
- Code improves maintainability, readability, or performance
- All critical issues resolved
- Tests are adequate

### Nit Comments
Prefix non-critical suggestions with `Nit:`

```text
Nit: consider renaming variable `tmp` to `result` for clarity.
```

### Escalation Path
If consensus cannot be reached:
1. Team discussion
2. Technical Lead
3. Maintainer
4. Engineering Manager

## Mentoring

### For Junior Developers
- Explain *why* changes are suggested
- Provide examples of alternatives
- Encourage questions

### Feedback Style
- Focus on code, not author
- Be constructive, not critical
- Balance positives with areas for improvement

## Common Scenarios

### Stuck Reviews
**Problem**: Review pending for days

**Solution**:
1. Check for unresolved comments
2. Open quick chat with reviewer
3. Escalate to Technical Lead if needed

### Conflicting Opinions
1. Refer to style guide/documentation
2. Discuss trade-offs
3. Escalate if unresolved

### Unreviewable Code
- If reviewer lacks expertise in an area:
  - Request specialist input
  - Acknowledge limitations in feedback

## Tips

### Best Practices
- Prefix non-critical comments with `Nit:`
- Keep reviews focused on code, not author
- Don't strive for perfection; value improvements
- Record outcomes of discussions as comments

### Common Pitfalls
- Approving code you wouldn't write (if it works, it works)
- Overlooking small changes (they add up)
- Delaying reviews (block others)
- Being too harsh or too lenient

## Configuration

- **URL**: https://google.com/code-review
- **Path**: /review-guidelines
