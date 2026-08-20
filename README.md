# SVGeeKit

> **Early-stage summer hobby project.** The API and feature set are still moving. That said, it already covers a large portion of the [W3C SVG 1.1 Second Edition](https://www.w3.org/TR/SVG11/) test suite — shapes, paths, gradients, patterns, clipping, masking, and more — and is built to grow one spec feature at a time.

A Swift package for rendering **static SVG** on iOS 16+ / macOS 14+. Optional `SVGScript` and `SVGAnimationImageView` require iOS 17+. See the [production readiness plan](docs/production-readiness/README.md) for the supported feature profile, conformance numbers, and roadmap.

## Installation (Swift Package Manager)

**Xcode:** File → Add Package Dependencies… → `https://github.com/Amnell/SVGeeKit.git`. Add the `SVGeeKit` library to your app target. Add `SVGAnimation` and/or `SVGScript` only if you need those opt-in products.

**`Package.swift`:**

```swift
dependencies: [
    .package(url: "https://github.com/Amnell/SVGeeKit.git", branch: "main")
]
```

Then link the product you need on the target:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "SVGeeKit", package: "SVGeeKit")
    ]
)
```

The package, product, and module are all **SVGeeKit**. `import SVGeeKit` re-exports the static parse/render surface (`SVGCore`, `SVGParser`, `SVGRenderer`, `SVGRendererSwiftUI`). Types keep the `SVG` prefix (`SVGImageView`, `SVGParser`, `SVGRenderedImage`). Scripting and SMIL are separate products and are **not** pulled in by `SVGeeKit`.

| Use case | SPM product(s) | Import | Notes |
| --- | --- | --- | --- |
| SwiftUI `SVGImageView` (data, document, or URL) | `SVGeeKit` | `import SVGeeKit` · `import SwiftUI` | Default path. View never throws. |
| Bitmap → SwiftUI `Image` / `UIImage` / `NSImage` | `SVGeeKit` | `import SVGeeKit` · `import SwiftUI` | `SVGRenderedImage` |
| Parse only (no UI) | `SVGeeKit` | `import SVGeeKit` | Or link `SVGParser` and `import SVGParser` + `import SVGCore` |
| Live SMIL (`SVGAnimationImageView`) | `SVGeeKit` + `SVGAnimation` | `import SVGeeKit` · `import SVGAnimation` | iOS 17+ / macOS 14+ |
| SMIL sampling on iOS 16 | `SVGeeKit` + `SVGAnimation` | `import SVGeeKit` · `import SVGAnimation` | `SVGAnimationEngine.sample` + `SVGImageView` |
| ECMAScript / `onclick` | `SVGeeKit` + `SVGScript` | `import SVGeeKit` · `import SVGScript` | iOS 17+; JavaScriptCore; not for untrusted production SVG |
| W3C fixtures / snapshot harness | `SVGConformance` | `import SVGConformance` | Tests and the Viewer app — not an app dependency |

Most apps only need **`SVGeeKit`**. Do not add `SVGScript` or `SVGAnimation` unless you explicitly want those capabilities.

**Static SwiftUI (product `SVGeeKit`):**

```swift
import SVGeeKit
import SwiftUI

SVGImageView(svgData: data, contentMode: .fit)
```

**Bitmap for `Image` (product `SVGeeKit`):**

```swift
import SVGeeKit
import SwiftUI

let rendered = try await SVGRenderedImage(url: iconURL, size: CGSize(width: 48, height: 48))
Image(rendered)
```

**SMIL on iOS 17+ (products `SVGeeKit` + `SVGAnimation`):**

```swift
import SVGeeKit
import SVGAnimation
import SwiftUI

if #available(iOS 17, *) {
    try SVGAnimationImageView(data: data)
}
```

**SMIL sampling on iOS 16 (same products):**

```swift
import SVGeeKit
import SVGAnimation
import SwiftUI

let sampled = SVGAnimationEngine.sample(document: document, at: time)
SVGImageView(document: sampled, contentMode: .fit)
```

**Scripting (products `SVGeeKit` + `SVGScript`, iOS 17+):**

```swift
import SVGeeKit
import SVGScript
import SwiftUI

if #available(iOS 17, *) {
    try SVGScriptImageView(data: data)
}
```

## Quick start

**SwiftUI (untrusted bytes — view never throws):**

```swift
import SVGeeKit
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

**From a URL or `URLRequest` (view never throws):**

```swift
SVGImageView(url: URL(string: "https://example.com/icon.svg"))
    .frame(width: 48, height: 48)

var request = URLRequest(url: assetURL)
request.setValue("Bearer …", forHTTPHeaderField: "Authorization")
SVGImageView(urlRequest: request, parseError: $parseError)
```

The view fetches the SVG document, then parses it with `SVGParser()` (production policy). Referenced `href`s inside that document are still not loaded from the network. On load or parse failure the canvas is empty.

**Bitmap for `Image` / `UIImage` / `NSImage`:**

```swift
let rendered = try await SVGRenderedImage(
    url: iconURL,
    size: CGSize(width: 48, height: 48),
    scale: displayScale
)
Image(rendered)
    .resizable()
    .aspectRatio(contentMode: .fit)

#if os(iOS)
Image(uiImage: rendered.uiImage)
#endif
```

`size` is the output bitmap in points (`nil` uses the SVG's width/height or `viewBox`). This type is named `SVGRenderedImage` because `SVGImage` is already the SVG `<image>` element.

Parsed documents and rasters are cached in `SVGRenderedImageCache.shared` (keyed by content hash and output size, not URL) so the same icon at 24pt and 48pt stays two bitmaps, and a changed remote file is redrawn after URLSession returns new bytes. Pass `cache: nil` to opt out. HTTP caching of the SVG bytes is still `URLSession`'s job.

**Explicit parse (recommended when you need warnings or custom caching):**

```swift
import SVGeeKit
import SwiftUI

struct ContentView: View {
    let svgData: Data
    @State private var document: SVGDocument?

    var body: some View {
        Group {
            if let document {
                SVGImageView(document: document, contentMode: .fit)
            } else {
                Text("Invalid SVG")
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
| `SVGImageView` | **No** | Empty canvas on parse or load failure |

Production means **no traps** on user data (`fatalError`, force-unwrap) — not “never throw.” Use `try`/`catch` at the parser boundary; let `SVGImageView(svgData:)` absorb failures in SwiftUI.

Details: [security model](docs/production-readiness/security-model.md) · [implementation guide](docs/production-readiness/security-implementation.md)

## Architecture

Pipeline: bytes → `SVGParser` → `SVGCore` model → `SVGRenderTree.lower` → `[SVGRenderCommand]` → renderer backend (currently `SVGRendererSwiftUI`, future `SVGRendererCoreGraphics` / Metal).

See [docs/architecture.md](docs/architecture.md) for the module contract.

`SVGeeKit` re-exports `SVGCore`, `SVGParser`, `SVGRenderer`, and `SVGRendererSwiftUI` only. Scripting (`SVGScript`) and live SMIL (`SVGAnimationImageView`) are separate products and require iOS 17+; `SVGAnimationEngine` is available on iOS 16+.

## Testing

- Unit tests: `swift test --filter SVGCoreTests`, `swift test --filter SVGParserTests`.
- Conformance suite: `swift test --filter ConformanceSuite` — parses each W3C-shaped test under `Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/`, rasterizes it, and diffs against the approved baseline in `Tests/__Snapshots__/`.
- Approve new / changed baselines: `APPROVE_SNAPSHOTS=1 swift test`.
- iOS 16 device/simulator check: open `Apps/iOS16Smoke/iOS16Smoke.xcodeproj` (see [Apps/iOS16Smoke/README.md](Apps/iOS16Smoke/README.md)).

The runner emits `docs/conformance/conformance-report.json` for every test run.

Browse the [W3C coverage gallery](docs/conformance/README.md) (SVGeeKit render vs. W3C reference PNG, one page per chapter). After a full conformance run:

```sh
swift run CoverageReport
```

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

## Releasing

No compile step — Swift Package Manager versions this package from **git tags**. Release notes are generated on the GitHub Release (PRs and commits since the previous tag).

1. On `main`, run **Actions → Cut release → Run workflow** and enter a semver (e.g. `0.1.0`). That tags `v0.1.0` and publishes the GitHub Release.
2. If you tag locally (`git tag v0.1.0 && git push origin v0.1.0`), **Publish release** creates the GitHub Release for that tag.

After the first tag, consumers can pin with `.package(url: "https://github.com/Amnell/SVGeeKit.git", from: "0.1.0")`.

## License

TBD.
