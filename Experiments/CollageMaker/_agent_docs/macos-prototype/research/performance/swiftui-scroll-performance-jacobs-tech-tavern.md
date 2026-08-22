# SwiftUI Scroll Performance — Jacob's Tech Tavern Research

**Date:** 2026-06-21
**Source:** https://blog.jacobstechtavern.com/p/swiftui-scroll-performance-the-120fps
**Author:** Jacob's Tech Tavern
**Context:** Reference research on SwiftUI scroll view performance patterns for infinite feeds

---

## Testing Methodology

- **Device:** iPhone 15 Pro, iOS 18.3.2
- **Mode:** Low Power Mode (intentionally throttled to stress-test performance)
- **Target:** 60fps (16.67ms per frame), tested via Animation Hitches instrument
- **Workload:** 1,000 cells with photos (Lorem Picsum), text, spinner animation, gradient effect

---

## Container Comparison

### VStack (Baseline — Do Not Use)

- **Behavior:** Eagerly loads and renders the entire view hierarchy upfront
- **Result:** Immediate freeze on load, all 1,000 cells laid out simultaneously
- **Memory:** Massive spike that never recovers (all views held in memory)
- **Interaction:** Completely blocked during initial load
- **Verdict:** Unusable for scrolling feeds

### LazyVStack

- **Behavior:** Loads and renders subviews on-demand near the viewport
- **Static cells:** Smooth 60fps, minor frame drops, no hangs
- **Dynamic cells:** Visible degradation with dropped frames and micro-hangs
- **Memory:** Consistent usage, evicts offscreen views since iOS 16+ (was one-directional lazy before)
- **Breaking point:** Frantic scroll indicator dragging causes dynamic height estimation to fail, resulting in wild scroll jumps and memory spikes
- **Caveat:** Programmatic scrolling to off-screen cells requires running all intermediate layout computation, causing performance hits

### List (Recommended)

- **Underlying tech:** UICollectionView with cell recycling
- **Static cells:** Effortless 60fps on Low Power Mode, no hitches
- **Dynamic cells:** Few one-to-two frame hitches at very fast scroll speeds (better than LazyVStack)
- **Memory:** Initial spike on load, then consistent and smooth throughout 1,000-item collection
- **Stability:** Could not be broken under stress testing
- **Trade-off:** Less formatting freedom due to UIKit system defaults underneath

---

## Performance Optimization Techniques

### Image Caching

- `AsyncImage` re-downloads images every time a cell reappears, wasting network I/O
- Libraries: Nuke, Kingfisher, CachedAsyncImage
- Impact: Dramatically snappier feel on second render

### Pagination

- Load 20-100 items initially, fetch more on scroll
- Reduces initial memory allocations and network I/O
- Smaller data source improves SwiftUI diffing speed

### Minimise Redraws

Two strategies:
1. **Minimise dependencies** — Views should have as little `@State`/`@Observable` as possible
2. **Make diffing fast** — Make views `Equatable` with `equatable()` modifier; primitive-only dependencies enable undocumented `memcmp`-style byte comparisons
3. **Debug tool:** `Self._printChanges` for tracking view re-computations in development

### Background Processing

- View bodies are `@MainActor` by default — string interpolation, data filtering all run on main thread
- Offload long-running processing, image transformations, data parsing to background threads
- Watch for `Task` closures that capture main actor context (they run on the thread they're created on)
- No SwiftUI equivalent of UIKit's Texture (background rendering library) exists as of writing

### drawingGroup() (Metal)

- Renders a view as a single pre-rendered GPU texture
- Useful for: complex animations, deep nested hierarchies, CoreImage blend modes
- Trade-off: GPU upload overhead can slow views down — use reactively, not preemptively

---

## Key Takeaways for CollageMaker

1. **Prefer `List` over `LazyVStack`** for any scrollable lists with dynamic content — more stable, better memory behavior
2. **Image caching is essential** — any view that re-renders offscreen images will feel sluggish without it
3. **Minimise view state** — fewer dependencies means fewer re-computations during scroll
4. **Profile before optimizing** — the author's closing advice: "profile your app before you listen to some guy on the internet"
5. **Test on Low Power Mode** — if it scrolls smoothly there, it will be smooth under normal conditions

## Influences

The article credits Thomas Ricouard and Fatbobman for foundational work on SwiftUI scroll performance.
