# Hero Index Removal — Learnings 2026-05-15

**Purpose:** Document learnings from removing the hero index star feature and simplifying the hero layout to rely on sidebar drag-and-drop order.

## What Worked

- **Tests guided the changes** — Removing `heroIndex` from `LayoutGenerator.generate()` cascaded through all test files. Test compilation failures immediately surfaced every call site, making it easy to track and fix all references across 4 test files.
- **Feature removal was clean** — `heroIndex` had no hidden dependencies beyond the obvious UI (star indicator, thumbnail strip) and ViewModel property. The `customImageOrder` permutation already provided the same capability through sidebar reorder, so removal was pure simplification.
- **Simplified `generateHero()`** — The function went from ~40 lines (with `adjustedOrder` logic, clamping, heroIdx math) to ~25 lines that just uses `imageOrder[0]` directly. Less branching, easier to reason about.

## What Didn't Work / Gaps

- **Multi-line edit produced brace mismatch** — Removing the hero thumbnail strip from `ContentView.swift` was a large block deletion. The edit accidentally dropped a closing brace for the `ForEach` content closure, producing "private can only be used in non-local scope" errors. The fix required careful brace counting to restore the `ForEach` → `.onMove` → `Section` nesting.
- **`.onMove` placement** — During the fix, `.onMove` was placed inside the `ForEach` content closure instead on the `ForEach` itself, causing Swift type-checker timeout. Moving it to the `ForEach` level resolved both the brace issue and the timeout.

## What Was Confusing

- Nothing particularly confusing. The scope of removal was clear from the user's request.

## Code Patterns Learned

- **When removing a parameter from a shared API, use grep first** — Running `grep "heroIndex" --include="*.swift"` before starting showed all 74 references across 7 files. This made the removal systematic rather than iterative.
- **`sed` for mechanical test updates** — For test files that only needed `, heroIndex: nil,` removed from `LayoutGenerator.generate()` calls, `sed -i '' 's/, heroIndex: nil,/,/g'` was faster than manual editing.
- **Swift type-checker timeout is a brace problem** — When the compiler reports "unable to type-check this expression in reasonable time" on a file that previously compiled, it's often a structural issue (misplaced brace, unclosed closure) rather than a genuinely complex expression. Check brace nesting first.

## Next Steps

- Remaining round-4 plan items: Title font dropdown (searchable, WYSIWYG), alignment SF Symbols, background toggle label, Status section (no changes)

---
**Status**: Closed
**Follow-up**: Round 4, Items 3-5 (ExportPanel improvements)
