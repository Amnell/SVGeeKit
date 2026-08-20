# Architecture

```
+-----------+        +------------+        +----------------+        +----------------------+
| .svg data | -----> | SVGParser  | -----> | SVGCore model  | -----> | SVGRenderTree.lower  |
+-----------+        +------------+        +----------------+        +----------------------+
                                                                              |
                                                                              v
                                                            +---------------------------------+
                                                            | [SVGRenderCommand]              |
                                                            +---------------------------------+
                                                                              |
                                                                              v
                                                            +---------------------------------+
                                                            | SVGRendererBackend              |
                                                            |   - SwiftUICanvasRenderer (now) |
                                                            |   - CoreGraphics  (Phase 4)     |
                                                            |   - Metal        (later)        |
                                                            +---------------------------------+
```

## Module contract

### `SVGCore`
- Pure value types: `SVGDocument`, `SVGGroup`, `SVGElement` (enum), `SVGRect`, `SVGTransform`, `SVGPaint*`, `SVGLength`, `SVGColor`.
- **Forbidden:** `Foundation.XMLParser`, any rendering import, `SwiftUI`, `AppKit`, `UIKit`, `ImageIO`.
- Allowed: `CoreGraphics` (for `CGPoint`/`CGRect`/`CGAffineTransform`), `Foundation` value types.
- All types are `Equatable` and `Sendable`.

### `SVGParser`
- Depends on `SVGCore` only.
- Single public entry point: `SVGParser().parse(data:)` / `parse(string:)`.
- Uses `XMLParser` (SAX). New elements are handled inside `SAXDelegate.didStartElement(...)`.
- Reports source-located `SVGParseError`s rather than silently swallowing.
- **CSS styling** is resolved at parse time into `SVGPaintProperties` / `SVGFont` — see `CSSStylesheet.swift` and `mergePaint` / `mergeFont`. Paint cascade (low → high): inherited → `<style>` class rules → inline `style=""` → presentation attributes. No renderer changes needed for basic paint props.

### `SVGRenderer`
- Depends on `SVGCore`. **No SwiftUI/AppKit/UIKit.**
- Defines `SVGRenderCommand` — the backend-neutral primitive set.
- `SVGRenderTree.lower(_ document:)` walks an `SVGDocument` and returns a flat `[SVGRenderCommand]`. Adding a new element type means adding a `case` to `SVGElement` AND a corresponding lowering pass here.
- The renderer protocol stays CG-shaped (paths, transforms, paint, opacity layers, clip stack). Resist adding SwiftUI-specific concepts here.

### `SVGRendererSwiftUI`
- Depends on `SVGCore` + `SVGRenderer`.
- Two surfaces:
  - `SVGImageView: View` — public SwiftUI view; uses `SwiftUICanvasRenderer` for live `Canvas` rendering. Accepts a parsed document, SVG bytes, or a `URL` / `URLRequest` for the document itself (in-document network `href`s remain gated by `SVGResourcePolicy`).
  - `SVGRenderedImage` — rasterizes a document, bytes, or URL to a `CGImage` with `Image` / `UIImage` / `NSImage` accessors. Optional `SVGRenderedImageCache` (shared by default) memos parse + raster by content hash and size.
  - `SVGRasterizer.rasterize(_:pixelSize:scale:)` — returns a `CGImage` via `CGContextRenderer` + `SVGGradientDrawing`. Used by the conformance harness.
- `SwiftUICanvasRenderer` translates each `SVGRenderCommand` to `GraphicsContext` calls.
- `CGContextRenderer` mirrors the same command stream for snapshot output; gradients use sRGB stop interpolation with independent alpha (matching W3C reference PNGs).

### `SVGeeKit`
- Umbrella that re-exports everything an app needs.

### `SVGConformance`
- Depends on `SVGeeKit`. Used by tests *and* by the Viewer app (Phase 2).
- `SVGTestSuiteIndex` enumerates the vendored W3C test directory; tags via filename prefix + `overrides.json`.
- `SVGSnapshotDiffer` does premultiplied-RGBA pixel diffing with tolerance.
- `SVGConformanceRunner` performs `parse → rasterize → diff` and emits a `SVGConformanceRecord` per test.

## Rendering pipeline

1. Parse SVG bytes → `SVGDocument`.
2. Lower the document into `[SVGRenderCommand]` via `SVGRenderTree.lower`. This applies the document-level `viewBox` → intrinsic-size transform once.
3. The renderer backend executes the command stream into its native graphics context (`SwiftUICanvasRenderer` for views, `CGContextRenderer` for snapshots).
4. `SVGRasterizer` renders into a flipped `CGContext` bitmap (top-left origin, premultiplied RGBA).

## Adding a new backend (Phase 4)

A new backend conforms to `SVGRendererBackend` and executes the existing command stream — no parser, model, or lowering changes required. If you find yourself wanting to add a SwiftUI-only command, redesign it CG-first instead.
