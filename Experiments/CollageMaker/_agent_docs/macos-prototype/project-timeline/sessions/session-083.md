# Arch Review Phase 3 Architecture — Session 83

**Date:** 2026-06-04
**Plan:** `2026-06-04-architectural-review-fixes.md` Phase 3 (2 items, 1 deferred)

## Context

Implemented Phase 3 of the architectural review fixes plan — medium-term architecture items targeting Combine→Observation migration and view-layer business logic extraction.

## Changes

### 3.1 S-1: Convert GestureCoordinator to @Observable

**GestureCoordinator.swift** — Replaced `ObservableObject` + 9 `@Published` properties with `@Observable`. Removed `import Combine` and `import SwiftUI`, added `import Foundation` and `import Observation`.

**CollageEditorView.swift** — Changed `@StateObject private var gestureCoordinator` to `@State private var gestureCoordinator`. The `@Observable` macro + `@State` pairing provides structural observation without Combine boilerplate.

### 3.2.1 W-6: Extract TitleDragHandler

**Views/TitleDragHandler.swift** (new) — `@MainActor struct TitleDragHandler` encapsulates title hit testing (`hitTest()` → `TitleHitResult`), drag offset computation, drag position calculation, and resize width computation. Added `enum TitleHitResult: Equatable` (`.none`, `.drag`, `.resize(TitleResizeEdge)`).

**CollageEditorView.swift** — Replaced ~35 lines of inline coordinate math in the title drag `DragGesture.onChanged` with `TitleDragHandler` calls. Replaced ~15 lines of inline hit detection in the panel swap `DragGesture` with a single `handler.hitTest() != .none` check. Removed module-level `resizeHandleWidth` constant. Added `Equatable` conformance to `TitleResizeEdge`.

### 3.2.2 W-6: Extract DropHandler

**Services/DropHandler.swift** (new) — `struct DropHandler` encapsulates `NSItemProvider` URL extraction, file type validation, and error logging. Uses `withTaskGroup` for concurrent provider loading and `withCheckedContinuation` to bridge `NSItemProvider.loadItem` callback API to async/await.

**ContentView.swift** — Replaced ~55-line inline `handleDrop` method with 3-line `DropHandler` call. Removed `imageTypes` property.

### 3.3 W-4: CollageAssembler sub-renderer injection — Deferred

As planned. The existing protocol hierarchy already supports granular mocking. The monolith is well-organized at ~428 lines.

## Build Status

**BUILD SUCCEEDED** — Zero warnings. App launches successfully.

**diff-review**: No issues found. Noted `@MainActor` on `TitleDragHandler` is technically redundant (value-type struct with no state, only called from main-actor closures) but harmless.

## Files Changed

- `Views/GestureCoordinator.swift` — `@Observable` migration, removed Combine
- `Views/TitleDragHandler.swift` — New file, title drag/resize logic
- `Views/CollageEditorView.swift` — TitleDragHandler integration, `@State` for GestureCoordinator, `Equatable` on `TitleResizeEdge`
- `Services/DropHandler.swift` — New file, drop handling extraction
- `ContentView.swift` — DropHandler integration, removed inline drop logic
