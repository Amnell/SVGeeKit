# SVGeeKit

A Swift package for rendering **static SVG** on iOS 17+ / macOS 14+, built incrementally against the W3C SVG 1.1 Second Edition test suite.

> Phase 1 vertical slice. Supported today: `<svg>` root with `viewBox`, `<g>` grouping, and `<rect>` (with fill, stroke, rounded corners, opacity, transforms). More features land per the plan in `AGENTS.md`.

## Quick start

```swift
import SVGKit
import SwiftUI

struct ContentView: View {
    @State private var document = try! SVGParser().parse(string: svgText)

    var body: some View {
        SVGImageView(document: document)
            .frame(width: 480, height: 360)
    }
}
```

## Architecture

Pipeline: bytes → `SVGParser` → `SVGCore` model → `SVGRenderTree.lower` → `[SVGRenderCommand]` → renderer backend (currently `SVGRendererSwiftUI`, future `SVGRendererCoreGraphics` / Metal).

See [docs/architecture.md](docs/architecture.md) for the module contract.

## Testing

- Unit tests: `swift test --filter SVGCoreTests`, `swift test --filter SVGParserTests`.
- Conformance suite: `swift test --filter ConformanceSuite` — parses each W3C-shaped test under `Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/`, rasterizes it, and diffs against the approved baseline in `Tests/__Snapshots__/`.
- Approve new / changed baselines: `APPROVE_SNAPSHOTS=1 swift test`.

The runner emits `docs/conformance/conformance-report.json` for every test run.

## Contributing

Coding agents and human contributors should both read [AGENTS.md](AGENTS.md) and the recipe in [docs/adding-a-feature.md](docs/adding-a-feature.md) before touching code. The library is designed to be extended one SVG feature at a time without breaking previously-passing snapshots.

## License

TBD.
