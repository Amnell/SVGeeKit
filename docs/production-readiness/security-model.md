# Security model

Production SVGeeKit must not fetch, decode, or execute untrusted external content while
parsing or rendering. Development and conformance tooling needs the **full local file
resolution** path (W3C bundled fonts, nested `<image href="…svg">`, relative PNGs).

**Approach:** one parser, explicit **`SVGResourcePolicy`** — secure by default, opt-in for
trusted local development. Do **not** rely on `#if DEBUG` or the mere presence of `baseURL`
as the gate.

Cross-reference: [static-profile.md](static-profile.md) for the supported subset.

## Production resilience (no traps)

**“Never crash in production”** means the library must not **`fatalError`**, **`preconditionFailure`**,
or **force-unwrap** on user-controlled SVG data. It does **not** mean removing `throws` from the
parser — integrators should use `try`/`catch` (or `Result`) and handle errors explicitly.

What we avoid is an **uncaught trap** inside SVGeeKit that takes down the host process.

### Layered behavior

| Layer | Throws? | On failure |
| --- | --- | --- |
| **`SVGParser.parse(…)`** | Yes — for hard parse failures | `throw SVGParseError` (malformed XML, missing root, …) |
| **`SVGParser.parse(…)`** | No — for recoverable policy issues | Append `SVGParseWarning` to report; continue parsing |
| **`SVGRenderTree.lower` / rasterizer** | No | Skip bad primitives; never trap |
| **`SVGImageView`** | **No** | Always a valid `View`; renders **nothing** on parse/render failure |

### Hard vs soft failures

| Kind | Examples | Parser | View |
| --- | --- | --- | --- |
| **Hard** (unrecoverable) | Not XML, no `<svg>` root, `failurePolicy: .throwOnWarning` + policy hit | `throws SVGParseError` | Empty canvas (if using data-based init) |
| **Soft** (recoverable) | Rejected external `href`, limit hit, unknown element, bad attribute | Warning in `SVGParseReport`; partial document | Renders what parsed |

Production `.failurePolicy` is **`.warnAndContinue`**: soft failures never become throws.
Hard XML failures still throw so callers can distinguish “nothing to show” from “partial icon”.

### What never happens on user data

- No `fatalError` / `preconditionFailure` / `assertionFailure` in parser or renderer
- No force-unwrap of href resolution, paint lookup, or path build without a fallback
- No uncaught filesystem access after a rejected href
- No `SVGImageView` initializer that `throws` or `fatalError`s

### Parser API (throws retained)

```swift
public struct SVGParseResult: Sendable {
  public var document: SVGDocument
  public var report: SVGParseReport
}

extension SVGParser {
  /// Primary API. Throws only on hard failures. Soft issues → `report.warnings`.
  public func parse(data: Data) throws -> SVGParseResult

  public func parse(string: String) throws -> SVGParseResult { … }
  public func parse(url: URL) throws -> SVGParseResult { … }
}
```

`SVGParseResult` bundles document + warnings so a successful `try` still surfaces policy
issues. Callers that only need the model: `try parser.parse(data:).document`.

### SwiftUI API (never throws)

The view layer absorbs failures so SwiftUI body evaluation never propagates a throw:

```swift
public struct SVGImageView: View {
  /// Existing — render a successfully parsed document.
  public init(document: SVGDocument, contentMode: SVGImageContentMode = .fit)

  /// Parse + render. Never throws. On parse failure → empty layout (zero content).
  public init(
    svgData: Data,
    parser: SVGParser = SVGParser(),
    contentMode: SVGImageContentMode = .fit
  )

  /// Optional: surface hard parse error to parent state without throwing from `body`.
  public init(
    svgData: Data,
    parser: SVGParser = SVGParser(),
    contentMode: SVGImageContentMode = .fit,
    parseError: Binding<Error?>
  )
}
```

Implementation sketch: `init(svgData:…)` runs `try? parser.parse(data:)` (or `do/catch`);
on failure, `commands = []`, `intrinsicSize = nil` → `Canvas` draws nothing. Parent can
log via `parseError` binding or by parsing separately with `try`.

### App integration patterns

```swift
// Explicit error handling (recommended for network assets)
do {
  let result = try SVGParser().parse(data: bytes)
  if !result.report.warnings.isEmpty { log(result.report.warnings) }
  SVGImageView(document: result.document)
} catch {
  fallbackIcon
}

// Fire-and-forget in SwiftUI (view never throws)
SVGImageView(svgData: bytes)

// Conformance / tests — same throwing parser
let result = try SVGParser(options: .localFiles(at: base)).parse(data: data)
```

### Testing-only strictness

```swift
public static let testingStrict = SVGParserOptions(…, failurePolicy: .throwOnWarning)
```

First soft warning becomes `throw` — for unit tests only, not app code.

## Resource policy (dev vs production)

### Design principle

| Rule | Why |
| --- | --- |
| Default is restrictive | `SVGParser()` must be safe on untrusted bytes with zero config |
| Opt-in, not opt-out | External load requires an explicit policy preset |
| Single gate | All href resolution goes through one resolver |
| Policy travels with the document | Render-time loaders must not bypass parse-time policy |
| Local files only in dev | Even development mode never fetches `http:` / `https:` |
| Never trap on user data | No `fatalError` / force-unwrap; `throws` is fine when caught |

### API sketch

```swift
// SVGCore or SVGParser — names tentative
public enum SVGResourcePolicy: Sendable, Equatable {
    /// Production default. Fragment refs (`#id`) and `data:` URIs only.
    case restricted

    /// Conformance, Viewer, local file workflows. Relative / absolute `file:` paths
    /// resolve under `baseURL`. Still no network schemes.
    case localFiles(baseURL: URL)
}

public struct SVGParserOptions: Sendable {
    public var resourcePolicy: SVGResourcePolicy
    public var limits: SVGParsingLimits
    /// How to surface recoverable problems. `.production` always uses `.warnAndContinue`.
    public var failurePolicy: SVGFailurePolicy

    /// Untrusted input — icons from network, user uploads, CMS assets.
    public static let production = SVGParserOptions(
        resourcePolicy: .restricted,
        limits: .default,
        failurePolicy: .warnAndContinue
    )

    /// W3C corpus, Viewer, `swift test`. Caller supplies the SVG file's directory.
    public static func localFiles(at baseURL: URL) -> SVGParserOptions {
        SVGParserOptions(
            resourcePolicy: .localFiles(baseURL: baseURL),
            limits: .default,
            failurePolicy: .warnAndContinue
        )
    }
}

public enum SVGFailurePolicy: Sendable {
    /// Production default. Soft failures → warnings; hard XML errors still throw.
    case warnAndContinue
    /// Unit tests only. First soft warning also throws.
    case throwOnWarning
}

public struct SVGParser {
    public var options: SVGParserOptions

    public init(options: SVGParserOptions = .production) { … }

    public func parse(data: Data) throws -> SVGParseResult { … }
    public func parse(string: String) throws -> SVGParseResult { … }
    public func parse(url: URL) throws -> SVGParseResult { … }
}
```

`baseURL` on `parse(data:baseURL:)` becomes a **convenience** that sets
`.localFiles(baseURL:)` when non-nil, or stays `.production` when nil — but the policy on
`SVGParser` always wins if both are set (document the precedence).

**Preferred call sites:**

```swift
// App — explicit try/catch
do {
  let result = try SVGParser().parse(data: bytes)
  logWarnings(result.report)
  SVGImageView(document: result.document)
} catch {
  showFallback()
}

// SwiftUI — non-throwing view (empty on failure)
SVGImageView(svgData: bytes)

// Conformance — same throwing parser + local file policy
let result = try SVGParser(options: .localFiles(at: svgURL.deletingLastPathComponent()))
    .parse(data: data)
```

### Central resolver

Introduce `SVGHrefResolver` (internal to `SVGParser` / `SVGRenderer`) used by every
current resolution path:

| Current location | What it resolves |
| --- | --- |
| `SVGReferencedImageResolver` | `<image href="…svg">` nested documents |
| `SVGImageDataLoader` | `<image href="…png">` raster bytes at render time |
| `FontParsing.loadExternalFont` | `font-face-uri xlink:href="../resources/SVGFreeSans.svg#ascii"` |
| `SAXDelegate.resolveGradientHrefs` / `resolvePatternHrefs` | `#fragment` in same doc — **always allowed** |
| `SVGDocument.resolveURL` | Generic helper — delegate to resolver |

```swift
enum SVGHrefResolver {
    enum Resolution {
        case fragment(String)           // #id — same document
        case dataURI(String)            // data:… — decode with size cap
        case localFile(URL)             // only when policy == .localFiles
        case rejected(SVGHrefRejectionReason)
    }

    static func classify(_ href: String, policy: SVGResourcePolicy) -> Resolution
}
```

### Stamp policy on `SVGDocument`

```swift
public struct SVGDocument {
    public var resourcePolicy: SVGResourcePolicy  // set at end of parse
    …
}
```

`SVGRenderTree` / `SVGImageDataLoader.load` reads `document.resourcePolicy` so a document
parsed in production mode cannot load disk files later even if `baseURL` was accidentally
left set.

### Behavior matrix

| href | `.restricted` | `.localFiles(baseURL:)` |
| --- | --- | --- |
| `#gradient` | Resolve in-doc | Resolve in-doc |
| `data:image/png;base64,…` | Decode (size cap) | Decode (size cap) |
| `data:image/svg+xml,…` | Parse nested (size cap) | Parse nested (size cap) |
| `../resources/foo.svg#id` | Warn; skip load | Load under `baseURL` |
| `image.png` | Warn; skip load | Load under `baseURL` |
| `https://…` | Warn; skip load | Warn; skip load (never) |
| `/etc/passwd` | Warn; skip load | Warn unless under allowed root* |

\*Optional hardening for `.localFiles`: resolve paths but reject if standardized path escapes
`baseURL` (path traversal guard) — still a warning + skip, not a throw, unless
`failurePolicy: .throwOnWarning`.

### Failure policy

| `failurePolicy` | Who uses it | On soft problem | On hard XML failure |
| --- | --- | --- | --- |
| `.warnAndContinue` | `.production`, `.localFiles`, apps | Warning in report | `throw SVGParseError` |
| `.throwOnWarning` | Unit tests only | `throw` | `throw` |

Production presets use `.warnAndContinue` — policy violations and limits are warnings, not
additional throw sites. Malformed documents still throw so callers can branch.

### What NOT to do

| Anti-pattern | Problem |
| --- | --- |
| `#if DEBUG` around external loading | Release conformance / profiling can't load W3C fonts |
| `baseURL != nil` ⇒ load files | Easy to accidentally pass `baseURL` in production |
| Separate `SVGParserUnsafe` type | Forks resolution logic; one gate is simpler |
| Network loading in `.localFiles` | SSRF; out of scope for this library |

### Module defaults

| Caller | Default policy |
| --- | --- |
| `SVGParser()` | `.production` |
| `SVGConformanceRunner` | `.localFiles(at: testCase.svgURL.deletingLastPathComponent())` |
| `W3CReferenceDiff` | `.localFiles(…)` |
| Viewer app | `.localFiles(…)` |
| `Benchmarks` executable | `.localFiles(…)` when given paths; `.production` for stdin/string |
| `SVGScriptDocument` | Inherit caller's policy (scripting is already non-production) |

## Threat model

| Threat | Mitigation |
| --- | --- |
| SSRF / arbitrary file read via `href` | Reject non-fragment external URIs |
| XXE / billion-laughs entity expansion | `XMLParser` with no external entities; size limits |
| Path bombs (huge `d` attributes) | Configurable parse limits |
| Script execution | Never execute `<script>` in production `SVGKit` |
| `foreignObject` HTML injection | Element ignored |
| Decompression bombs in embedded `data:` images | Size cap before decode |
| Cyclic `<image href="…svg">` graphs | Cycle detection (exists today; keep in `.localFiles` only) |

## URI policy

### Always allowed (both policies)

| Pattern | Example | Use |
| --- | --- | --- |
| Fragment reference | `#myGradient` | `use`, gradients, patterns, `clip-path`, `mask` |
| Data URI (image) | `data:image/png;base64,…` | Embedded raster in `<image>` |
| Data URI (SVG) | `data:image/svg+xml;base64,…` | Nested SVG if size limits pass |

### Allowed only in `.localFiles`

| Pattern | Example | Use |
| --- | --- | --- |
| Relative file path | `../resources/SVGFreeSans.svg#ascii` | W3C fonts, co-located assets |
| Same-directory file | `icon.png` | Raster `<image>` |
| Nested SVG file | `nested.svg` | `<image href="…svg">` |

### Never allowed (any policy)

| Pattern | Example | Action |
| --- | --- | --- |
| HTTP(S) | `https://example.com/a.svg` | Warn; skip load |
| `file://` outside allowed root | `file:///etc/passwd` | Warn; skip load |

### Migration note

External resolution today is implicitly enabled whenever `baseURL` is set
(`ImageParsing.swift`, `FontParsing.swift`, `SVGImageDataLoader.swift`). Phase 0
introduces `SVGResourcePolicy` so that **`baseURL` alone is not sufficient** — callers
must pass `.localFiles(at:)` for the W3C harness and Viewer.

## Parse limits (to implement)

Expose via `SVGParser.Options` (names tentative):

| Limit | Suggested default | Purpose |
| --- | --- | --- |
| `maxDocumentBytes` | 4 MB | Reject huge inputs |
| `maxElementCount` | 50 000 | XML bomb guard |
| `maxPathCommands` | 500 000 per `d` | Path bomb guard |
| `maxNestingDepth` | 256 | Stack guard |
| `maxDataURIBytes` | 2 MB | Embedded image cap |
| `maxDefinitions` | 10 000 | `defs` table cap |

When a limit is exceeded under `.warnAndContinue`: **warn + skip or truncate** — do not
throw. Record `SVGParseWarning.limitExceeded(…)`. Hard XML failures still throw.

## Capability reporting (to implement)

Successful `parse(…)` returns warnings alongside the document via `SVGParseResult`:

```swift
public struct SVGParseWarning: Sendable {
  public enum Kind: Sendable {
    case rejectedExternalReference(href: String, line: Int?)
    case limitExceeded(kind: String, line: Int?)
    case unsupportedElement(name: String, line: Int?)
    case malformedAttribute(name: String, line: Int?)
    case missingDefinition(id: String)
    case xmlNotWellFormed(detail: String)
  }
  public var kind: Kind
  public var message: String
}

public struct SVGParseReport: Sendable {
  public var warnings: [SVGParseWarning]
}
```

Integrators inspect `result.report.warnings` after a successful `try`. For SwiftUI,
`SVGImageView(svgData:)` handles hard failures internally (empty view); use a separate
`try parse` when you need to surface errors to the user.

## Implementation checklist

### Phase 0a — policy infrastructure

- [x] Add `SVGResourcePolicy`, `SVGParserOptions`, `SVGFailurePolicy`, `SVGHrefResolver`
- [x] `SVGParser(options:)` defaults to `.production` with `.warnAndContinue`
- [x] `parseWithReport(…) throws -> SVGParseResult` (document + report)
- [x] Store `resourcePolicy` on `SVGDocument` at end of parse
- [x] Route `SVGReferencedImageResolver`, `FontParsing`, `SVGImageDataLoader` through resolver
- [x] Path traversal guard for `.localFiles` (warn + skip; allows W3C `../resources/`)
- [x] Unit tests: production warns on relative href; localFiles accepts co-located file
- [ ] Unit tests: malformed XML throws; hostile input never traps (`fatalError`/force-unwrap)

### Phase 0b — caller migration & view layer

- [ ] `SVGConformanceRunner` → explicit `.localFiles(at:)` (still uses `baseURL` bridge)
- [ ] `W3CReferenceDiff` → `.localFiles(at:)`
- [ ] Viewer / Benchmarks → `.localFiles(at:)` when reading paths
- [x] `SVGImageView(svgData:)` — non-throwing init, empty canvas on parse failure
- [x] Optional `SVGImageView(…, parseError: Binding<Error?>)` for parent state
- [ ] Document in README: parser throws on hard failure; view never throws
- [ ] Renderer audit: no `fatalError` / force-unwrap on user-controlled model data

### Phase 0c — hardening

- [x] Add `SVGParsingLimits` on `SVGParserOptions`
- [ ] `SVGParseReport` on every successful `parse(…)`
- [ ] Audit `SVGParser` for implicit `URL(string:relativeTo:)` resolution paths
- [ ] Ensure `SVGScript` / `SVGAnimation` are not linked by default from `SVGKit`
- [ ] Fuzz / corpus test: random bytes → no trap; malformed → `throws` or empty view

## Conformance impact

These W3C tag families remain **permanently skipped** for production:

| Tag | Reason |
| --- | --- |
| `linking` | External and internal navigation — not rendering |
| `script` | Script execution |
| `interact` | Pointer events / cursor |
| `extend` | Namespace extension edge cases |

Individual tests that only need a static initial frame may still run via `overrides.json`
`"run": true` when the script is irrelevant to the visual under test.
