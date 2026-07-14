# SVGeeKit Static Profile 1.0 (draft)

The public contract for production SVG rendering. Anything listed **Supported** must render
correctly for self-contained documents. Anything **Unsupported** is ignored or rejected
per [security-model.md](security-model.md). Anything **Out of scope** is not part of v1.

Update this document when features land. Tag matching W3C chapters in
[test-tagging.md](../test-tagging.md).

## Document requirements

| Requirement | Status |
| --- | --- |
| Single root `<svg>` | Supported |
| `viewBox`, `width`, `height`, `preserveAspectRatio` | Supported |
| Self-contained bytes (no external fetches) | Required |
| `xml:space` on text | Supported (partial) |
| XML namespaces on root | Supported |

## Elements

### Supported (v1 target)

| Element | Notes |
| --- | --- |
| `svg` | Root and nested `<svg>` in definitions |
| `g` | Grouping, inherited paint, transforms |
| `defs` | Definition container |
| `rect`, `circle`, `ellipse`, `line`, `polyline`, `polygon` | Basic shapes — W3C `shapes` chapter verified (30/30) |
| `path` | Path data (`d`) — W3C `paths` chapter verified (19/19 non-skipped; `paths-dom-*` skipped) |
| `use` | **`href="#id"` / `xlink:href="#id"` only** — same document |
| `linearGradient`, `radialGradient`, `stop` | Paint servers in `defs` |
| `pattern` | Tiled paint; fragment refs only |
| `clipPath` | Clipping |
| `mask` | Alpha / luminance masking |
| `image` | **`data:` URIs and app-supplied bytes only** |
| `text`, `tspan` | System fonts; see [font-rollout-plan.md](../font-rollout-plan.md) |
| `style` | Author stylesheet (`type="text/css"`) |
| `switch` | Conditional processing (`systemLanguage`, `requiredFeatures`, …) |
| `symbol` | Stored in `defs`; instanced via `<use>` |

### Tier 2 (should ship in v1)

| Element | Notes | Status |
| --- | --- | --- |
| `marker` | Arrowheads / path decorations | Not implemented |
| `font`, `font-face`, `glyph`, `missing-glyph` | **Inline in document only** — no `font-face-uri` fetch | Not implemented |
| `textPath` | Text on a path | Not implemented |

### Tier 3 (optional v1.1)

| Element | Notes | Status |
| --- | --- | --- |
| `filter` | Curated primitive subset only — see [filters-plan.md](filters-plan.md) | Not implemented |
| `feGaussianBlur`, `feOffset`, `feMerge`, `feFlood`, `feComposite`, `feBlend`, `feColorMatrix` | Subset of filter primitives | Not implemented |

### Unsupported (graceful ignore + warning)

| Element | Behavior |
| --- | --- |
| Unknown elements | Skip subtree; `SVGParseWarning.unsupportedElement` |
| `script` | Never executed; optional metadata capture only |
| `animate`, `set`, `animateTransform`, `animateMotion` | Ignored in production |
| `foreignObject` | Ignored |
| `a` | Ignored (hyperlink; no navigation) |
| `view` | Ignored (fragment navigation) |
| Filter primitives not in [filters-plan.md](filters-plan.md) | Ignored |

## Attributes (selected)

### Supported paint & geometry

`fill`, `stroke`, `fill-opacity`, `stroke-opacity`, `opacity`, `fill-rule`,
`stroke-width`, `stroke-linecap`, `stroke-linejoin`, `stroke-miterlimit`,
`stroke-dasharray`, `stroke-dashoffset`, `transform`, `display`, `visibility`,
`clip-path`, `mask`, `clip-rule`, `color`

### Supported text

`font-family`, `font-size`, `font-weight`, `font-style`, `text-anchor`, `dx`, `dy`,
`rotate` (deferred assignment in parser)

### Supported linking (fragment only)

| Attribute | Allowed values |
| --- | --- |
| `href`, `xlink:href` on `use`, gradients, patterns | `#id` fragments in the same document |
| `href` on `image` | `data:image/...` only |

### Unsupported / restricted

| Attribute / feature | Policy |
| --- | --- |
| External `href` / `xlink:href` (`http:`, `https:`, relative paths) | **Warn + skip** — see [security-model.md](security-model.md) |
| `filter="url(#id)"` | Unsupported until [filters-plan.md](filters-plan.md) lands |
| `marker-start` / `marker-mid` / `marker-end` | Unsupported until `<marker>` lands |
| `color-interpolation`, `color-interpolation-filters` | Unsupported (sRGB only) |
| `vector-effect` | Unsupported in v1 |
| Event handler attributes (`onclick`, …) | Ignored in production |
| `requiredExtensions` | Treated as unsupported feature |

## CSS

| Feature | Status |
| --- | --- |
| Presentation attributes | Supported |
| Inline `style="..."` | Supported |
| `<style>` class selectors (`.foo`) | Supported |
| `<style>` type selectors (`rect { }`) | Supported |
| Specificity / inheritance per SVG 1.1 cascade | In progress — [styling-rollout.md](../styling-rollout.md) |
| CSS `filter:` property | Out of scope for v1 |
| `@font-face` in CSS | Out of scope for v1 |

## Color & compositing

| Feature | Policy |
| --- | --- |
| sRGB colors (`#rgb`, `rgb()`, named colors) | Supported |
| `currentColor` | Supported |
| `color-interpolation=linearRGB` | Unsupported |
| Premultiplied alpha raster output | Yes (snapshot harness) |

## Parser & SwiftUI API

| API | Throws? | On failure |
| --- | --- | --- |
| `SVGParser.parse(…)` | Yes (hard failures) | `SVGParseError`; soft issues → `SVGParseReport.warnings` |
| `SVGImageView(document:)` | No | Requires pre-parsed document |
| `SVGImageView(svgData:)` | No | Empty canvas — nothing rendered |
| `SVGRenderTree.lower` | No | Skip bad nodes; no trap |

See [security-model.md](security-model.md) for the full resilience model.

## Modules

| SwiftPM product | v1 production |
| --- | --- |
| `SVGKit` | **Required** — parse + render static SVG |
| `SVGScript` | Optional; not part of static profile |
| `SVGAnimation` | Optional; not part of static profile |

## Integrator checklist

Before shipping an asset library against SVGeeKit v1, verify each file:

- [ ] No `http:` / `https:` / relative `href` references
- [ ] No `<script>` reliance for initial render
- [ ] No SMIL `<animate>` for initial render
- [ ] Text uses system-available `font-family` (or inline SVG fonts)
- [ ] Effects are paths/gradients, or documented as requiring [filters-plan.md](filters-plan.md)
- [ ] Raster images embedded as `data:` URIs if needed
