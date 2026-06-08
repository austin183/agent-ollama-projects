# Code Review: CollageMaker (Post-Round 99)
**Date:** 2026-06-07
**Reviewer:** opencode (Agent)

## 1. Executive Summary

The `CollageMaker` project is architecturally sound at a high level, following a clean MVVM + Service layer pattern. The separation between geometry calculation and rendering is a particular strength. However, as the project has grown, several critical "growth pains" have emerged, specifically a God-object ViewModel and some critical bugs in the Vision/Analysis pipeline.

**Overall Status:** ⚠️ **Request Changes**
The project is stable but contains a high-severity bug in portrait image handling and a concurrency bottleneck in the saliency analysis that must be addressed before further feature expansion.

---

## 2. Critical Issues (Must be Fixed)

### 🔴 Runtime Bugs & Performance
| ID | Issue | Impact | Location | Recommendation |
|:---|:---|:---|:---|:---|
| **COORD-01** | **Portrait Coordinate Swap Bug** | Incorrect crop placement for portrait images. | `SaliencyResult.swift:26` | Remove the X/Y swap logic in `cropOrigin(for:cropSize:)`. |
| **CONC-01** | **Sequential Actor Execution** | Batch analysis is sequential, not parallel, blocking performance. | `SaliencyAnalyzer.swift:27` | Mark `analyze(_:)` as `nonisolated`. |
| **ERR-01** | **All-or-Nothing Batch Failure** | One corrupt image fails the entire collage analysis. | `SaliencyAnalyzer.swift:102` | Use optional results in `ThrowingTaskGroup` and catch errors per-image. |

### ⚠️ Architectural Violations (SOLID)
| ID | Issue | Principle | Impact | Location | Recommendation |
|:---|:---|:---|:---|:---|:---|
| **SRP-01** | **God Class: `CollageViewModel`** | SRP | High maintenance burden; fragile state. | `CollageViewModel.swift` | Extract `TitleManager`, `BackgroundManager`, and `LayoutCoordinator`. |
| **DIP-01** | **Hardcoded Manager Deps** | DIP | Inhibits unit testing and isolation. | `CollageViewModel.swift` | Inject managers via protocols in the initializer. |
| **OCP-01** | **Leaky Strategy Abstraction**| OCP | Adding layouts forces changes to the public `generate` signature. | `LayoutGenerator.swift:9` | Use a `LayoutOptions` enum/config object for strategy-specific parameters. |

---

## 3. Detailed Domain Analysis

### ViewModel Domain
The `CollageViewModel` has exceeded its reasonable size (~1,100 lines). While it coordinates well, it is doing too much "work" rather than "orchestration."
- **State Management:** The manual versioning (`cropMapVersion`, etc.) is a brittle workaround for `@Observable`.
- **Boilerplate:** The proliferation of individual debounce tasks suggests a need for a generic `Debouncer` utility.

### Layout & Assembly Domain
This is the most mature part of the codebase. The separation of `LayoutGenerator` (math) and `CollageAssembler` (rendering) is excellent.
- **Coordinate Systems:** The transformation logic in `CollageAssembler` is functional but should be moved to a geometry model (e.g., `PanelGeometry`) to prevent duplication in the UI layer.

### Vision/Analysis Domain
While the use of protocols makes this layer testable, the implementation has critical flaws in concurrency and coordinate handling (as noted in the Critical Issues table).

---

## 4. Nit Comments & Suggestions

- **[Nit]** `UserDefaultsPersistence` should be behind a protocol to avoid tight coupling to `UserDefaults`.
- **[Suggestion]** Move `SaliencyResult.cropOrigin` logic into a `CoordinateConverter` utility to keep the model a pure DTO.
- **[Suggestion]** In `LayoutGenerator.swift:201`, the `makeStrategy` switch is fine for now, but consider a registration-based factory if layout styles grow beyond 15.

---

## 5. Final Decision: Request Changes

**Required Changes for Approval:**
1. Fix the portrait coordinate swap bug in `SaliencyResult.swift`.
2. Resolve the sequential actor bottleneck in `SaliencyAnalyzer.swift`.
3. Implement robust batch error handling in `analyzeAll`.
4. (High Priority) Begin decomposing `CollageViewModel` into specialized managers.
