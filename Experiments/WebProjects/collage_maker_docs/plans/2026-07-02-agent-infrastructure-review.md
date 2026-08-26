# Agent & Skills Alignment Review

**Date:** 2026-07-02
**Reviewer:** build-docs agent
**Scope:** AGENTS.md, all 12 agents, all skills, documentation structure

---

## Executive Summary

The project has successfully built a functional web app (Phases 1-2 complete, 156 passing tests), but the **agent infrastructure is almost entirely misaligned** with the actual project. Every agent and most skills were copied from a macOS/Swift project template and still reference Swift, SwiftUI, OSLog, `@Observable`, and macOS-specific skills. This is a web app with Vue 3, Canvas 2D, and ES modules.

**Severity: Critical** — agents are actively giving wrong instructions to AI collaborators.

---

## 1. AGENTS.md Review

### Checklist Results

| Criterion | Status | Notes |
|-----------|--------|-------|
| **Conciseness** | PASS | 50 lines, well-structured |
| **Universality** | PASS | Covers all tasks |
| **What/Why/How** | PASS | Architecture, structure, running, conventions |
| **Progressive disclosure** | NEEDS WORK | No pointer to learnings, plans, or specs |
| **No linter duties** | PASS | No code style rules |
| **Length** | PASS | Well under 300 lines |

### Issues

**1.1 — Missing "How to work" section**
The file explains how to *run* the app but not how agents should *work* on it. There's no mention of:
- Where to write session summaries (`_agent_docs/project-timeline/sessions/`)
- Where to write learnings (`_agent_docs/learnings/`)
- Where to write plans (`_agent_docs/project-timeline/llm-usage/plans/`)
- The git commit convention (from workspace AGENTS.md: `Co-Authored-By` line)

**1.2 — Missing pointer to documentation**
No reference to `_agent_docs/` for plans, research, or specifications. Per the progressive disclosure principle, AGENTS.md should point agents to where they can find deeper context.

**1.3 — Directory listing is stale**
The directory structure shows `Export/`, `Persistence/`, and `Saliency/` as "(future)" but:
- `Saliency/SaliencyFallback.js` exists and is exported
- `Export/` directory exists (empty)
- `Persistence/` directory exists (empty)
- `App/` directory has 6 files not listed
- `MyComponents/` directory (test files) is not mentioned

---

## 2. Agents Review

### Critical Finding: ALL agents reference macOS/Swift

Every single agent file contains references to Swift, SwiftUI, macOS frameworks, or macOS-specific skills. This project is a **static web app** with zero Swift code.

### build-code.md — CRITICAL MISMATCH

| Line | Current Text | Problem |
|------|-------------|---------|
| 8 | "Swift developer" | This is a JavaScript/HTML/CSS project |
| 16 | "Swift source code" | No Swift exists |
| 20 | "compiling Swift code" | No compiler, no Swift |
| 26 | "CollageMaker macOS app" | It's a web app |
| 36 | "building-macos-apps skill" | Irrelevant skill |
| 37 | "OSLog with subsystem" | No OSLog in web |
| 38 | "@MainActor + @Observable" | No Swift concurrency |
| 39 | "Services are actors" | No Swift actors |

### build-debug.md — CRITICAL MISMATCH

| Line | Current Text | Problem |
|------|-------------|---------|
| 8 | "CollageMaker macOS app" | Web app |
| 36-40 | References to `building-macos-apps` skill references | All macOS-specific paths |
| 42 | "bash script/build_and_run.sh --logs" | Script doesn't exist |
| 43 | "bash script/build_and_run.sh --telemetry" | Script doesn't exist |
| 57-58 | "bash script/build_and_run.sh --verify" | Script doesn't exist |
| 59 | "bash script/run_tests.sh" | Script doesn't exist |

### build-test.md — PARTIAL MISMATCH

| Line | Current Text | Problem |
|------|-------------|---------|
| 8 | "Swift testing specialist" | JavaScript testing |
| 8 | "CollageMaker macOS app" | Web app |
| 16 | "Every *.js file needs *.test.js" | Correct for this project |
| 32 | "@Test functions" | Swift test annotation, not used in Mocha |
| 33 | "#expect calls" | Swift assertion, not used in Chai |

### build-docs.md — MOSTLY CORRECT

This agent is the least misaligned since it's platform-agnostic, but still references plan paths that may not match convention.

### build-quick-work.md — PARTIAL MISMATCH

| Line | Current Text | Problem |
|------|-------------|---------|
| 43 | "production Swift source code" | JavaScript |

### diff-review.md / diff-review-g31.md — PARTIAL MISMATCH

| Line | Current Text | Problem |
|------|-------------|---------|
| 29-32 | References to `building-macos-apps` skill and Swift concurrency | All macOS-specific |
| 30 | "@Observable tracking" | Not used in this project |

### planner.md / planner-g31.md — PARTIAL MISMATCH

| Line | Current Text | Problem |
|------|-------------|---------|
| 37 | "SwiftUI, state management, gestures, graphics, Vision" | All macOS-specific |
| 38-42 | References to `building-macos-apps` skill references | All macOS-specific |
| 54 | "coordinate system traps, concurrency issues, @Observable gotchas" | Not applicable |
| 60-64 | "path/to/file.swift" examples | Should be `.js` |

### solid-review.md / solid-review-g31.md — PARTIAL MISMATCH

The SOLID principles themselves are universal, but:
- Severity examples reference Swift-specific issues (`@Observable`, force unwraps, main actor)
- These should be updated with JavaScript/web equivalents

### world-review.md — PARTIAL MISMATCH

| Line | Current Text | Problem |
|------|-------------|---------|
| 10 | "building-macos-apps" skill | Irrelevant |

---

## 3. Skills Review

### Skills in `.opencode/skills/` (owned by this project)

| Skill | Relevance | Notes |
|-------|-----------|-------|
| `analyzing-opencode-usage` | High | Used for session tracking |
| `capturing-learnings` | High | Structured debriefs |
| `code-review` | High | Has JavaScript reference |
| `reviewing-agents-md` | High | Used for this review |
| `reviewing-claude-md` | **EMPTY** | Directory exists with 0 files — needs content or removal |
| `running-diff-review` | High | Used for diff reviews |
| `skill-extraction` | Medium | General utility |
| `skills-best-practice` | High | Authoring guidance |

### Inherited Skills (NOT owned by this project)

The following skills appear in the available skills list but are **not files in this project**. They are inherited from elsewhere (likely the macOS CollageMaker project at `~/workspace/agent-ollama-projects/Experiments/CollageMaker/`):

- `building-macos-apps` — macOS/SwiftUI patterns (inherited, not local)
- `playwright-apple-docs` — Apple docs scraping (inherited, not local)
- `macos-telemetry-instrumentation` — macOS logging (inherited, not local)

**These inherited skills are not actionable from this project.** However, agents in this project reference `building-macos-apps` by name, which will pull in wrong macOS context. Agent files should stop referencing that skill.

### Missing Skills

The project has no skill for its actual domain:
- **No "building-web-apps" skill** covering Vue 3 Options API, Canvas 2D, ES modules, CDN loading, Mocha/Chai testing, and Playwright E2E patterns
- **No skill** documenting the Midiestro3D pattern that this project follows

---

## 4. Documentation Structure Review

### Current State

```
_agent_docs/
├── InitialThoughts.md              # Single line, outdated paths
├── plans/                          # Plans here...
│   ├── 2026-06-30-implementation.md
│   ├── 2026-07-01-test-plan.md
│   └── 2026-07-02-p0-test-followup.md
├── project-timeline/
│   ├── sessions/                   # Session summaries here
│   │   └── session-001 through 006
│   └── (no llm-usage/plans/)      # build-docs agent expects plans HERE
├── prompts.md                      # Outdated paths throughout
├── research/                       # Good content
│   ├── MidiestroLibraryResearch.md
│   └── TFJSModelsSaliencyResearch.md
└── specifications/                 # Good content
    └── world-view-specifications.md
```

### Issues

**4.1 — No learnings directory exists**
After 6 sessions of work, `_agent_docs/learnings/` doesn't even exist. The build-docs agent specifies writing learnings there, and the capturing-learnings skill exists, but no learnings have been captured. This is hard-won knowledge being lost.

**4.2 — Plans in two different locations**
- Plans live in `_agent_docs/plans/`
- build-docs agent expects plans in `_agent_docs/project-timeline/llm-usage/plans/`
- This inconsistency will confuse agents

**4.3 — InitialThoughts.md has stale paths**
References `~/workspace/_agent_docs/CollageProject/ConvertToWebsite/` which doesn't exist.

**4.4 — prompts.md has stale paths**
Same issue — references old directory structure.

---

## 5. Recommendations

### Priority 1: CRITICAL — Fix Agent Definitions

**Action:** Rewrite all agent files to reference the actual web project.

**Specific changes per agent:**

#### build-code.md
- Change "Swift developer" → "Frontend developer"
- Change "Swift source code" → "JavaScript, HTML, and CSS source code"
- Remove all macOS-specific conventions (OSLog, @MainActor, @Observable, actors)
- Replace with web conventions:
  - ES modules with named exports
  - Factory functions for creating instances
  - Plain objects for data models
  - Vue 3 Options API for reactive state
  - Canvas 2D for rendering
  - No build step, no bundler
- Replace `building-macos-apps` skill reference with a new `building-web-apps` skill (see below)

#### build-debug.md
- Change "CollageMaker macOS app" → "CollageMaker web app"
- Remove all references to `building-macos-apps` skill and its macOS-specific references
- Replace build/run scripts with web equivalents:
  - `bash start-server.sh` to start dev server
  - Browser devtools for debugging
  - `node scripts/run-tests.js` for unit tests
  - `npx playwright test` for E2E tests
- Update debugging process to reference browser devtools, console logs, and network tab

#### build-test.md
- Change "Swift testing specialist" → "JavaScript testing specialist"
- Change "@Test functions" → "Mocha `it()` blocks"
- Change "#expect calls" → "Chai `expect()` assertions"
- Keep the `.test.js` naming convention (already correct)

#### build-docs.md
- Verify plan path convention matches actual usage (`_agent_docs/plans/` vs `_agent_docs/project-timeline/llm-usage/plans/`)

#### build-quick-work.md
- Change "Swift source code" → "JavaScript source code"

#### diff-review.md / diff-review-g31.md
- Remove all `building-macos-apps` skill references
- Remove Swift-specific validation guidance (@Observable, Swift concurrency)
- Add JavaScript/web-specific validation:
  - ES module import/export correctness
  - Canvas 2D API usage patterns
  - Vue 3 reactivity patterns

#### planner.md / planner-g31.md
- Replace all `building-macos-apps` skill references with web-appropriate references
- Change file extension examples from `.swift` to `.js`
- Update "Consult Skills" section to reference web patterns

#### solid-review.md / solid-review-g31.md
- Update severity examples to use JavaScript/web equivalents:
  - Instead of "force unwraps" → "unhandled Promise rejections"
  - Instead of "main actor violations" → "race conditions in async callbacks"
  - Instead of "@Observable" → "Vue reactivity traps"

#### world-review.md
- Remove `building-macos-apps` reference
- Add reference to web-specific considerations (browser performance, memory leaks, canvas rendering)

### Priority 2: HIGH — Create Web Project Skill

**Action:** Create `.opencode/skills/building-web-apps/SKILL.md` covering:

```
building-web-apps/
├── SKILL.md                      # Main skill instructions
├── references/
│   ├── vue-options-api.md        # Vue 3 Options API patterns
│   ├── canvas-2d.md              # Canvas 2D rendering patterns
│   ├── es-modules.md             # ES module conventions
│   ├── testing.md                # Mocha/Chai + Playwright patterns
│   └── midiestro-pattern.md      # The proven Midiestro3D pattern
```

This skill would replace all the `building-macos-apps` references in agent files.

### Priority 3: HIGH — Capture Learnings

**Action:** Create `_agent_docs/learnings/` directory and capture learnings from the 6 completed sessions. Key learnings to capture:

- UndoManager batch undo/redo bug (discovered in session 6)
- Layout math porting patterns (Swift → JavaScript)
- Canvas 2D vs CoreGraphics mapping decisions
- Mocha/Chai test patterns for browser-based tests
- Playwright E2E patterns for canvas-heavy apps
- Vue 3 Options API factory decomposition pattern

### Priority 4: MEDIUM — Fix AGENTS.md

**Action:** Update AGENTS.md with:

```markdown
## Documentation

- **Plans:** `_agent_docs/plans/` — implementation plans and test plans
- **Learnings:** `_agent_docs/learnings/` — hard-won knowledge from sessions
- **Research:** `_agent_docs/research/` — platform research and analysis
- **Specifications:** `_agent_docs/specifications/` — feature specifications
- **Session summaries:** `_agent_docs/project-timeline/sessions/`

## Working on the Project

- Write session summaries in `_agent_docs/project-timeline/sessions/` using the template from `.opencode/skills/analyzing-opencode-usage/references/session-summary.json`
- Capture learnings in `_agent_docs/learnings/` after significant discoveries
- Consult the `building-web-apps` skill for Vue 3, Canvas 2D, and ES module patterns
- Git commits must include `Co-Authored-By: LittleLight <noreply@traveler.dstny>`
```

Update the directory structure to reflect actual files.

### Priority 5: MEDIUM — Clean Up Documentation Structure

**Action:**
1. Create `_agent_docs/learnings/` directory
2. Standardize plan location — pick either `_agent_docs/plans/` or `_agent_docs/project-timeline/llm-usage/plans/` and update all references
3. Update `InitialThoughts.md` paths
4. Update `prompts.md` paths

### ~~Priority 6: Remove Irrelevant Skills~~ — REMOVED

**Struck from plan.** The macOS skills (`building-macos-apps`, `playwright-apple-docs`, `macos-telemetry-instrumentation`) are **not files in this project** — they are inherited from the macOS CollageMaker project. Removing them is out of scope. The real fix is already covered in Priority 1: stop referencing those skills in agent definitions.

---

## Summary Table

| Area | Issue Count | Severity | Effort |
|------|------------|----------|--------|
| Agent definitions (all 12) | ~40 references | **Critical** | Medium — systematic rewrites |
| Missing web skill | 1 gap | **High** | Medium — create from scratch |
| Missing learnings | 0 captured | **High** | Low — create directory + capture |
| AGENTS.md gaps | 3 issues | Medium | Low — targeted edits |
| Documentation structure | 4 issues | Medium | Low — reorganization |
| `reviewing-claude-md` empty | 1 skill | Low | Low — fill or remove | |

---

## Suggested Execution Order

All changes stay within `~/workspace/austin183.github.io/CollageMaker/`.

1. **Create `_agent_docs/learnings/`** and capture key learnings from sessions 1-6
2. **Create `building-web-apps` skill** with references for Vue 3, Canvas 2D, ES modules, testing
3. **Rewrite all 12 agent files** to reference web patterns instead of macOS patterns
4. **Update AGENTS.md** with documentation pointers and working conventions
5. **Clean up documentation structure** (standardize paths, update stale references)
6. **Address `reviewing-claude-md`** — either populate with content or remove the empty directory
