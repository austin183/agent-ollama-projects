# @Observable didSet Init Guard — Learnings 2026-05-25

**Purpose:** Document the `isInitializing` guard pattern needed when `@Observable` properties with `didSet` side effects are populated from persistence during initialization.

---

## The Problem

When `@Observable` properties have `didSet` observers that register undo, persist to `UserDefaults`, or trigger side effects (like `updatePreview()`), assigning those properties during `init` fires the `didSet` — causing unwanted undo registrations, redundant persistence writes, and preview renders before the object is fully constructed.

```swift
// BEFORE — didSet fires during init assignment
var gutter: CGFloat = CGFloat(UserDefaults.standard.double(forKey: "gutter")) {
    didSet {
        undoManager.registerUndo(withTarget: self) { ... }  // fires during init!
        UserDefaults.standard.set(Double(gutter), forKey: "gutter")  // redundant write!
        regenerateLayout()  // runs before object is ready!
    }
}

init() {
    // gutter's default value above already read from UserDefaults,
    // but if you re-assign in init body, didSet fires again
    self.gutter = someComputedValue  // triggers undo + persist + side effect
}
```

## The Fix: `isInitializing` Guard

A private `isInitializing` flag, set to `true` before property assignments in `init` and `false` after, with `guard !isInitializing else { return }` at the top of each `didSet`:

```swift
private var isInitializing = false

var gutter: CGFloat = 0 {
    didSet {
        guard !isInitializing else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.gutter = oldValue
        }
        undoManager.setActionName("Change Gutter")
        persistence.save(self)
        regenerateLayout()
    }
}

init() {
    isInitializing = true
    let bundle = persistence.load()
    self.gutter = bundle.gutter  // didSet fires but returns immediately
    self.layoutStyle = bundle.layoutStyle
    // ... all 13 properties ...
    isInitializing = false
}
```

## Why This Pattern

- **Zero undo entries at launch** — undo stack starts clean, no spurious entries from initialization
- **No redundant persistence** — `save(self)` during init would write values that are already in UserDefaults
- **No premature side effects** — `updatePreview()` or `regenerateLayout()` won't run before panels/images are set up
- **Safe for undo replay** — when undo restores an old value, `isInitializing` is `false`, so `didSet` runs normally (re-persisting the old value, which is correct)

## Related: `@MainActor` Init Default Parameter Trap

When the persistence class is `@MainActor`, you cannot use it as a default parameter value:

```swift
// DOES NOT COMPILE — init is isolated to MainActor,
// default params are evaluated in a synchronous nonisolated context
init(persistence: UserDefaultsPersistence = UserDefaultsPersistence()) { }
```

**Fix:** Use init overloads instead:

```swift
convenience init() {
    self.init(persistence: UserDefaultsPersistence())
}

convenience init(saliencyAnalyzer: S, assembler: A) {
    self.init(saliencyAnalyzer: s, assembler: a, persistence: UserDefaultsPersistence())
}

init(saliencyAnalyzer: S, assembler: A, persistence: UserDefaultsPersistence) {
    // ...
}
```

---

**Status:** Closed
**Follow-up:** None — pattern is established and working
