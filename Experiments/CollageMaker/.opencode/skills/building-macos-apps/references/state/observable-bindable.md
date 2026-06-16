# @Observable and @Bindable — macOS 14+ State Management

`@Observable` is a Swift 5.9+ macro that replaces `ObservableObject` + `@Published`. It synthesizes observation code at compile time for **stored properties only**.

## @Observable Class

```swift
@Observable
@MainActor
final class CollageViewModel {
    var title: String = ""
    var panels: [Panel] = []
    var previewImage: NSImage?
}
```

**Key differences from ObservableObject:**
- No `@Published` needed — all `var` stored properties are automatically observed
- No `objectWillChange` publisher
- Use `@Bindable` in views, not `@ObservedObject`/`@EnvironmentObject`

## @Bindable in Views

Views consuming an `@Observable` class **must** use `@Bindable var`. A plain `let` parameter will render once and never update.

```swift
struct ContentView: View {
    @Bindable var viewModel: CollageViewModel  // Correct — SwiftUI auto-tracks all property changes

    var body: some View {
        TextField("Title", text: $viewModel.title)
        Image(nsImage: viewModel.previewImage ?? NSImage())
    }
}
```

```swift
// WRONG — stale after first render
struct ContentView: View {
    let viewModel: CollageViewModel  // SwiftUI does NOT set up observation

    var body: some View {
        TextField("Title", text: $viewModel.title)  // Binding won't work
    }
}
```

## Persisting Properties: Stored + didSet

`@Observable` **cannot track computed properties**. A computed property with `get`/`set` will persist correctly but **never triggers SwiftUI re-renders**.

### The Pattern

Convert `UserDefaults`-backed computed properties to stored properties with `didSet`:

```swift
@Observable
@MainActor
final class CollageViewModel {
    // Correct — triggers re-render AND persists
    var title: String = UserDefaults.standard.string(forKey: "title") ?? "" {
        didSet { UserDefaults.standard.set(title, forKey: "title") }
    }

    var backgroundStyle: BackgroundStyle = BackgroundStyle(rawValue: UserDefaults.standard.string(forKey: "bgStyle") ?? "") ?? .solid {
        didSet { UserDefaults.standard.set(backgroundStyle.rawValue, forKey: "bgStyle") }
    }
}
```

```swift
// WRONG — persists but NEVER triggers re-render
@Observable
@MainActor
final class CollageViewModel {
    var backgroundStyle: BackgroundStyle {
        get { BackgroundStyle(rawValue: UserDefaults.standard.string(forKey: "bgStyle") ?? "") ?? .solid }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "bgStyle") }
    }
}
```

### Property Type Comparison

| Property Type | Triggers Re-render? | Persistable? |
|---|---|---|
| Stored (`var x = value`) | Yes | No (in-memory only) |
| Stored + `didSet` | Yes | Yes (write to disk in `didSet`) |
| Computed (`get`/`set`) | **No** | Yes (but invisible to SwiftUI) |

### UserDefaults Typed Getter Defaults Trap

`UserDefaults.double(forKey:)`, `.integer(forKey:)`, and `.bool(forKey:)` return the type's **zero value** (`0.0`, `0`, `false`) for missing keys — not `nil`. This causes silent wrong defaults (e.g., opacity initializing to `0` making an image invisible).

| Method | Missing Key Returns | Safe? |
|---|---|---|
| `string(forKey:)` | `nil` | Safe — use `?? default` |
| `data(forKey:)` | `nil` | Safe — use `?? default` |
| `double(forKey:)` | `0.0` | **Unsafe** — check `object(forKey:)` first |
| `integer(forKey:)` | `0` | **Unsafe** — check `object(forKey:)` first |
| `bool(forKey:)` | `false` | **Unsafe** — check `object(forKey:)` first |

**Safe default pattern:**
```swift
var backgroundOpacity: Double = {
    if UserDefaults.standard.object(forKey: "bgOpacity") != nil {
        return UserDefaults.standard.double(forKey: "bgOpacity")
    }
    return 1.0  // intentional default, not 0.0
}() {
    didSet { UserDefaults.standard.set(backgroundOpacity, forKey: "bgOpacity") }
}
```

### Color Persistence Helper

Extract `saveColor`/`loadColor` methods to avoid repeating `NSKeyedArchiver` boilerplate:

```swift
@Observable
@MainActor
final class CollageViewModel {
    var backgroundColor: NSColor = loadColor("bgColor", default: .white) {
        didSet { saveColor(backgroundColor, key: "bgColor") }
    }

    private func saveColor(_ color: NSColor, key: String) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadColor(_ key: String, default: NSColor) -> NSColor {
        guard let data = UserDefaults.standard.data(forKey: key),
              let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) else {
            return `default`
        }
        return color
    }
}
```

## Side Effects with didSet

When a property change requires a side effect (e.g., regenerating preview), call it in `didSet`:

**Critical rule: `didSet` is the single source of side effects.** Every stored property that affects a rendered output (preview, layout, export) must call its side effect method in `didSet`. Relying on `.onChange` in views is fragile — SwiftUI may recreate the view struct, losing the `.onChange` tracker. The ViewModel owns the trigger logic.

**Audit checklist:** For each property, ask "Does this affect the rendered preview?" If yes, `didSet` must call `updatePreview()` (or equivalent). Missing a single `updatePreview()` call means the UI control works locally but the preview stays stale.

```swift
@Observable
@MainActor
final class CollageViewModel {
    var gutter: Double = 10 {
        didSet { updatePreview() }
    }

    var previewImage: NSImage?

    func updatePreview() {
        Task.detached { [weak self] in
            guard let self, !Task.isCancelled else { return }
            // ... heavy rendering ...
            Task { @MainActor [preview = result] in
                self?.previewImage = preview
            }
        }
    }
}
```

## @Bindable Nested Struct Mutations Bypass didSet

When using `@Bindable` bindings to nested struct properties, SwiftUI's observation system may handle the mutation through `withMutation` without invoking the parent property's setter. This means `didSet` observers don't fire for all mutation paths.

**Problem:**
```swift
@Observable class CollageViewModel {
    var titleStyle: TitleStyle = .default {
        didSet {
            // May NOT fire when binding mutates a nested property
            updatePreview()
        }
    }
}

struct ExportPanel: View {
    @Bindable var viewModel: CollageViewModel
    var body: some View {
        NSColorPickerView(color: $viewModel.titleStyle.backgroundColor)  // bypasses didSet
    }
}
```

**Fix — Explicit setter methods:**
```swift
@Observable class CollageViewModel {
    var titleStyle: TitleStyle = .default

    func setTitleBackgroundColor(_ color: NSColor) {
        titleStyle.backgroundColor = color
        updatePreview()
        debouncedSave()
    }
}

struct ExportPanel: View {
    @Bindable var viewModel: CollageViewModel
    var body: some View {
        NSColorPickerView(
            color: Binding(
                get: { viewModel.titleStyle.backgroundColor },
                set: { viewModel.setTitleBackgroundColor($0) }
            )
        )
    }
}
```

**Diagnostic clue:** If a binding "works" (the value changes in the model) but side effects don't fire, check whether the binding targets a nested property of a struct and whether the side effects live in the parent property's `didSet`.

## Initialization Guard for didSet Side Effects

When `@Observable` properties have `didSet` observers that register undo, persist to `UserDefaults`, or trigger side effects (like `updatePreview()`), assigning those properties during `init` fires the `didSet` — causing unwanted undo registrations, redundant persistence writes, and premature side effects before the object is fully constructed.

**Fix: `isInitializing` guard**

```swift
@Observable
@MainActor
final class CollageViewModel {
    private var isInitializing = false

    var gutter: CGFloat = 0 {
        didSet {
            guard !isInitializing else { return }
            undoManager.registerUndo(withTarget: self) { target in
                target.gutter = oldValue
            }
            persistence.save(self)
            regenerateLayout()
        }
    }

    init(persistence: Persistence) {
        isInitializing = true
        let bundle = persistence.load()
        self.gutter = bundle.gutter       // didSet fires but returns immediately
        self.layoutStyle = bundle.layoutStyle
        // ... all properties ...
        isInitializing = false
    }
}
```

**Why this pattern:**
- Zero undo entries at launch — undo stack starts clean
- No redundant persistence — `save(self)` during init writes values already in `UserDefaults`
- No premature side effects — `updatePreview()` won't run before panels/images are set up
- Safe for undo replay — when undo restores a value, `isInitializing` is `false`, so `didSet` runs normally

## Circular Init — self Needed as Dependency

When a class creates a sub-object that stores `self` (e.g., as a protocol target), Swift blocks the init: all stored properties must be set before `self` exists, but the sub-object needs `self` to construct.

**Problem:**
```swift
@Observable final class CollageViewModel {
    var coordinator: ImageCoordinator

    init() {
        self.coordinator = ImageCoordinator(target: self) // ERROR: self used before init
    }
}
```

**Fix: IUO on the dependency, not the owner** — put the IUO on the sub-object's back-reference, assign it after the owner's init completes:

```swift
final class ImageCoordinator {
    var target: ImageCoordinationTarget!  // IUO here, not on the owner

    init(imageLibrary: ImageLibrary) {
        self.imageLibrary = imageLibrary
        // No target parameter
    }
}

@Observable final class CollageViewModel {
    var coordinator: ImageCoordinator  // non-optional, safe

    init() {
        self.coordinator = ImageCoordinator(imageLibrary: library)
        coordinator.target = self  // post-init assignment — safe, immediate
    }
}
```

**Why this is preferred over IUO on the owner:** `var coordinator: ImageCoordinator!` on the owner risks a runtime crash if any code path accesses it before init completes. Placing the IUO on the dependency confines the risk to a single, immediately-set property.

**When to use:** The sub-object stores `self` as a protocol reference (DIP), and you want the owner property to be non-optional.

When a dependency class is `@MainActor`, you cannot use it as a default parameter value in `init`:

```swift
// DOES NOT COMPILE — default params are evaluated in a nonisolated context
init(persistence: Persistence = UserDefaultsPersistence()) { }
```

**Fix: Use init overloads:**

```swift
convenience init() {
    self.init(persistence: UserDefaultsPersistence())
}

init(persistence: Persistence) {
    // ...
}
```

## View Binding Rules

| Declaration | Observes @Observable? | Safe? |
|---|---|---|
| `@Bindable var viewModel: MyViewModel` | Yes | Yes |
| `let viewModel: MyViewModel` | **No** | No — stale after first render |
| `@StateObject` + `@ObservedObject` | N/A (legacy) | Use for `ObservableObject` only |

## Passing @Observable to Child Views

```swift
// Root-owned with @State
struct ParentView: View {
    @State private var viewModel = CollageViewModel()

    var body: some View {
        ChildView(viewModel: viewModel)  // Pass as value — child uses @Bindable
    }
}

// Child uses @Bindable
struct ChildView: View {
    @Bindable var viewModel: CollageViewModel

    var body: some View {
        Slider(value: $viewModel.gutter, in: 0...50)
    }
}
```

## Diagnosing @Observable Issues

If a binding "works locally" (TextField shows typed text, Slider moves) but dependent views don't update:

1. **Check if the ViewModel property is computed instead of stored** — computed properties are invisible to `@Observable`
2. **Check if the consuming view uses `@Bindable`** — `let` will not observe changes
3. **Check if side effects are called in `didSet`** — `updatePreview()` won't fire from a computed setter

### Debugging: Verify Observation

Add a `print()` in `didSet` to confirm the property is stored and being assigned:

```swift
var title: String = "" {
    didSet { print("title changed: \(title)") }  // Should print on every change
}
```

If the print doesn't fire, the property is either computed or being mutated in-place.

## @Observable Delegation Chains

When a ViewModel delegates a property to a sub-manager via a computed property, SwiftUI observation breaks. `@Observable` only tracks stored properties on the observed instance — it cannot see through computed properties into another object.

### The Problem

```swift
@Observable @MainActor final class CollageViewModel {
    let cropManager = CropManager()

    // Computed delegation — INVISIBLE to SwiftUI observation on CollageViewModel
    var cropMap: [UUID: CropInfo] {
        get { cropManager.cropMap }
        set { cropManager.cropMap = newValue }
    }
}

// View reads through computed property — NEVER receives updates
struct MyView: View {
    @Bindable var viewModel: CollageViewModel
    var body: some View {
        ForEach(viewModel.panels) { panel in
            let crop = viewModel.cropMap[panel.id]  // Won't update on cropManager mutations
        }
    }
}
```

Root cause: `viewModel.cropMap` is a function call from SwiftUI's perspective. It observes `CollageViewModel`, but `cropManager.cropMap` is a different object that `CollageViewModel`'s observation system doesn't know about.

### The Fix (Both Parts Required)

1. **Make the delegate `@Observable`** — so mutations emit observation events
2. **Have the view read the delegate directly** — so SwiftUI registers the delegate as an observation dependency

```swift
@Observable @MainActor final class CropManager {  // Part 1: @Observable
    var cropMap: [UUID: CropInfo] = [:]
}

@Observable @MainActor final class CollageViewModel {
    let cropManager = CropManager()

    var cropMap: [UUID: CropInfo] {  // Convenience accessor for non-view code
        get { cropManager.cropMap }
        set { cropManager.cropMap = newValue }
    }
}

// Part 2: View reads delegate directly
struct MyView: View {
    @Bindable var viewModel: CollageViewModel
    var body: some View {
        ForEach(viewModel.panels) { panel in
            let crop = viewModel.cropManager.cropMap[panel.id]  // Updates correctly
        }
    }
}
```

### Delegation Chain Rules

| Scenario | Observation Works? | Fix |
|---|---|---|
| Stored property on `@Observable` class | Yes | None needed |
| Computed property reading another object | **No** | Make delegate `@Observable` + read delegate directly in view |
| View reads through computed property (`vm.cropMap`) | **No** | Read delegate directly (`vm.cropManager.cropMap`) |
| View reads delegate directly but delegate is plain class | **No** | Add `@Observable` to delegate |

### Diagnostic Clues

If a view updates for some state changes but not others after refactoring:
1. Check if any properties changed from stored to computed
2. Check if the delegate object is `@Observable`
3. Check if the view reads the delegate directly (not through the computed property)
4. The symptom is typically partial: stored properties still update, delegated properties don't

### Version Counter Alternative

The direct delegate read fix works but exposes the delegate's internal structure to the view. When you want to preserve the delegation abstraction, use a **version counter**:

```swift
@Observable @MainActor final class CollageViewModel {
    let previewManager = PreviewManager()  // @Observable
    private var titleImageVersion = 0

    var titleImage: NSImage? {
        get {
            let _ = titleImageVersion  // establishes observation dependency
            return previewManager.titleImage
        }
        set { previewManager.titleImage = newValue }
    }

    func updateTitleImage() {
        titleImageVersion += 1  // forces observation re-tracking
        previewManager.updateTitleImage(...)
    }
}
```

The `let _ = titleImageVersion` read in the getter registers `titleImageVersion` as an observation dependency. Incrementing it triggers the observation system to re-evaluate any view that reads `viewModel.titleImage`.

| Approach | Pros | Cons |
|---|---|---|
| Version counter | Preserves abstraction, view reads single property | Requires manual increment at every mutation site |
| Direct delegate read | Automatic, no manual increment | Exposes delegate structure to view, tighter coupling |

### Throttling Version Counter Increments

When a version counter drives view re-evaluation during high-rate input (gestures firing 60-120x/sec), throttle the increments to bound SwiftUI body re-evaluations. Use `ContinuousClock` + `Duration` — **never** `mach_absolute_time()` (returns ticks, not nanoseconds):

```swift
private var lastNotifyTime: ContinuousClock.Instant = .now
private let notifyInterval: Duration = .milliseconds(30) // ~33fps

private func throttledNotify() {
    let now = ContinuousClock.now
    if now - lastNotifyTime >= notifyInterval {
        lastNotifyTime = now
        titleImageVersion += 1
    }
}
```

Throttle (not debounce) is the right choice here — throttle fires immediately on the first event and skips until the interval elapses, giving live feedback during active gestures. Debounce defers until after a quiet period, leaving the view stale during the gesture.

**Gesture-end notification gap:** When per-frame notification is deferred to a debounce task, gesture-end paths (`onEnded`, `finish*`) that cancel the debounce task will never fire the notification. Always add explicit notification in gesture-end methods.

### Eliminating Dual State — Verification Checklist

When unifying dual state (e.g., removing a shadow copy from ViewModel):
1. Remove the stored property from the secondary owner
2. Add a computed property that delegates to the primary owner
3. Grep for `= primaryOwner.property` to find all manual sync lines
4. Remove each sync line
5. Verify grep returns zero matches
6. Build and run — check for observation gaps (views that stop updating)
7. If observation gaps appear: ensure delegate is `@Observable` + views read delegate directly

## Migration from ObservableObject

When migrating from `ObservableObject` to `@Observable`:

| ObservableObject Pattern | @Observable Equivalent |
|---|---|
| `class VM: ObservableObject` | `@Observable class VM` |
| `@Published var x: Int` | `var x: Int` |
| `@ObservedObject var vm: VM` | `@Bindable var vm: VM` |
| `@EnvironmentObject var vm: VM` | `@Environment var vm: VM` |
| `.onChange(of: vm.x)` | `.onChange(of: vm.x)` (same API) |
| `.onReceive(vm.$x.dropFirst())` | Not needed — `@Bindable` tracks automatically |
| `objectWillChange.send()` | `vm._observation.send()` (rarely needed) |

**Note:** `@Observable` and `ObservableObject` can coexist in the same codebase. Migrate incrementally.

## Summary Rules

1. **All `@Observable` properties that drive UI must be stored** — computed properties are invisible to SwiftUI
2. **Use `didSet` for persistence and side effects** — this is the only way to combine observation with `UserDefaults`
3. **Views must use `@Bindable var`** — `let` will not observe changes
4. **Root views own `@Observable` with `@State`** — children receive via `@Bindable`
5. **Extract color persistence helpers** — `saveColor`/`loadColor` reduce boilerplate for `NSColor` properties
6. **Guard `didSet` during initialization** — use `isInitializing` flag to prevent undo registrations, redundant persistence, and premature side effects when loading saved state in `init`
7. **No `@MainActor` default params in init** — use init overloads instead of `init(dep: MainActorDep = MainActorDep())`
8. **`@State` UUID cache staleness** — When `@State` caches `[UUID: Value]` and the source collection regenerates with new UUIDs, the cache is stale for one render cycle. Compute on-the-fly in `GeometryReader` closure for correctness-critical paths (hit-testing, overlays). See "@State Cache Staleness with UUID Collections" above.
9. **@Observable delegation chains** — Computed properties that delegate to sub-managers break SwiftUI observation. Fix: make the delegate `@Observable` AND have views read the delegate directly (e.g., `vm.cropManager.cropMap`, not `vm.cropMap`). Both parts are required. Alternatively, use a **version counter** — a private stored `Int` read in the computed getter and incremented at mutation sites — to preserve the delegation abstraction.
10. **@Bindable nested struct mutations bypass `didSet`** — Bindings to nested struct properties (e.g., `$viewModel.titleStyle.backgroundColor`) may use `withMutation` internally, skipping the parent property's `didSet`. Use explicit setter methods with manual `Binding(get:set:)` when side effects are required.
11. **Multi-field cache invalidation** — Every code path that clears a multi-field cache (result + key + input) must clear ALL fields. Leaving key fields stale causes the cache to return stale `nil` on restore. Prefer the defensive guard pattern: `if let cachedResult = cachedResult, ...` — if the result is `nil`, the cache always misses.
12. **Gesture hot path caching** — Move expensive computation (CoreText, image processing) to a cached ViewModel method. Keep cheap math in a computed property that reads the cache. Position changes during drag recompute the cheap math but reuse the cached expensive result.

## Extracting Managers from @Observable ViewModels

When a ViewModel grows beyond simple state + side effects, extract a dedicated `@Observable` manager for a focused subsystem.

### When to Extract

| Signal | Threshold |
|---|---|
| Related async tasks | 3+ |
| Related stored properties | 3+ |
| Method responsibility | Methods doing both orchestration AND rendering |
| Test complexity | Tests need to mock rendering separately from business logic |

### Pure Accumulator Pattern

Prefer managers that only accumulate and report, leaving domain logic to the ViewModel:

```
Tightly coupled: Manager accepts closures capturing domain state
Moderately coupled: Manager returns events, caller handles logic
Pure accumulator: Manager only stores raw data, caller owns all logic
```

```swift
// Pure accumulator — knows nothing about crops, panels, or images
@Observable @MainActor final class ScrollPanManager {
    var activePanelId: UUID?
    var accumulator: CGSize = .zero

    func scroll(delta: CGSize, sensitivity: Double) {
        accumulator.width += delta.width * sensitivity
        accumulator.height += delta.height * sensitivity
    }
}

// ViewModel owns crop computation, commit timing, and preview scheduling
@Observable @MainActor final class CollageViewModel {
    let scrollPanManager = ScrollPanManager()

    func handleScroll(delta: CGSize) {
        scrollPanManager.scroll(delta: delta, sensitivity: sensitivity)
        applyCropFrom(scrollPanManager.accumulator, panelId: scrollPanManager.activePanelId)
        schedulePreview()
    }
}
```

**Why:** Inverting the dependency (manager knows nothing about domain) makes the manager testable in isolation and reusable across different ViewModels.

## Multi-Field Cache Invalidation

When a cache stores multiple fields (result + key + input), clearing only the result while leaving key fields stale causes the cache to return stale `nil` on restore.

**Bug scenario:**
```swift
private var cachedBounds: TitleBoundsCache?
private var cachedKey: LayoutKey?
private var cachedString: NSAttributedString?

private func ensureBounds() -> TitleBoundsCache? {
    guard !titleAttrString.string.isEmpty else {
        cachedBounds = nil  // BUG: leaves cachedKey + cachedString stale
        return nil
    }
    if let cachedStr = cachedString, cachedStr.isEqual(titleAttrString),
       cachedKey == currentKey {
        return cachedBounds  // returns stale nil!
    }
    // ... compute and cache ...
}
```

**Trace:** Title set → cache populated. Title cleared → only `cachedBounds = nil`. Title restored → key/string match → returns `nil`.

**Fix — Clear all fields atomically:**
```swift
guard !titleAttrString.string.isEmpty else {
    cachedBounds = nil
    cachedString = nil
    cachedKey = nil
    return nil
}
```

**Defensive alternative — Guard the cached result:**
```swift
if let cachedBounds = cachedBounds,
   let cachedStr = cachedString, cachedStr.isEqual(titleAttrString),
   cachedKey == currentKey {
    return cachedBounds
}
```

This catches stale `nil` regardless of whether all fields were cleared — if `cachedBounds` is `nil`, the cache always misses and recomputes. **Prefer this pattern.**

## Computed Property Caching for Gesture Hot Paths

`@Observable` has no path-based granularity for computed properties — any tracked property change triggers full view body re-evaluation. Move expensive computation (CoreText layout, image processing) to a cached ViewModel method, and keep cheap math in a computed property.

**Pattern:**
```swift
// ViewModel — caches expensive computation
private var cachedResult: ExpensiveType?
private var cachedKey: CacheKey?

func ensureResult() -> ExpensiveType? {
    guard !inputString.string.isEmpty else {
        cachedResult = nil
        cachedKey = nil
        return nil
    }
    if cachedKey == currentKey { return cachedResult }
    cachedResult = computeExpensive(currentKey)
    cachedKey = currentKey
    return cachedResult
}

var cachedFrame: CGRect? {
    guard let result = ensureResult() else { return nil }
    // Cheap math using cached result + current position
    return computeFrame(from: result, position: currentPosition)
}

// View — thin delegator
private var titleFrame: CGRect? { viewModel.cachedFrame }
```

**Key insight:** Position changes during drag recompute the `CGRect` (cheap math) but reuse the cached expensive result. Layout/style changes invalidate the cache and trigger fresh computation.

## @State Cache Staleness with UUID Collections

When a view caches derived data in `@State` keyed by UUIDs (e.g., `[UUID: CGRect]` for panel frames), and the source collection can be regenerated with **new UUIDs**, the cache becomes stale for one render cycle. The `.onChange` that updates the cache fires *after* the first re-render body evaluation.

**The gap:**
1. ViewModel updates collection with new UUIDs
2. SwiftUI re-renders body — `@State` cache still holds old UUIDs
3. `.onChange` fires and updates cache
4. SwiftUI re-renders again (now in sync)

Steps 2–3 is the gap. Anything reading the cache during the first render — hit-testing in gesture closures, selected-outline overlays, `ForEach` conditional rendering — will fail or show stale state.

**Fix: Compute on-the-fly in GeometryReader closure**

```swift
GeometryReader { geometry in
    let panelFrames = viewModel.panels.reduce(into: [UUID: CGRect]()) { dict, panel in
        dict[panel.id] = canvasToPreviewFrame(panel.frame, in: geometry.size)
    }
    // panelFrames is always fresh — no staleness gap
}
```

**When @State caching is still valid:** For collections whose UUIDs are stable across updates (e.g., panels that persist across layout changes, or frames that only change during window resize). The staleness gap only occurs when UUIDs are replaced.

**Performance trade-off:** On-the-fly computation adds O(n) work per render. For typical collections (≤20 items), this is negligible. For large collections, keep the `@State` cache for `ForEach` rendering but compute fresh values inside gesture handlers where correctness matters.

## Pitfalls

- **`@Observable` computed property** — appears to work (value persists) but **never triggers re-render**. Convert to stored property with `didSet` for persistence
- **`let viewModel: MyObservableVM`** — view renders once with initial state and never updates. Must use `@Bindable var`
- **Binding "works locally" but dependent views stale** — TextField shows text, Slider moves, but preview doesn't update. Check: (a) property is computed not stored, (b) view uses `let` not `@Bindable`, (c) `updatePreview()` not called in `didSet`
- **UserDefaults typed getters return zero for missing keys** — `UserDefaults.double(forKey:)`, `.integer(forKey:)`, and `.bool(forKey:)` return `0`, `0`, and `false` respectively when the key doesn't exist (unlike `.string(forKey:)` and `.data(forKey:)` which return `nil`). This causes silent wrong defaults. Safe pattern: check `object(forKey:)` first, then call the typed getter only if the key exists.
- **`didSet` fires during `init`** — Assigning properties in `init` triggers `didSet`, causing spurious undo entries, redundant `UserDefaults` writes, and premature side effects. Use an `isInitializing` guard in each `didSet` to skip side effects during initialization.
- **`@MainActor` default param in `init`** — `init(dep: SomeMainActorClass = SomeMainActorClass())` won't compile. Use `convenience init()` overloads instead.
- **@Observable delegation chain** — A computed property on an `@Observable` class that delegates to a sub-manager (e.g., `var cropMap { cropManager.cropMap }`) breaks observation. SwiftUI only tracks stored properties on the observed instance. Fix requires BOTH: (a) make the delegate `@Observable`, (b) views read `vm.cropManager.cropMap` directly, not through the computed property. Alternative: use a **version counter** — private `Int` read in the computed getter, incremented at mutation sites — to preserve abstraction.
- **@Bindable nested struct mutations bypass `didSet`** — Bindings like `$viewModel.titleStyle.backgroundColor` may use `withMutation` internally, skipping the parent property's `didSet`. Side effects (e.g., `updatePreview()`) won't fire. Fix: use explicit setter methods with `Binding(get:set:)`.
- **Multi-field cache partial clear** — Clearing only the result field of a multi-field cache (result + key + input) leaves keys stale. On restore, the keys match and the cache returns stale `nil`. Fix: clear ALL fields, or use defensive guard (`if let cachedResult = cachedResult, ...`).
- **Expensive computed in gesture hot path** — `@Observable` has no path-based granularity — any tracked property change triggers full body re-evaluation. During 33fps gesture loops, expensive computation in computed properties causes hitching. Fix: cache expensive work in a ViewModel method, expose cheap math via computed property.
