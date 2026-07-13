# SVGeeKit

A Swift package for rendering **static SVG** on iOS 17+ / macOS 14+, built incrementally against the W3C SVG 1.1 Second Edition test suite.

> Static SVG renderer for iOS 17+ / macOS 14+. See the [production readiness plan](docs/production-readiness/README.md) for the supported feature profile and roadmap.

## Quick start

**SwiftUI (untrusted bytes — view never throws):**

```swift
import SVGKit
import SwiftUI

struct ContentView: View {
    let svgData: Data

    var body: some View {
        SVGImageView(svgData: svgData, contentMode: .fit)
            .frame(width: 480, height: 360)
    }
}
```

On parse failure the canvas is empty. To surface errors to parent state:

```swift
@State private var parseError: Error?

SVGImageView(svgData: svgData, parseError: $parseError)
```

**Explicit parse (recommended for network assets):**

```swift
import SVGKit
import SwiftUI

struct ContentView: View {
    let svgData: Data
    @State private var document: SVGDocument?

    var body: some View {
        Group {
            if let document {
                SVGImageView(document: document, contentMode: .fit)
            } else {
                ContentUnavailableView("Invalid SVG", systemImage: "exclamationmark.triangle")
            }
        }
        .task {
            do {
                let result = try SVGParser().parseWithReport(data: svgData)
                if !result.report.warnings.isEmpty {
                    // rejected external href, limit hit, unknown element, …
                }
                document = result.document
            } catch {
                document = nil
            }
        }
    }
}
```

`SVGParser()` defaults to **production** policy: same-document `#fragment` refs and `data:` URIs only — no network or disk fetch. For local fixture files (tests, Viewer), use `SVGParser(options: .localFiles(at: directory))` or `SVGConformanceFixtureParsing.parse(data:svgURL:)`.

## Security & resilience

| Layer | Throws? | On failure |
| --- | --- | --- |
| `SVGParser.parse(…)` | Yes — hard failures only | `throw SVGParseError` (malformed XML, missing root, …) |
| `SVGParser.parseWithReport(…)` | Same | Document + `SVGParseReport.warnings` for soft issues (rejected `href`, limits, …) |
| `SVGImageView` | **No** | Empty canvas on parse failure |

Production means **no traps** on user data (`fatalError`, force-unwrap) — not “never throw.” Use `try`/`catch` at the parser boundary; let `SVGImageView(svgData:)` absorb failures in SwiftUI.

Details: [security model](docs/production-readiness/security-model.md) · [implementation guide](docs/production-readiness/security-implementation.md)

## Architecture

Pipeline: bytes → `SVGParser` → `SVGCore` model → `SVGRenderTree.lower` → `[SVGRenderCommand]` → renderer backend (currently `SVGRendererSwiftUI`, future `SVGRendererCoreGraphics` / Metal).

See [docs/architecture.md](docs/architecture.md) for the module contract.

`SVGKit` re-exports `SVGCore`, `SVGParser`, `SVGRenderer`, and `SVGRendererSwiftUI` only. Scripting (`SVGScript`) and SMIL (`SVGAnimation`) are separate products for conformance tooling — not linked by default.

## Testing

- Unit tests: `swift test --filter SVGCoreTests`, `swift test --filter SVGParserTests`.
- Conformance suite: `swift test --filter ConformanceSuite` — parses each W3C-shaped test under `Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/`, rasterizes it, and diffs against the approved baseline in `Tests/__Snapshots__/`.
- Approve new / changed baselines: `APPROVE_SNAPSHOTS=1 swift test`.

The runner emits `docs/conformance/conformance-report.json` for every test run.

## Benchmarks

A standalone executable times the parse / lower / rasterize phases on either the vendored W3C corpus or any SVG files you point it at:

```sh
swift run -c release Benchmarks                       # full W3C SVG 1.1 corpus
swift run -c release Benchmarks -n 10 -f paths-data   # 10 iterations, filtered
swift run -c release Benchmarks --no-rasterize        # CPU phases only
swift run -c release Benchmarks ~/Desktop/logo.svg    # one file
swift run -c release Benchmarks samples/              # walk a directory
swift run -c release Benchmarks 'corpus/**/*.svg'     # quoted glob pattern
swift run -c release Benchmarks --help
```

Output is a per-phase table (n / mean / median / p95 / max) plus the top-N slowest files.

## Production readiness

The v1 target is **self-contained static SVG 1.1** — no scripting, animation, or external
resource fetch in the production API. **Security Phase 0 is complete** (resource policy, limits, non-throwing view). Track feature progress in [docs/production-readiness/](docs/production-readiness/README.md):

- [Static profile](docs/production-readiness/static-profile.md) — supported / unsupported subset
- [Roadmap](docs/production-readiness/roadmap.md) — phased implementation checklist
- [Security model](docs/production-readiness/security-model.md) — URI policy and parse limits
- [Shipping checklist](docs/production-readiness/shipping-checklist.md) — release gates

## Contributing

Coding agents and human contributors should both read [AGENTS.md](AGENTS.md) and the recipe in [docs/adding-a-feature.md](docs/adding-a-feature.md) before touching code. The library is designed to be extended one SVG feature at a time without breaking previously-passing snapshots.

## License

TBD.
