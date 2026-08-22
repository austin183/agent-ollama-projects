# Code Review: CollageMaker (Post-Round 99)
**Date:** 2026-06-07
**Reviewer:** opencode (Harold)

## 1. Executive Summary

CollageMaker is a well-architected macOS SwiftUI app with a clean MVVM + Service layer pattern. The project has matured significantly with well-extracted managers (`CropManager`, `PreviewManager`, `ExportManager`, `ImageLibraryManager`), protocol-based abstractions, and a comprehensive test suite. The separation between layout math (`LayoutGenerator`) and rendering (`CollageAssembler`) is a particular strength.

However, several issues remain that should be addressed before further feature expansion: the `CollageViewModel` god class, a questionable coordinate transform in the saliency pipeline, and opportunities to consolidate debounce boilerplate.

**Overall Status:** ⚠️ **Request Changes** (3 critical, 4 architectural)

---

## 2. Critical Issues (Must Be Fixed)

### COORD-01: Portrait Coordinate Swap Questionable
| Aspect | Detail |
|--------|--------|
| **Location** | `SaliencyResult.swift:26` |
| **Impact** | Potentially incorrect crop placement for portrait images |
| **Root Cause** | `SaliencyAnalyzer.swift:43` passes `CGImagePropertyOrientation.up` to `VNImageRequestHandler`, which tells Vision the image has no rotation. Yet `SaliencyResult.cropOrigin` swaps X/Y for portrait images, assuming Vision rotated the buffer. These two assumptions contradict each other. |
| **Recommendation** | Either (a) pass the actual EXIF orientation to `VNImageRequestHandler` and remove the swap, or (b) strip EXIF orientation at image load time using `NSImage(cgImage:cgImage, size: .zero)` and confirm the swap is unnecessary. Return to the producer-tracing pattern: trace the saliency center value back to its producer (`VNImageRequestHandler`) to verify which coordinate space it uses. |

### CONC-01: `analyzeAll` Error Handling Is All-or-Nothing
| Aspect | Detail |
|--------|--------|
| **Location** | `SaliencyAnalyzer.swift:100` |
| **Impact** | One corrupt image fails the entire batch analysis |
| **Root Cause** | `withThrowingTaskGroup` propagates the first error, discarding successful results |
| **Recommendation** | Use a non-throwing task group that collects `[Int: Result<SaliencyResult, Error>]` and logs per-image failures. Return partial results so the collage still renders with best-fit crops for failed images. |

### ARCH-01: `CollageViewModel` God Class (1100 lines)
| Aspect | Detail |
|--------|--------|
| **Location** | `CollageViewModel.swift` |
| **Impact** | High maintenance burden, fragile state management, difficult to test incrementally |
| **Root Cause** | While managers have been extracted, the ViewModel still directly handles: title state + caching, background state, layout regeneration, crop orchestration, scroll pan, preview rendering, export, undo, persistence, and saliency coordination |
| **Recommendation** | Extract a `TitleManager` (@Observable, owns title text, style, caching, and drag state) and a `LayoutManager` (owns layout style, gutter, style-specific params, and regeneration trigger). The ViewModel should orchestrate, not accumulate. |

---

## 3. Architectural Issues (Should Fix)

### SRP-02: Debounce Task Proliferation
| Aspect | Detail |
|--------|--------|
| **Location** | `CollageViewModel.swift:879-885` |
| **Issue** | Seven separate `Task<Void, Never>?` debounce variables (`previewDebounceTask`, `previewRenderDebounceTask`, `panelPreviewTask`, `titleDebounceTask`, `fontSizeDebounceTask`, `gutterDebounceTask`, `backgroundColorDebounceTask`) with identical cancel-sleep-execute patterns |
| **Recommendation** | Create a generic `Debouncer` utility: `struct Debouncer { func debounce(id: String, delay: Duration, work: @escaping @MainActor () -> Void) }`. This eliminates 7 variables and ~70 lines of boilerplate. |

### OCP-01: `LayoutStrategy` Interface Leaks Strategy Parameters
| Aspect | Detail |
|--------|--------|
| **Location** | `LayoutGenerator.swift:6`, `LayoutStyle.makeStrategy` (:197) |
| **Issue** | The `LayoutStrategy.generate` signature is stable, but `makeStrategy` requires `sliceAngle` and `hexSpacing` parameters that only two strategies use. Adding a new layout with its own parameters forces a change to `makeStrategy`. |
| **Recommendation** | Introduce a `LayoutOptions` struct with optional properties (`sliceAngle`, `hexSpacing`, etc.). Pass it to both `makeStrategy` and `generate`. New layouts read only what they need. |

### DIP-01: `ExportManager` Couples to `UserDefaults` and `NSSavePanel`
| Aspect | Detail |
|--------|--------|
| **Location** | `ExportManager.swift:48-60` |
| **Issue** | Direct `UserDefaults.standard` access for export folder memory and `NSSavePanel` instantiation make this class hard to test in isolation and violate DIP. |
| **Recommendation** | Inject a `SavePanelPresenter` protocol (present panel, return URL?) and pass the default folder as a parameter or via a `FolderMemory` protocol. |

### ISP-01: `AssemblyConfig` 14-Parameter Constructor
| Aspect | Detail |
|--------|--------|
| **Location** | `AssemblyConfig.swift:78` |
| **Issue** | The primary initializer takes 14 parameters. Callers must construct the full config even when only a subset has changed. |
| **Recommendation** | The secondary factory init (`init(layout:title:background:canvasSize:overlay:)` at line 120) is the right direction. Make this the primary API and deprecate the flat constructor. Consider a builder pattern for `buildAssemblyConfig()` in the ViewModel. |

---

## 4. Domain-Specific Analysis

### Vision / Saliency Pipeline
- **Strength:** `SaliencyAnalyzer` is an `actor` with a clean `SaliencyAnalysis` protocol. Face detection is boosted to 0.9 confidence, a good heuristic.
- **Note on prior review claim:** The previous review stated `analyzeAll` is sequential due to actor isolation. This is **incorrect** — `withThrowingTaskGroup` spawns concurrent tasks, and the actor fast-paths concurrent calls to methods that don't access actor-isolated state. The `analyze(_:)` method only uses local variables and Vision APIs. Parallelism works as intended.

### Rendering Pipeline
- **Strength:** `RenderScheduler` correctly serializes `CGContext` operations via a serial `DispatchQueue` bridged through `withCheckedContinuation`. This protects `NSGraphicsContext.current` from concurrent corruption.
- **Strength:** `CollageAssembler` properly separates full assembly, preview, per-panel, background, and title rendering into distinct protocol methods.
- **Concern:** `@unchecked Sendable` is used on `AssemblyConfig`, `BackgroundConfig`, `TitleConfig`, `LayoutConfig`, `TitleStyle`, `PanelGeometry`, and `CollageAssembler`. Each has a documented justification (AppKit types captured on MainActor, read-only on background). This is acceptable but warrants periodic audit — a single write from a background thread would be data race undefined behavior.

### Gesture Handling
- **Strength:** `GestureCoordinator` as a `@State` class correctly accumulates mutable gesture state. The title drag handler uses the producer-tracing pattern via `TitleDragHandler`.
- **Strength:** Throttled notification (`throttledNotifyCropMapChanged`) uses `ContinuousClock` + `Duration` correctly, avoiding the `mach_absolute_time()` tick-vs-nanosecond pitfall.

### Title Rendering
- **Strength:** `TitleBoundsCT` provides a lightweight CoreText bounds calculator that produces identical results to `TitleMetricsCT` for pixel-perfect outline alignment. The `TitleBoundsCache` wrapper with identity comparison is a clever testability pattern.
- **Strength:** `TitleTextData` extracts font runs from `NSAttributedString` on MainActor and crosses the concurrency boundary as a `Sendable` struct. This avoids the `NSAttributedString` thread-safety issue entirely.

### Persistence
- **Strength:** `UserDefaultsPersistence` centralizes all keys and handles type-specific archiving. The `PersistenceBundle` pattern for load is clean.
- **Concern:** `UserDefaultsPersistence` is a concrete class, not behind a protocol. The ViewModel depends on the concrete type. For testability this works (the tests pass a custom `UserDefaults`), but a protocol would be more flexible.

---

## 5. Test Quality Assessment

### Strengths
- **19 test files** covering ViewModel, services, managers, models, and performance
- `TestAssembler` is a well-designed, consolidated mock with call tracking, configurable returns, delays, and error injection
- `MockSaliencyAnalyzer` is simple and effective
- The `@Suite(.serialized)` annotation on `CollageViewModelTests` prevents concurrency races
- AppKit initialization fixture (`AppKitInit` suite) ensures `NSApplication.shared` is initialized
- Tests verify behavioral outcomes (cache invalidation, undo registration, debounced rendering) rather than implementation details

### Gaps
- **No test for `SaliencyResult.cropOrigin` with portrait images** — the coordinate swap logic at line 26 is untested
- **No test for `RenderScheduler` concurrent safety** — the existing `RenderSchedulerTests` likely test basic functionality, but not concurrent corruption of `NSGraphicsContext.current`
- **No test for `CropInfo` Codable round-trip** with `.path` geometry — the decoder reconstructs a `CGPath(rect:transform:)` from the bounding rect, losing the original path shape
- **No integration test** for the full saliency → crop → preview pipeline with real images

---

## 6. Nit Comments

- **[Nit]** `PersistenceBundle` at `UserDefaultsPersistence.swift:5` is missing its enclosing scope — the `struct` declaration appears to be outside any namespace. Consider nesting it inside `UserDefaultsPersistence` or giving it a clearer module-level purpose.
- **[Nit]** `CollageViewModel.images` and `CollageViewModel.panels` are convenience computed/stored properties that duplicate `imageLibrary.images`. The `images` accessor (`CollageViewModel.swift:90`) is fine, but `panels` being a direct stored property breaks the encapsulation of panel state — consider a `LayoutPanelManager` that owns the panels array.
- **[Suggestion]** `LayoutGenerator.generate` has 8 parameters. Consider a `LayoutRequest` struct to group `numImages`, `canvasSize`, `gutter`, `style`, `imageOrder`, `mosaicSeed`, `sliceAngle`, and `hexSpacing`.
- **[Suggestion]** `SeededPRNG` is a nice touch for reproducible mosaic layouts. Consider exposing a `mosaicSeed` property on `CollageViewModel` so users can regenerate the same mosaic.
- **[Nit]** `CollageMakerApp.swift:11` — `@State private var viewModel = CollageViewModel()` creates the ViewModel via the convenience init. This is fine, but the `CollageViewModel()` convenience init creates concrete `SaliencyAnalyzer()` and `CollageAssembler()`, making it impossible to swap implementations without changing the `@main` entry point. Consider a factory or dependency registration for production vs debug builds.

---

## 7. Final Decision: Request Changes

**Required for approval:**
1. Fix the portrait coordinate swap bug in `SaliencyResult.cropOrigin` (COORD-01)
2. Implement per-image error handling in `SaliencyAnalyzer.analyzeAll` (CONC-01)
3. Begin decomposing `CollageViewModel` — at minimum extract `TitleManager` (ARCH-01)

**Recommended before next feature sprint:**
4. Consolidate debounce tasks into a `Debouncer` utility (SRP-02)
5. Introduce `LayoutOptions` for strategy-specific parameters (OCP-01)
6. Add tests for portrait saliency crop origin and `CropInfo` Codable round-trip

**Things done well (no changes needed):**
- `RenderScheduler` serial queue pattern for `NSGraphicsContext.current` safety
- `TitleTextData` Sendable extraction for crossing concurrency boundaries
- `TitleBoundsCT` / `TitleBoundsCache` caching architecture
- `PreviewManager` generation counter pattern for stale result rejection
- Protocol-based service abstractions with comprehensive test mocks
- `CoordinateConverter` utility for canvas/preview/screen coordinate transforms
- Throttled notification with `ContinuousClock` + `Duration`
