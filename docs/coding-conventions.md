# Coding conventions

- **Swift 6.0, strict concurrency.** All public types in `SVGCore` are `Equatable + Sendable`. Reach for `@preconcurrency import CoreGraphics` if a `CG*` type otherwise blocks `Sendable` conformance (already done in `SVGRenderer`).
- **Value types by default.** Reference types only when a real identity / lifetime requirement exists (e.g. backing `CGImage`).
- **No force unwraps in library code.** Optional propagation or explicit error throwing only. Tests may force-unwrap for brevity.
- **Comments.** Add a one-line comment only when the *why* is non-obvious (a hidden invariant, a workaround, a subtle constraint). Do not restate the code.
- **Naming.** Public types are `SVG`-prefixed (`SVGRect`, `SVGPaint`). Private helpers are not prefixed.
- **Errors.** Library code throws typed errors (`SVGParseError`, `SVGSnapshotDiffer.DiffError`). Errors carry source location when available.
- **No dependencies.** SVGeeKit's runtime targets have no external SwiftPM dependencies. Test infrastructure stays in-tree (no SnapshotTesting library; we own the diff).
- **MainActor boundaries.** `SVGRasterizer` is `@MainActor` because `ImageRenderer` is. `SVGImageView` is a SwiftUI view (already main-actor-isolated). Everything else should run anywhere.
- **Imports.** Each target's imports are minimal — never re-export through dependencies, except `SVGKit` which explicitly `@_exported import`s the public surface.
- **File layout.** One concept per file. New SVG elements go into `SVGCore/Elements/<Element>.swift` once that directory exists (early-stage files all live at `Sources/SVGCore/` root).
