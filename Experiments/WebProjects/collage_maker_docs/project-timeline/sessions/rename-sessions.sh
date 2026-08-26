#!/bin/zsh
# Dry-run rename script for session summary files.
# New convention: YYYY-MM-DD-XXX-<agent>-<description>.<ext>
#
# Usage:
#   zsh rename-sessions.sh --dry-run   # preview (default)
#   zsh rename-sessions.sh             # execute
#
# Run from: CollageMaker/_agent_docs/project-timeline/sessions/

SESSIONS_DIR="$(dirname "$0")"
DRY_RUN="${1:---dry-run}"

rename() {
  local old="$1" new="$2"
  if [[ "$DRY_RUN" == "--dry-run" ]]; then
    echo "mv \"$old\" \"$new\""
  else
    echo "mv \"$SESSIONS_DIR/$old\" \"$SESSIONS_DIR/$new\""
    mv "$SESSIONS_DIR/$old" "$SESSIONS_DIR/$new"
  fi
}

# ============================================================
# 2025-06-12
# ============================================================
# NOTE: session-tdd-agent-20250612.json was renamed to 2025-06-12-001-build-tdd-create-tdd-agent.json
# by this script, then corrected to 2026-07-07-004-build-tdd-create-tdd-agent.json (date was a typo).

# ============================================================
# 2026-06-30
# ============================================================
rename "session-001-summary.json" \
       "2026-06-30-001-build-docs-world-view-specifications.json"
rename "session-002-summary.json" \
       "2026-06-30-001-build-docs-implementation-plan.json"

# ============================================================
# 2026-07-01
# ============================================================
rename "session-003-summary.json" \
       "2026-07-01-001-build-code-phase1-core-architecture.json"
rename "session-004-summary.json" \
       "2026-07-01-001-build-code-phase2-panel-editing-crop.json"

# ============================================================
# 2026-07-02
# ============================================================
rename "session-006-summary.json" \
       "2026-07-02-001-build-docs-p0-test-implementation.json"
rename "session-007-summary.json" \
       "2026-07-02-002-build-docs-agent-infrastructure-review.json"
rename "session-008-summary.json" \
       "2026-07-02-001-build-test-p0-test-fixes.json"
rename "session-009-summary.json" \
       "2026-07-02-001-build-quick-work-feature-commits.json"
rename "session-010-summary.json" \
       "2026-07-02-003-build-docs-midpoint-gap-plans.json"
rename "session-011-summary.json" \
       "2026-07-02-001-build-debug-vue-options-api-fixes.json"
rename "session-012-summary.json" \
       "2026-07-02-001-build-code-phase3-backgrounds-title-overlay.json"

# ============================================================
# 2026-07-03
# ============================================================
rename "session-013-summary.json" \
       "2026-07-03-001-build-test-title-manager-p0-tests.json"
rename "session-014-summary.json" \
       "2026-07-03-001-build-docs-skill-refinement-testing.json"
rename "session-015-summary.json" \
       "2026-07-03-002-build-docs-skill-refinement-testing-learnings.json"
rename "session-016-summary.json" \
       "2026-07-03-001-build-debug-canvas-preview-offscreen.json"
rename "session-017-summary.json" \
       "2026-07-03-003-build-docs-css-layout-reference.json"
rename "session-018-summary.json" \
       "2026-07-03-004-build-docs-pre-phase4-architecture-review.json"
rename "session-019-summary.json" \
       "2026-07-03-005-build-docs-cache-estimation-bugfix.json"
rename "session-020-summary.json" \
       "2026-07-03-002-build-test-keyboard-shortcuts-test-plan.json"
rename "session-021-summary.json" \
       "2026-07-03-003-build-test-landing-page-test-plan.json"
rename "session-022-summary.json" \
       "2026-07-03-006-build-docs-keyboard-shortcuts-implementation.json"
rename "session-023-summary.json" \
       "2026-07-03-004-build-test-saliency-test-plan.json"
rename "session-024-summary.json" \
       "2026-07-03-007-build-docs-skill-refinement-keyboard-handler.json"
rename "session-025-summary.json" \
       "2026-07-03-008-build-docs-deferred-feature-learnings.json"
rename "session-026-summary-01.json" \
       "2026-07-03-005-build-test-landing-page-tests.json"
rename "session-026-summary.json" \
       "2026-07-03-006-build-test-saliency-debug-overlay-test-plan.json"
rename "2026-07-03-consolidated-report-design.json" \
       "2026-07-03-009-build-docs-consolidated-report-design.json"

# ============================================================
# 2026-07-04
# ============================================================
rename "session-005-summary.json" \
       "2026-07-04-001-build-docs-tax-bracket-visualizer-research.json"
rename "session-027-summary.json" \
       "2026-07-04-001-build-test-saliency-analyzer-tests.json"
rename "session-028-summary.json" \
       "2026-07-04-002-build-test-responsive-design-test-plan.json"
rename "session-029-summary.json" \
       "2026-07-04-003-build-test-saliency-debug-overlay-tests.json"
rename "session-030-summary.json" \
       "2026-07-04-004-build-test-pwa-test-plan.json"
rename "session-031-summary.json" \
       "2026-07-04-002-build-docs-writing-plans-skill.json"
rename "session-032-summary.json" \
       "2026-07-04-005-build-test-responsive-design-tests.json"
rename "session-033-summary.json" \
       "2026-07-04-003-build-docs-skill-refinement-responsive.json"
rename "session-034-summary.json" \
       "2026-07-04-006-build-test-pwa-capabilities-tests.json"
rename "session-035-summary.json" \
       "2026-07-04-004-build-docs-skill-refinement-pwa.json"
rename "session-036-summary.json" \
       "2026-07-04-007-build-test-background-renderer-tests.json"
rename "session-037-summary.json" \
       "2026-07-04-008-build-test-title-renderer-tests.json"
rename "session-038-summary.json" \
       "2026-07-04-009-build-test-title-renderer-coverage.json"
rename "session-039-summary.json" \
       "2026-07-04-005-build-docs-post-phase3-state-review.json"
rename "session-040-summary.json" \
       "2026-07-04-006-build-docs-architectural-refactoring-plan.json"

# ============================================================
# 2026-07-05
# ============================================================
rename "session-041-summary.json" \
       "2026-07-05-001-build-test-phase2-god-module-decoupling.json"
rename "session-042-summary.json" \
       "2026-07-05-002-build-test-phase4-cleanup-dead-code.json"
rename "session-044-crop-drag-fix.json" \
       "2026-07-05-001-build-debug-crop-drag-fix.json"
rename "session-045-crop-preview-fix.json" \
       "2026-07-05-002-build-debug-crop-preview-and-render-fix.json"
rename "session-046-crop-interaction-fix.json" \
       "2026-07-05-003-build-debug-crop-interaction-fix.json"
rename "session-047-pre-commit-review-fixes-plan.json" \
       "2026-07-05-007-build-docs-pre-commit-review-fixes-plan.json"
rename "2026-07-05-building-web-apps-refinement.json" \
       "2026-07-05-008-build-docs-skill-refinement-extensibility.json"
rename "2026-07-05-skill-refinement.json" \
       "2026-07-05-009-build-docs-skill-refinement-architectural-refactoring.json"
rename "2026-07-05-phase1-memory-cleanup.md" \
       "2026-07-05-003-build-test-phase1-memory-cleanup.md"
rename "2026-07-05-phase3-extensibility.md" \
       "2026-07-05-004-build-test-phase3-extensibility-improvements.md"

# ============================================================
# 2026-07-06
# ============================================================
rename "session-048-pre-commit-review-fixes-phase1.json" \
       "2026-07-06-001-build-tdd-pre-commit-review-fixes-phase1.json"
rename "2026-07-06-export-registry-skill-refinement.json" \
       "2026-07-06-001-build-docs-skill-refinement-export-registry.json"

# ============================================================
# 2026-07-07
# ============================================================
rename "session-049-pre-commit-review-fixes-phase2.json" \
       "2026-07-07-001-build-tdd-pre-commit-review-fixes-phase2.json"
rename "session-050-pre-commit-review-fixes-phase3.json" \
       "2026-07-07-002-build-tdd-pre-commit-review-fixes-phase3.json"
rename "session-051-pre-commit-review-fixes-phase4.json" \
       "2026-07-07-003-build-tdd-pre-commit-review-fixes-phase4.json"
rename "session-052-pre-commit-solid-review.json" \
       "2026-07-07-001-build-docs-solid-and-world-review.json"
rename "session-053-change-requests-plan.json" \
       "2026-07-07-002-build-docs-change-requests-plan.json"
rename "2026-07-07-building-web-apps-testing-patterns-refinement.json" \
       "2026-07-07-003-build-docs-skill-refinement-testing-patterns.json"
rename "2026-07-07-event-listener-skill-refinement.json" \
       "2026-07-07-004-build-docs-skill-refinement-event-listeners.json"

# ============================================================
# 2026-07-08
# ============================================================
rename "session-054-phase2-implementation.json" \
       "2026-07-08-001-build-tdd-change-requests-phase2.json"
rename "session-055-phase3-implementation.json" \
       "2026-07-08-002-build-tdd-change-requests-phase3.json"
rename "session-056-phase4-multitouch-implementation.json" \
       "2026-07-08-003-build-tdd-change-requests-phase4-multitouch.json"
rename "2026-07-08-phase1-change-requests.md" \
       "2026-07-08-004-build-tdd-change-requests-phase1.md"
rename "2026-07-08-building-web-apps-skill-refinement-compositing-accessibility.json" \
       "2026-07-08-001-build-docs-skill-refinement-compositing-accessibility.json"
rename "2026-07-08-pointer-handler-skill-refinement.json" \
       "2026-07-08-002-build-docs-skill-refinement-pointer-handler.json"
rename "2026-07-08-web-workers-skill-refinement.json" \
       "2026-07-08-003-build-docs-skill-refinement-web-workers.json"

# ============================================================
# 2026-07-09
# ============================================================
rename "session-057-phase5-refactoring.json" \
       "2026-07-09-001-build-tdd-change-requests-phase5-refactoring.json"
rename "session-058-pre-commit-review-5phase.json" \
       "2026-07-09-001-build-docs-pre-commit-review-5phase.json"
rename "session-059-diagonal-slices-negative-angle-fix.json" \
       "2026-07-09-001-build-debug-diagonal-slices-negative-angle.json"
rename "session-060-hexagonal-overlap-fix.json" \
       "2026-07-09-002-build-debug-hexagonal-overlap-fix.json"
rename "session-061-change-requests-followup-plan.json" \
       "2026-07-09-002-build-docs-change-requests-followup-plan.json"
rename "2026-07-09-building-web-apps-factory-testability-refinement.json" \
       "2026-07-09-003-build-docs-skill-refinement-factory-testability.json"

# ============================================================
# 2026-07-10
# ============================================================
rename "session-062-phase1-followup-implementation.json" \
       "2026-07-10-001-build-docs-followup-phase1-saliency-toast.json"
rename "session-063-phase2-followup-implementation.json" \
       "2026-07-10-001-build-tdd-followup-phase2-tdd.json"
rename "session-2026-07-10-toast-aria-skill-refinement.json" \
       "2026-07-10-002-build-docs-skill-refinement-toast-aria.json"

# ============================================================
# 2026-07-11
# ============================================================
rename "session-064-expanded-color-swatch-pivot.json" \
       "2026-07-11-001-build-tdd-expanded-color-swatch-pivot.json"

echo ""
if [[ "$DRY_RUN" == "--dry-run" ]]; then
  echo "--- Dry run complete. Remove --dry-run to execute. ---"
else
  echo "--- Rename complete. ---"
fi
