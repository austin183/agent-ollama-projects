# Harness Notes

This workspace is a shell around whatever is in the internal `workspace` folder.  It could be different from time to time.  Skills and Subagents in this Harness need to apply generically to whatever is in the workspace.

PLEASE AVOID using SubAgents since they are not supported for this environment yet.

# Project Imperatives

- When writing code of any kind, think about the test cases that could go with it to verify it works as expected
    - Unit Tests
    - Mock Folders with Files for tests involving file management
- When encountering unexpected errors, think about what the user could help clarify before proceeding
- When skills do not work as expected, think about how to refine the skill