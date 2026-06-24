# CollageMaker — Agent Instructions

# Things to Avoid
- **Do not ask agents to return full file contents** - Agents should return clues and references, but it is more efficient to read files directly than to ask an agent to read it and return its contents.

# Our Home Folder
- **Our home folder is `~/workspace/agent-ollama-projects/Experiments/CollageMaker`** - That is `agent-ollama-projects`.
  - **Tell subagents is it `~/workspace/agent-ollama-projects/Experiments/CollageMaker`, because they often want to go to another folder instead**

## Project at a glance
macOS SwiftUI desktop app that assembles photo collages with Vision-based saliency analysis. Single Xcode project, no SPM or CocoaPods.

- **Xcode project**: `CollageMaker/CollageMaker/CollageMaker.xcodeproj`
- **Scheme**: `CollageMaker`
- **Targets**: `CollageMaker` (app), `CollageMakerTests` (unit), `CollageMakerUITests` (XCUITest)
- **Deployment target**: macOS 26.4, arm64
- **Swift version**: 5.0, Swift 6 language mode

## Build and run

```bash
bash script/build_and_run.sh run          # build and launch
bash script/build_and_run.sh --logs       # launch + tail OSLog
bash script/build_and_run.sh --telemetry  # launch + tail subsystem logs
bash script/build_and_run.sh --verify     # build, launch, exit 0 on success
```

The script kills any running instance before building and locates the `.app` in DerivedData by globbing. See the `building-macos-apps` skill → `references/tooling/build-and-run.md` for script patterns and debugging tips.

## Tests

Unit tests use **Swift Testing** (`@Test`, `@Suite`, `#expect`). UI tests use **XCTest**.
 
```bash
bash script/run_tests.sh
```

Test fixture helpers are in `CollageMakerTests/TestHelpers.swift`. See `CollageViewModelTests.swift` for the mocking pattern. See the `building-macos-apps` skill → `references/testing/testing-patterns.md` for AppKit init, CGImage fixtures, concurrency races, serialization, and diagnostic patterns.

## Architecture

```
CollageMaker/
├── CollageMakerApp.swift      — @main entry, wires ContentView + Settings
├── ContentView.swift          — NavigationSplitView: sidebar / editor / detail
├── Models/                    — data types (ImageItem, ImagePanel, LayoutStyle, CanvasConfig, etc.)
├── ViewModel/
│   ├── CollageViewModel.swift — @Observable, @MainActor, single source of truth
│   └── CropManager.swift      — crop state management
├── Services/
│   ├── SaliencyAnalyzer.swift — actor, Vision VNGenerateAttentionBasedSaliencyImageRequest
│   ├── CollageAssembler.swift — CoreGraphics compositing, protocol CollageAssembly
│   ├── LayoutGenerator.swift  — panel layout math
│   ├── ScrollPanManager.swift — scroll/pan gesture coordination
│   ├── FontMerger.swift       — font merging for export
│   └── TitleMetrics.swift     — title text measurements
└── Views/                     — SwiftUI views (CollageEditorView, ExportPanel, SettingsView, etc.)
```

Key conventions:
- **`@MainActor` + `@Observable`** on `CollageViewModel` — all UI state lives here
- **Services are actors or plain classes behind protocols** — enables mocking in tests
- **All logging uses `OSLog`** with subsystem `austin183.indie.CollageMaker`
- **UserDefaults keys** are centralized in `UserDefaultsPersistence.Keys`
- **Coordinate systems**: Vision (bottom-left, normalized) vs CoreGraphics vs NSImage (top-left). See `building-macos-apps` skill → `references/graphics/coordinate-systems.md`.

## Important gotchas

- **No Swift Package Manager** — all code is in the Xcode project. Do not create `Package.swift`.
- **Code signing is Automatic** — builds work locally without explicit identity configuration.
- **`_agent_docs/learnings/`** contains 30+ session learnings files with hard-won knowledge about SwiftUI gestures, coordinate transforms, undo batching, and more. Read relevant files before making changes in those areas.

## Skill references

The `building-macos-apps` skill provides detailed patterns for:
- **State management**: `@Observable`, `@Bindable`, concurrency — see skill main file
- **Testing**: fixtures, mocks, races, diagnostics — `references/testing/testing-patterns.md`
- **Build and run**: scripts, logging, debugging — `references/tooling/build-and-run.md`
- **Coordinate systems**: Vision/CoreGraphics/NSImage flips, EXIF, fit math — `references/graphics/coordinate-systems.md`
- **Gestures**: targeting, magnification, live preview — `references/gestures/swiftui-gestures.md`
- **Vision framework**: actor isolation, saliency heat maps — `references/graphics/vision-api-details.md`
- **Windowing**: `WindowGroup`, `Settings` scenes — `references/tooling/windowing.md`
