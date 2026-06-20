# Logging Quality

- **Logging utility extraction** -- Private string formatting helpers (`rectStr`, `pointStr`, `sizeStr`) defined in view files should be moved to a shared `LoggingExtensions.swift` file as `internal` functions. Avoids duplication across files that need debug logging.
- **Error logging for silent failures** -- Always add `logger.error` before returning `nil` from rendering methods (e.g., `createBitmapContext` returning `nil`). Silent failures are invisible in production.
- **Redundant `privacy: .public`** -- `"\("\(value)", privacy: .public)"` has no effect — the outer string interpolation swallows the OSLog privacy annotation. Use `"\(value)"` directly or `"\(value, privacy: .public)"` at the top level.
