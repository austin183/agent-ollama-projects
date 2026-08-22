# Actor `nonisolated` Method — Genuine Task Parallelism

**Date:** 2026-06-08
**Context:** Post-round-99 review fix CONC-01, `SaliencyAnalyzer`

## Problem

An actor method called via `withThrowingTaskGroup` appears concurrent but is actually serialized. Each task's `await self.method()` must hop through the actor's single-threaded executor, eliminating all parallelism.

```swift
actor MyAnalyzer {
    func analyze(_ input: Input) async throws -> Result {
        // ... pure computation, no self access ...
    }

    func analyzeAll(_ inputs: [Input]) async throws -> [Result] {
        try await withThrowingTaskGroup(of: (Int, Result).self) { group in
            for (i, input) in inputs.enumerated() {
                group.addTask {
                    let result = try await self.analyze(input) // ACTOR HOP — serialized!
                    return (i, result)
                }
            }
            // ...
        }
    }
}
```

## Root Cause

Actor isolation guarantees that `self.method()` executes on the actor's executor. Even though `withThrowingTaskGroup` creates multiple concurrent tasks, each `await self.analyze(...)` serializes through the actor's single queue.

## Fix

Mark the method `nonisolated` when it accesses no actor-isolated state:

```swift
actor MyAnalyzer {
    nonisolated func analyze(_ input: Input) async throws -> Result {
        // Only local variables, external APIs, module-level constants
    }
    // analyzeAll now gets genuine parallelism
}
```

## Verification Checklist

Before marking an actor method `nonisolated`, verify:
1. **No `self.` access** to actor-stored properties
2. **Only local variables** and function parameters
3. **Module-level constants** (e.g., `private let logger`) are fine — not actor-isolated
4. **External async APIs** (Vision, URLSession, etc.) are fine — not actor-isolated
5. **Protocol conformance** — the protocol must not require actor isolation

## When This Applies

- Pure computation methods on actors that only exist to satisfy protocol conformance
- Batch processing actors that use `withThrowingTaskGroup` internally
- Any actor method that could equally be a standalone `func` outside the actor

## Anti-Pattern

Placing pure functions inside an actor solely for protocol conformance, then expecting `withThrowingTaskGroup` to provide parallelism. The actor executor will serialize everything unless the method is `nonisolated`.
