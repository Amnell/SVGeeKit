# Production roadmap

Phased checklist for SVGeeKit v1. Work top-to-bottom. Each item should land with tests
per [adding-a-feature.md](../adding-a-feature.md).

**Status key:** `[ ]` not started · `[~]` in progress · `[x]` done

Update conformance targets after `swift test` regenerates
[conformance-report.json](../conformance/conformance-report.json).

**Implementation detail for Phase 0:** [security-implementation.md](security-implementation.md) (Steps 0–9, complete).

---

## Phase 0 — Security model

**Goal:** No external resource fetch in production parse path.

**Status:** `[x]` **Complete** (2026-07-13)

**Docs:** [security-model.md](security-model.md) · [security-implementation.md](security-implementation.md)

### Resource policy

- [x] `SVGResourcePolicy`, `SVGParserOptions`, `SVGHrefResolver`
- [x] `SVGParser()` defaults to `.production` (`.restricted` — `#fragment` + `data:` only)
- [x] Gate external `<image>` / `font-face-uri` resolution at parse time
- [x] Reject external `href` / `xlink:href` in production (warn + skip, no throw)
- [x] Gate raster loads at render time via `document.resourcePolicy`
- [x] Explicit `.localFiles(at:)` for conformance, Viewer, benchmarks (`SVGConformanceFixtureParsing`)
- [x] Remove implicit `baseURL` bridge from public parser API

### Parse reporting & limits

- [x] `SVGParseReport` / `SVGParseResult` with `SVGParseWarning`
- [x] `SVGParsingLimits` on `SVGParserOptions` (document, elements, nesting, path, data URI, defs)
- [x] Soft limit exceed → warning + skip/truncate; hard XML errors still throw

### View layer & resilience

- [x] `SVGImageView(svgData:)` — non-throwing; empty canvas on failure
- [x] Optional `parseError: Binding<Error?>` for parent state
- [x] Trap audit: no `fatalError` / `precondition` / `try!` on parser/renderer paths
- [x] `HostileInputTests` — random bytes + W3C corpus under `.production` never trap

### Tests & docs

- [x] `SVGHrefResolverTests`, `SVGParsingLimitsTests`
- [x] README documents parser-throws / view-never-throws contract
- [x] `SVGScript` / `SVGAnimation` not linked from `SVGKit` by default

**Exit criteria:** Untrusted SVG bytes cannot trigger filesystem or network I/O through
`SVGKit` alone. **Met.**

---

## Phase 1 — Core static rendering

**Goal:** Solid Tier-1 geometry, paint, gradients, structure, and CSS styling.

**Docs:** [styling-rollout.md](../styling-rollout.md), [adding-a-feature.md](../adding-a-feature.md)

### 1a. Shapes, paths, coords

| Target | Baseline | Goal | Status |
| --- | ---: | ---: | --- |
| `shapes` passed | 30 | 30 | `[x]` verified |
| `paths` passed | 19 | 19 | `[x]` verified |
| `coords` passed | 28 | 28 | `[x]` verified |

**`shapes` chapter:** all 30 non-skipped W3C tests pass with verified baselines in
`Tests/__Snapshots__/` (completed 2026-07-14).

**`paths` chapter:** all 19 non-skipped W3C tests pass with verified baselines
(completed 2026-07-14). Two `paths-dom-*` tests remain skipped — DOM API + script
mutation, out of production scope.

- [x] Basic shapes (`rect`, `circle`, `ellipse`, `line`, `poly`, `path`)
- [x] Transforms, `viewBox`, coordinate units
- [x] `rx` / `ry` clamping, single-attribute copy, `<use>` stroke overlays (`shapes-rect-03-t`)
- [x] Path `d` parsing and rendering (`paths-data-*`; `paths-dom-*` skipped)

### 1b. Painting

| Target | Baseline | Goal | Status |
| --- | ---: | ---: | --- |
| `painting` passed | 22 | 24+ | `[~]` |
| `painting` partial | 0 | 0 | `[x]` |

- [x] Fill, stroke, opacity, dash, caps/joins
- [x] `display="none"` in mask / clipPath children (`painting-control-05-f`)
- [x] Gradient `color-interpolation` sRGB + linearRGB (`painting-render-01-b`)
- [ ] `<marker>` — moved to [Phase 4](#phase-4--structure--reuse) (8 tests; required for 24+ passed)
- [ ] Skip / document: `color-interpolation` compositing (`painting-render-02-b`)

### 1c. Paint servers (`pservers`)

| Target | Baseline | Goal | Status |
| --- | ---: | ---: | --- |
| `pservers` passed | 33 | 33 | `[x]` verified |
| `pservers` partial | 0 | 0 | `[x]` |

- [x] `linearGradient`, `radialGradient`, `pattern`
- [x] `stop-opacity` independent interpolation (`pservers-grad-05-b`)
- [x] Promoted: `pservers-grad-05-b`, `pservers-grad-13-b`, `pservers-grad-16-b`, `pservers-grad-18-b`, `pservers-grad-21-b`, `pservers-grad-23-f`, `pservers-grad-24-f`, `pservers-pattern-06-f`
- [x] `<use>` fill on no-fill overlay + inherited group stroke (`pservers-grad-13-b`)
- [x] Stop offset normalization + duplicate-offset overlap (`pservers-grad-16-b`)

**`pservers` chapter:** all 33 non-skipped W3C tests pass with verified baselines
(completed 2026-07-14).

- [ ] `gradientUnits`, `spreadMethod`, `gradientTransform` edge cases

### 1d. CSS styling

| Target | Baseline | Goal | Status |
| --- | ---: | ---: | --- |
| `styling` passed | 15 | 15 | `[x]` verified |
| `styling` partial | 0 | 0 | `[x]` |
| `styling` skipped | 3 | 3 | `[x]` keep skipped |

Follow [styling-rollout.md](../styling-rollout.md):

- [x] Presentation attributes (case-sensitive XML names — `FiLl` is not `fill`)
- [x] Inline `style`
- [x] `<style>` class and type selectors (core)
- [x] Inheritance (`styling-inherit-01-b` promoted)
- [x] Presentation cascade vs style/stylesheet (`styling-pres-03-f` … `05-f`)
- [x] `!important`, `@import` (localFiles), case-insensitive CSS (`styling-css-08-f` … `10-f`, `styling-elem-01-b`)
- [x] Promoted: `styling-css-10-f` — case-insensitive CSS in `style` / `<style>` / `@import`; presentation attrs remain case-sensitive (2026-07-20)
- [x] Skip: `styling-pres-02-f` (script), `styling-css-05-b` (`:lang`/text), `styling-css-06-b` (dynamic pseudo-classes)

**`styling` chapter:** all 15 non-skipped W3C tests pass with verified baselines
(completed 2026-07-20).

### 1e. Document structure (`struct`)

| Target | Baseline | Goal | Status |
| --- | ---: | ---: | --- |
| `struct` passed | 28 | 45+ | `[~]` |
| `struct` partial | 26 | ≤10 | `[~]` |
| `struct` skipped (DOM) | 18 | 18 | `[x]` keep skipped |

- [x] `g`, `defs`, `use` (same-document `#id` refs; ids outside `<defs>` indexed for `<use>`)
- [x] External `<use xlink:href="file.svg#id">` under `.localFiles` (rejected in `.production`;
  `SVGExternalUseResolver` + shared `ExternalSVGDocumentLoader`; promoted `struct-use-04-b`, 2026-07-20)
- [x] `<?xml-stylesheet href="…css">` pre-scan for linked author CSS (required by `svgRef4.svg` in `struct-use-04-b`)
- [x] CSS/stylesheet-specified presentation preserved through `<use>` shadow tree (stroke on external shapes)
- [x] `<switch>` conditional processing
- [x] `<image>` element (production policy gates external refs; `.localFiles` for fixtures)
- [ ] `symbol` instancing polish
- [~] Promote high-value partial baselines (batch by test family; promoted `struct-use-01-t`, `struct-use-05-b` on 2026-07-20; `struct-use-06-b`/`07-b` skipped — onclick/interaction)
- [x] Skip `struct-dom-*` — DOM API out of scope

### 1f. Rendering (`render`)

| Target | Baseline | Goal | Status |
| --- | ---: | ---: | --- |
| `render` passed | 8 | 8 | `[x]` verified |
| `render` partial | 0 | 0 | `[x]` |

- [x] Implicit paint order (document order)
- [x] Group opacity — isolated compositing via `groupLayer` (`render-groups-01-b`, 2026-07-20)
- [x] `opacity` not inherited to children (SVG §14.5); per-element vs group opacity distinct

**`render` chapter:** all 8 non-skipped W3C tests pass with verified baselines
(completed 2026-07-20).

**Phase 1 exit criteria:** Core tags (`shapes`, `paths`, `coords`, `painting`, `pservers`,
`styling`, `render`, `color`) at ≥90% passed among non-skipped tests; remaining gaps
documented in [static-profile.md](static-profile.md).

---

## Phase 2 — Masking & clipping

**Goal:** Complete `clipPath` and `mask` for in-profile tests.

**Doc:** [adding-a-feature.md](../adding-a-feature.md)

| Target | Baseline | Goal | Status |
| --- | ---: | ---: | --- |
| `masking` passed | 6 | 15+ | `[~]` |

- [x] `clipPath` definitions and `clip-path` attribute (partial)
- [x] `mask` definitions and `mask` attribute (partial)
- [x] Group vs element opacity (`masking-opacity-01-b` re-approved, 2026-07-20)
- [x] Clip construction edge cases (`masking-path-08-b`: empty / hidden / display / invalid URL / paint attrs)
- [x] Mask construction edge cases (`masking-path-10-b`: empty / hidden / display / invalid URL / paint attrs)
- [ ] Remove `masking` from `skipTags` in `overrides.json` incrementally
- [ ] `masking-path-*`, `masking-mask-*` — verify running overrides
- [ ] `maskUnits`, `maskContentUnits`, luminance vs alpha
- [ ] Text + clip-path integration (see Phase 3)

**Exit criteria:** All non-filter `masking-*` tests that don't require script either pass
or have a documented unsupported sub-feature.

---

## Phase 3 — Text

**Goal:** Production text via system fonts on the path rendering pipeline.

**Doc:** [font-rollout-plan.md](../font-rollout-plan.md) (implementation detail)

| Target | Baseline | Goal | Status |
| --- | ---: | ---: | --- |
| `text` passed | 4 | 30+ | `[ ]` |
| `fonts` passed | 0 | N/A | `[ ]` |

### Production scope (system fonts)

- [ ] Path-based text lowering (`TextLayout` → glyph `CGPath` → `emitPaintedPath`)
- [ ] `text-anchor`, multi-`tspan`, `xml:space`
- [ ] Text inherits paint, `clip-path`, `mask`
- [ ] Gradients on text paths
- [ ] Remove `text` from `skipTags`; enable tests incrementally

### Conformance-only (inline SVG fonts)

- [x] Parse inline `<font>`, `<glyph>` in `defs` (conformance / `.localFiles` fixtures)
- [x] External `font-face-uri` **rejected** under `.production` per [security-model.md](security-model.md)
- [ ] Bundle `SVGFreeSans` inline for W3C tests OR ship test-only fixture helper (`.localFiles` covers corpus today)

### Defer

- [ ] `textPath` — post-v1 unless a target asset corpus requires it
- [ ] `altGlyph`, complex bidi — out of scope
- [ ] Full `fonts-*` chapter — inline fonts only; external URI tests stay skipped

**Exit criteria:** Labels and simple multi-run text render correctly with system fonts;
`text` chapter mostly passing.

---

## Phase 4 — Structure & reuse

**Goal:** Sprite sheets and diagram decorations.

| Target | Baseline | Goal | Status |
| --- | ---: | ---: | --- |
| `painting` (markers) | 0 | 7 | `[ ]` |

- [ ] `<symbol>` + `<use>` width/height / `viewBox` preservation
- [ ] `<marker>` element — `markerWidth`, `markerHeight`, `refX`, `refY`, `orient`
- [ ] `marker-start`, `marker-mid`, `marker-end` on paths
- [ ] Enable `painting-marker-*` tests in `overrides.json`

**Exit criteria:** Arrowhead / diagram SVGs render without flattening markers in the design tool.

---

## Phase 5 — Baseline verification sweep

**Goal:** Turn unverified partial baselines into trusted snapshots.

**Doc:** [snapshot-workflow.md](../snapshot-workflow.md)

| Target | Baseline | Goal | Status |
| --- | ---: | ---: | --- |
| `partialBaseline` total | 93 | ≤30 | `[ ]` |
| `passed` total | 208 | 280+ | `[ ]` |

### Process (repeat per tag)

1. Filter conformance report for `partialBaseline` in the target tag.
2. For each test: read `<d:passCriteria>`, compare
   `Tests/__SnapshotResults__/<id>/actual.png` to W3C reference PNG.
3. Optional: `W3CReferenceDiff.diff(testId:…)`.
4. Fix renderer if wrong; promote with `APPROVE_SNAPSHOTS=<id>` after **human** confirmation.

### Priority order

1. `animate` (60 partial) — **low priority** (out of production scope; only promote if needed for regression)
2. `struct` (26 partial) — highest in-profile count
3. ~~`styling`~~ — **complete** (15/15 passed, 0 partial; promoted 2026-07-20)
4. ~~`pservers`~~ — **complete** (33/33 passed, 2026-07-14)
5. ~~`render`~~ — **complete** (8/8 passed, 0 partial; promoted 2026-07-20)
6. `color` (2 partial)

`shapes` — **complete and verified** (30/30 passed, 0 partial; promoted 2026-07-14).
`pservers` — **complete and verified** (33/33 passed, 0 partial; promoted 2026-07-14).
`styling` — **complete and verified** (15/15 passed, 0 partial; promoted 2026-07-20).
`render` — **complete and verified** (8/8 passed, 0 partial; promoted 2026-07-20).

**Exit criteria:** No `partialBaseline` with `diffMaxChannel: 0` in Tier-1 tags unless
explicitly marked "known gap" in [static-profile.md](static-profile.md).

---

## Phase 6 — Filters (optional v1.1)

**Goal:** Blur, drop shadow, and simple color adjustments for design-tool exports.

**Doc:** [filters-plan.md](filters-plan.md)

**Not required for v1 ship.** Start only after Phases 0–5 or when a target asset corpus
demands it.

- [ ] See [filters-plan.md](filters-plan.md) checklist

---

## Out of scope (permanent for v1)

Do not implement for production. Keep `skipTags` entries in `overrides.json`.

| Tag / area | Tests | Notes |
| --- | ---: | --- |
| `animate` | 78 | Optional `SVGAnimation` module for spec analysis only |
| `script` | 6 | Optional `SVGScript` module; never in production API |
| `interact` | 24 | Events, cursor |
| `linking` | 12 | `<a>`, `<view>` navigation |
| `extend` | 1 | Namespace extension |
| `filters` (full) | 43 | Subset only in Phase 6 |
| DOM API (`*-dom-*`) | ~40 | Across `struct`, `coords`, `paths`, `text`, `types` |

---

## Suggested work order (summary)

```
Phase 0  Security lockdown                    [x] complete
   ↓
Phase 1  Struct partials + painting markers (Phase 4)            ← current
   ↓
Phase 2  Masking complete
   ↓
Phase 3  Text (system fonts)
   ↓
Phase 4  Markers + symbol polish
   ↓
Phase 5  Verification sweep
   ↓
Ship     shipping-checklist.md
   ↓
Phase 6  Filters subset (optional)
```

## Updating this doc

When closing a milestone:

1. Change `[ ]` → `[x]` on completed items.
2. Update baseline/goal tables from latest `conformance-report.json`.
3. Update phase status in [README.md](README.md).
