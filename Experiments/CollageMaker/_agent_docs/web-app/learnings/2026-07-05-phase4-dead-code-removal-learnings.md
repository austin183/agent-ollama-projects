# Phase 4 Dead Code Removal Learnings - 2026-07-05

**Purpose**: Document insights from implementing Phase 4 (Cleanup & Dead Code Removal) of the architectural refactoring plan. This session removed three dead code items: `CollageState.js`, `ComponentRegistry.js`, and `migrateLayoutStyle()`.

## What Worked

### 1. Systematic Dead Code Identification
Using grep searches and world-review guidance, we efficiently identified all dead code:
- `ComponentRegistry.js` - imported but never used (no calls to `registerService`/`getService`)
- `CollageState.js` - exported but only used by test fixtures, not production code
- `migrateLayoutStyle()` - exported but never called anywhere

### 2. Test File Updates with Local Helpers
Instead of trying to make tests work with deleted modules, we created local `createTestState()` helpers in each affected test file. This approach:
- Eliminates dependency on dead code
- Makes tests more self-contained
- Reduces coupling between test files

### 3. Incremental Deletion and Verification
We deleted one module at a time and ran tests after the batch to ensure no breaking changes. This verified that our identification of dead code was correct.

### 4. PWA Cache URL Maintenance
Updating `PWACacheUtils.js` cache URLs alongside module deletion prevents future 404 errors in service worker caching. This is often overlooked but critical for PWA functionality.

## What Didn't Work / Gaps

### 1. No Automated Dead Code Detection
We relied on manual grep searches and world-review to find dead code. A linting rule or build-time check for unused exports would catch these earlier.

### 2. Test Files Accumulate Dead Dependencies
Test files imported `createCollageState` even though it was production dead code. Tests should be reviewed as part of dead code cleanup, not just production code.

### 3. Migration Code Lingers
`migrateLayoutStyle()` remained in the codebase long after it was needed. We need a process to retire migration functions once legacy data is purged.

## What Was Confusing

### 1. Whether to Keep `createCollageState` for Tests
Initially considered whether to keep the module just for test utility. Decision: Delete it and update tests. This aligns with "tests should not depend on dead code" principle.

### 2. Update Scope for PWACacheUtils
Question: Should we remove the files from cache URLs or keep them in case they're needed again? Decision: Remove them. If needed in future, they can be restored from version control.

## Skill Improvements

### 1. building-web-apps Skill
Add guidance on dead code removal:
- Always verify modules are unused before deletion
- Update all references (imports, cache configs, documentation)
- Run full test suite after cleanup

### 2. capturing-learnings Skill
Enhance debrief template to include:
- "Dead code identified" section
- "Test dependencies updated" section

### 3. Create New Skill: Dead Code Audit
A skill for systematically identifying and removing unused code, with checklists for:
- Finding unused exports
- Checking test file dependencies
- Updating PWA cache configurations
- Verifying no runtime import errors

## Documentation Updates Needed

1. **AGENTS.md** - Add note about Phase 4 completion and dead code removal process
2. **Phase 4 Plan** - Update status to "Complete" in the implementation plan
3. **Learnings Index** - Reference this document in project overview

## Next Steps

1. Run E2E/Playwright tests to verify no runtime import errors
2. Check service worker behavior with updated cache URLs
3. Consider adding ESLint rule for unused exports
4. Schedule quarterly dead code audits

---

**Status**: Closed  
**Follow-up**: Phase 5 (if any) or ongoing maintenance
