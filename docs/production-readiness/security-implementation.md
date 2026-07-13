# Security model — implementation guide

Step-by-step plan for [security-model.md](security-model.md) Phase 0. Each step is sized for
one focused PR; run `swift test` after every step.

**Where to start:** [Step 1](#step-1--types--href-resolver-no-behavior-change) — types and
`SVGHrefResolver` only. No call-site changes, no conformance impact.

## Current state (audit)

External I/O is scattered and implicitly gated by `baseURL`:

| File | What loads |
| --- | --- |
| `Sources/SVGParser/ImageParsing.swift` | Nested `<image href="file.svg">` via `Data(contentsOf:)` |
| `Sources/SVGParser/FontParsing.swift` | `font-face-uri` → external SVG font file |
| `Sources/SVGRenderer/SVGImageDataLoader.swift` | Raster `<image href="file.png">` at **render** time |
| `Sources/SVGCore/SVGDocument.swift` | `resolveURL(_:)` — generic relative resolution |
| `Sources/SVGParser/SVGParser.swift` | `parse(url:)` sets `baseURL` to parent directory |

~40 test / Viewer call sites pass `baseURL:` today. **Do not flip the default policy until
Step 5** (after harness migration).

## Dependency graph

```
Step 1  Types + SVGHrefResolver (no wiring)
   ↓
Step 2  SVGParseResult + warnings collector on SAXDelegate
   ↓
Step 3  Wire resolver → ImageParsing, FontParsing (parse time)
   ↓
Step 4  Wire resolver → SVGImageDataLoader (render time, via document.policy)
   ↓
Step 5  Migrate conformance / Viewer / tests → .localFiles(at:)
   ↓
Step 6  Default SVGParser() → .production; deprecate bare baseURL
   ↓
Step 7  SVGImageView(svgData:) non-throwing init
   ↓
Step 8  SVGParsingLimits
   ↓
Step 9  Renderer trap audit + fuzz test
```

---

## Step 1 — Types + href resolver (no behavior change)

**Goal:** Land the vocabulary without changing runtime behavior.

### New files (SVGCore — value types only)

| File | Types |
| --- | --- |
| `Sources/SVGCore/SVGResourcePolicy.swift` | `SVGResourcePolicy`, `SVGParserOptions`, `SVGFailurePolicy`, `SVGParsingLimits` |
| `Sources/SVGCore/SVGParseReport.swift` | `SVGParseWarning`, `SVGParseReport`, `SVGParseResult` |

### New file (SVGParser — internal)

| File | Types |
| --- | --- |
| `Sources/SVGParser/SVGHrefResolver.swift` | `classify(href:policy:) -> Resolution` |

Resolver rules (unit-test these in isolation):

- `#id` → `.fragment`
- `data:…` → `.dataURI`
- `http:` / `https:` → `.rejected(.networkScheme)` — always
- Relative / absolute path → `.localFile(resolvedURL)` only if `policy == .localFiles(baseURL)`
- Otherwise → `.rejected(.externalReference)`

Path traversal: if `.localFiles`, resolve then verify
`resolvedURL.standardizedFileURL.path.hasPrefix(baseURL.standardizedFileURL.path)`.

### Tests

`Tests/SVGParserTests/SVGHrefResolverTests.swift` — table-driven cases, no parser involved.

### Exit criteria

- [ ] `swift build` / `swift test` green
- [ ] Zero behavior change to existing parse paths

---

## Step 2 — Parse result + warning collector

**Goal:** Parser can accumulate warnings without changing return type yet.

### Changes

1. `SAXDelegate` holds `var warnings: [SVGParseWarning]` and optional `failurePolicy`.
2. Add `warning(_:)` helper on delegate (records line from `XMLParser` when available).
3. Add parallel API (keep old signatures):

```swift
public func parse(data: Data, options: SVGParserOptions = .production) throws -> SVGParseResult
```

4. Existing `parse(data:baseURL:)` forwards to:

```swift
// Temporary bridge until Step 6 — preserves today’s behavior
let opts = baseURL.map { SVGParserOptions.localFiles(at: $0) } ?? .production
return try parse(data: data, options: opts)
```

5. On successful parse, set `document.resourcePolicy = options.resourcePolicy`.

### Tests

- Parse valid inline SVG → `result.report.warnings.isEmpty`
- Parse with unknown element → warning recorded (once wired in Step 3)

### Exit criteria

- [ ] `SVGParseResult` returned from new overload
- [ ] Old `parse(data:baseURL:)` still works identically via bridge
- [ ] All existing tests pass unchanged

---

## Step 3 — Wire resolver at parse time

**Goal:** Gate `ImageParsing` and `FontParsing` through `SVGHrefResolver`.

### ImageParsing.swift

Before `Data(contentsOf:)` or nested parse:

```swift
switch SVGHrefResolver.classify(href, policy: policy) {
case .localFile(let url): … load …
case .dataURI: … existing data path …
case .fragment: return nil  // not valid for image file href
case .rejected(let reason):
  warnings.append(.rejectedExternalReference(href: href, …))
  return nil
}
```

Thread `policy` + `warnings` from `SVGParser.parse` → `SVGReferencedImageResolver.resolve`.

### FontParsing.swift

Same gate in `loadExternalFont(href:)`.

### Policy source during Steps 3–4

Use `options.resourcePolicy` from parser. Bridge in Step 2 means `baseURL` callers still get
`.localFiles` — **conformance keeps working**.

### Tests (new)

| Test | Expect |
| --- | --- |
| `.production` + `<image href="../x.png">` | Warning; no file load |
| `.production` + `<image href="data:image/png;base64,…">` | No warning; loads |
| `.localFiles(at:)` + W3C font URI | Font loads (existing test ids) |

### Exit criteria

- [ ] Production policy blocks external file loads at parse time
- [ ] Conformance still passes (bridge provides `.localFiles` when `baseURL` passed)

---

## Step 4 — Wire resolver at render time

**Goal:** `SVGImageDataLoader` cannot bypass policy via `document.baseURL`.

### Changes

1. `SVGImageDataLoader.load(href:policy:)` (or pass full `SVGDocument`).
2. `SVGRenderer.swift` `RenderContext` carries `resourcePolicy` instead of bare `baseURL`.
3. When policy is `.restricted`, raster file hrefs return `nil` (image skipped — no throw).

### Tests

Extend `SVGImageDataLoaderTests` with `.restricted` vs `.localFiles`.

### Exit criteria

- [ ] No render-time disk read under `.production` policy
- [ ] Conformance raster image tests still pass via bridge

---

## Step 5 — Migrate trusted callers to explicit `.localFiles`

**Goal:** Conformance and tooling opt in explicitly; stop relying on `baseURL` parameter.

### Call sites to update

| Location | Change |
| --- | --- |
| `Sources/SVGConformance/ConformanceRunner.swift` | `SVGParser(options: .localFiles(at: …))` |
| `Sources/SVGConformance/W3CReferenceDiff.swift` | same |
| `Apps/Viewer/TestDetailView.swift`, `TestStore.swift`, `DropZoneView.swift` | same |
| `Apps/Benchmarks/main.swift` | same for file paths |
| `Tests/SVGRendererTests/*` | helper: `parseW3C(_ testId:)` using `.localFiles` |
| `Tests/SVGAnimationTests/*` | same |
| `Tests/SVGParserTests/*` | tests that need external refs use `.localFiles`; others use `.production` |

Add test helper in `SVGConformance`:

```swift
// Sources/SVGConformance/ConformanceFixtureParsing.swift
SVGConformanceFixtureParsing.parse(data:svgURL:)
```

### Exit criteria

- [x] Conformance green with explicit `.localFiles`
- [x] No production test accidentally passes `baseURL:` without `.localFiles`

---

## Step 6 — Production default; remove baseURL bridge

**Goal:** `SVGParser()` is secure with no parameters.

### Breaking API changes (2026-07-13)

Removed implicit local-file access via `baseURL`:

| Removed | Replacement |
| --- | --- |
| `parse(data:baseURL:)` | `parse(data:)` (`.production`) or `parse(data:options:sourceURL:)` with `.localFiles(at:)` |
| `parse(string:baseURL:)` | `parse(string:)` or explicit `SVGParserOptions.localFiles(at:)` |
| `SVGParser.parse(data:baseURL:)` async | `SVGParser.parse(data:options:)` async |
| `SVGScriptDocument(data:baseURL:)` | `SVGScriptDocument(data:options:)` |
| `SVGScriptImageView(data:baseURL:)` | `SVGScriptImageView(data:options:)` |
| `SVGAnimationImageView(data:baseURL:)` | `SVGAnimationImageView(data:options:)` |
| `SVGImageDataLoader.load(href:baseURL:)` | `load(href:policy:)` |

W3C / Viewer / benchmarks: use `SVGConformanceFixtureParsing.parse(data:svgURL:)`.

### Changes

1. Remove or deprecate `parse(data:baseURL:)` — replace with `parse(data:options:)`.
2. `parse(url:)` for production: either remove, or document as dev-only and require
   `.localFiles(at: url.deletingLastPathComponent())` internally in Benchmarks/Viewer only.
3. `SVGDocument.baseURL` — keep for `.localFiles` policy only; nil under `.restricted`.

### Tests

- `SVGParser().parse(string: "<svg>…<image href='../x.png'/>")` → warning, no load
- Conformance still green (already on `.localFiles` from Step 5)

### Exit criteria

- [x] Default parser is production-safe
- [x] Breaking API change documented in plan / CHANGELOG

---

## Step 7 — Non-throwing SwiftUI view

**Goal:** `SVGImageView(svgData:)` never throws; empty on failure.

### Changes — `SVGImageView.swift`

```swift
public init(svgData: Data, parser: SVGParser = SVGParser(), contentMode: …) {
  if let result = try? parser.parse(data: svgData) {
    self.init(document: result.document, contentMode: contentMode)
  } else {
    self.commands = []
    self.intrinsicSize = nil
    self.contentMode = contentMode
  }
}
```

Optional `parseError: Binding<Error?>` variant captures the `catch` error.

### Tests

`SVGImageViewContentModeTests` or new file: invalid bytes → view builds, canvas empty.

### Exit criteria

- [ ] No throwing view initializer
- [ ] Valid SVG still renders identically

---

## Step 8 — Parse limits

**Goal:** Bomb protection with warnings, not traps.

Wire `SVGParsingLimits` checks into:

- `SVGParser.parse` entry (document bytes)
- `SAXDelegate` element count / depth
- `PathDataParser` command count
- `SVGImageDataLoader` data URI size

On exceed: `warning(.limitExceeded(…))` + skip/truncate per [security-model.md](security-model.md).

### Exit criteria

- [ ] Oversized path `d` → warning, partial path or skipped element
- [ ] Hard XML errors still throw

---

## Step 9 — Trap audit + fuzz

**Goal:** Prove no `fatalError` / force-unwrap on hostile input.

1. Grep audit: `fatalError`, `precondition`, `!` on parser/renderer paths touching user data.
2. Add `Tests/SVGParserTests/HostileInputTests.swift`:
   - Random `Data` → `parse` does not trap
   - Malformed XML → `throws` OR empty view (Step 7)
3. Optional: run on W3C corpus with `.production` — expect warnings, no crash.

### Exit criteria

- [ ] Checklist in [security-model.md](security-model.md) Phase 0c complete

---

## Suggested PR sequence

| PR | Steps | Risk |
| --- | --- | --- |
| 1 | Step 1 | None |
| 2 | Step 2 | Low |
| 3 | Step 3 + 4 | Medium — run full conformance |
| 4 | Step 5 | Medium — mechanical call-site updates |
| 5 | Step 6 | **Breaking** — API cleanup |
| 6 | Step 7 | Low |
| 7 | Step 8 + 9 | Low |

## What to do right now

1. Read [security-model.md](security-model.md) resilience section (throws vs warnings vs view).
2. Open **PR 1**: add `SVGResourcePolicy.swift`, `SVGParseReport.swift`, `SVGHrefResolver.swift`
   + `SVGHrefResolverTests`.
3. Do **not** change `SVGParser()` default or `baseURL` behavior until PR 4–5.

After PR 3 lands, run:

```sh
swift test --filter ConformanceSuite
swift test --filter SVGParserTests
```

to confirm the bridge still feeds `.localFiles` to the harness.
