# CSS & styling rollout plan

Phased plan for SVG 1.1 styling (`styling-*` W3C chapter). Most work is
**parser-only** — styles resolve into `SVGPaintProperties` / `SVGFont` at parse
time; the renderer already handles the resulting paint. See
[adding-a-feature.md §1b](adding-a-feature.md#1b-styling-features-css--parser-only-path)
for the implementation recipe.

## Goals

1. Support author stylesheets (`<style type="text/css">`) and the `class` attribute.
2. Preserve correct SVG 1.1 cascade: presentation attributes beat inline `style`,
   which beats stylesheet rules, which beat inheritance.
3. Land one W3C `styling-*` test at a time with parser unit tests + snapshot review.

## Current state

| Area | Status |
| --- | --- |
| Presentation attributes | Mostly works (`styling-pres-01-t` passed) |
| Inline `style="..."` | Works (`styling-css-07-f` passed) |
| `<style>` class selectors (`.foo`, `.foo.bar`) | Implemented (`styling-class-01-f` — partial baseline pending promotion) |
| `<style>` type selectors (`rect { }`) | Implemented (`styling-css-01-b` — partial baseline pending promotion) |
| `mergeFont` + stylesheet | Not wired — extend when a test needs font props from CSS |
| Inheritance / specificity edge cases | Mostly `partialBaseline` — treat as unverified |

## Key files

| File | Role |
| --- | --- |
| `Sources/SVGParser/CSSStylesheet.swift` | Parse class rules from `<style>` text |
| `Sources/SVGParser/SVGParser.swift` | `<style>` SAX capture (`foundCharacters` + `foundCDATA`), `mergePaint`, `mergeFont` |
| `Sources/SVGParser/AttributeParsers.swift` | Color/length parsing reused by `applyPaintProperty` |

## Paint cascade (do not reorder casually)

1. Inherited paint from ancestors
2. Matching `<style>` class rules (document order)
3. Inline `style="..."` attribute
4. Presentation attributes — highest priority

## Suggested next tests

Read each test's `<d:passCriteria>` before picking one:

| Test | Exercises | Likely work |
| --- | --- | --- |
| `styling-css-01-b` | Type + class selectors in `<style>` | Done — type selectors in `CSSStylesheet` |
| `styling-css-02-b` … `styling-css-06-b` | Further `<style>` rules | Extend stylesheet parser incrementally |
| `styling-pres-02-f` … `styling-pres-05-f` | Presentation attribute edge cases | Parser cascade / `mergePaint` |
| `styling-inherit-01-b` | Property inheritance | Inheritance in `mergePaint` / group stack |
| `styling-elem-01-b` | Element-specific styling | Type selectors + element context |

## Testing workflow

1. **Parser unit test first** — assert resolved `paint` on parsed shapes (fast, no rasterizer).
2. **Conformance** — `swift test --filter ConformanceSuite` (not `--filter <test-id>`; cases are parametrized).
3. **Verify visually** — compare `Tests/__SnapshotResults__/<id>/actual.png` against
   `Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/png/<id>.png` and the test's
   `<d:passCriteria>`. A `partialBaseline` row with zero diff is **not** sufficient.
   Optional programmatic pre-check: `W3CReferenceDiff.diff(testId:w3cResourcesRoot:)`
   in `Sources/SVGConformance/W3CReferenceDiff.swift` (see `CSSStylingRenderTests`).
4. **Promote** — `APPROVE_SNAPSHOTS=<id> swift test --filter ConformanceSuite` after human review.

## Anti-patterns

- ❌ Adding a new `SVGElement` case for CSS — resolve into existing paint/font fields.
- ❌ Touching `SVGRenderer` for `fill` / `stroke` / `visibility` from stylesheets.
- ❌ Trusting `__PartialSnapshots__` or `diffMaxChannel: 0` as proof of correctness.
- ❌ Parsing `<style>` with `foundCharacters` only — W3C tests wrap CSS in CDATA; handle `foundCDATA` too.
