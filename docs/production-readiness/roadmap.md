# Production roadmap

Phased checklist for SVGeeKit v1. Work top-to-bottom; do not skip Phase 0 before
shipping. Each item should land with tests per [adding-a-feature.md](../adding-a-feature.md).

**Status key:** `[ ]` not started · `[~]` in progress · `[x]` done

Update conformance targets after `swift test` regenerates
[conformance-report.json](../conformance/conformance-report.json).

---

## Phase 0 — Security model

**Goal:** No external resource fetch in production parse path.

**Doc:** [security-model.md](security-model.md)

- [ ] Gate/remove external `<image href="file.svg">` resolution in `SVGParser`
- [ ] Reject external `href` / `xlink:href` in production (warn + skip, no throw)
- [ ] Add `SVGParser.Options` resource limits
- [ ] Add `SVGParseReport` warnings
- [ ] Unit tests for URI policy

**Exit criteria:** Untrusted SVG bytes cannot trigger filesystem or network I/O through
`SVGKit` alone.

---

## Phase 1 — Core static rendering

**Goal:** Solid Tier-1 geometry, paint, gradients, structure, and CSS styling.

**Docs:** [styling-rollout.md](../styling-rollout.md), [adding-a-feature.md](../adding-a-feature.md)

### 1a. Shapes, paths, coords (mostly done)

| Target | Baseline | Goal | Status |
| --- | ---: | ---: | --- |
| `shapes` passed | 27 | 30 | `[~]` |
| `paths` passed | 19 | 21 | `[~]` |
| `coords` passed | 28 | 28+ | `[~]` |

- [x] Basic shapes (`rect`, `circle`, `ellipse`, `line`, `poly`, `path`)
- [x] Transforms, `viewBox`, coordinate units
- [ ] Remaining `paths-*` edge cases (read pass criteria per test)
- [ ] Promote `shapes` partial baselines after visual verification

### 1b. Painting

| Target | Baseline | Goal | Status |
| --- | ---: | ---: | --- |
| `painting` passed | 20 | 24+ | `[~]` |

- [x] Fill, stroke, opacity, dash, caps/joins
- [ ] `<marker>` — moved to [Phase 4](#phase-4--structure--reuse)
- [ ] Skip / document: `color-interpolation=linearRGB` (`painting-render-02-b`)
- [ ] `painting-marker-*` — blocked on `<marker>`

### 1c. Paint servers (`pservers`)

| Target | Baseline | Goal | Status |
| --- | ---: | ---: | --- |
| `pservers` passed | 25 | 33 | `[~]` |
| `pservers` partial | 8 | 0 | `[~]` |

- [x] `linearGradient`, `radialGradient`, `pattern`
- [ ] Verify and promote 8 partial baselines against W3C PNG + pass criteria
- [ ] `gradientUnits`, `spreadMethod`, `gradientTransform` edge cases

### 1d. CSS styling

| Target | Baseline | Goal | Status |
| --- | ---: | ---: | --- |
| `styling` passed | 7 | 18 | `[~]` |
| `styling` partial | 11 | 0 | `[~]` |

Follow [styling-rollout.md](../styling-rollout.md):

- [x] Presentation attributes
- [x] Inline `style`
- [x] `<style>` class and type selectors (core)
- [ ] Inheritance (`styling-inherit-01-b`, …)
- [ ] Presentation edge cases (`styling-pres-02-f` … `05-f`)
- [ ] Promote 11 partial baselines after verification

### 1e. Document structure (`struct`)

| Target | Baseline | Goal | Status |
| --- | ---: | ---: | --- |
| `struct` passed | 23 | 45+ | `[~]` |
| `struct` partial | 31 | ≤10 | `[~]` |
| `struct` skipped (DOM) | 18 | 18 | `[x]` keep skipped |

- [x] `g`, `defs`, `use` (fragment refs)
- [x] `<switch>` conditional processing
- [x] `<image>` element (needs Phase 0 security lockdown)
- [ ] `symbol` instancing polish
- [ ] Promote high-value partial baselines (batch by test family)
- [x] Skip `struct-dom-*` — DOM API out of scope

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
- [ ] Remove `masking` from `skipTags` in `overrides.json` incrementally
- [ ] `masking-path-*`, `masking-mask-*`, `masking-opacity-*` — verify running overrides
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

- [ ] Parse inline `<font>`, `<glyph>` in `defs` (no external `font-face-uri`)
- [ ] Bundle `SVGFreeSans` inline for W3C tests OR ship test-only fixture helper
- [ ] Keep external `font-face-uri` **rejected** per [security-model.md](security-model.md)

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
| `partialBaseline` total | 121 | ≤30 | `[ ]` |
| `passed` total | 181 | 280+ | `[ ]` |

### Process (repeat per tag)

1. Filter conformance report for `partialBaseline` in the target tag.
2. For each test: read `<d:passCriteria>`, compare
   `Tests/__SnapshotResults__/<id>/actual.png` to W3C reference PNG.
3. Optional: `W3CReferenceDiff.diff(testId:…)`.
4. Fix renderer if wrong; promote with `APPROVE_SNAPSHOTS=<id>` after **human** confirmation.

### Priority order

1. `struct` (31 partial) — highest count
2. `animate` (60 partial) — **low priority** (out of production scope; only promote if needed for regression)
3. `styling` (11 partial)
4. `pservers` (8 partial)
5. `shapes` (3 partial)
6. `color` (2 partial)
7. `render` (1 partial)

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
Phase 0  Security lockdown
   ↓
Phase 1  Styling partials + pservers partials + struct partials
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
