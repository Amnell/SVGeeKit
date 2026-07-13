# Filters plan (optional v1.1)

SVG `<filter>` support is **not required for v1**. Browsers implement it broadly, and
design-tool exports sometimes use blur and drop-shadow filters — but full SVG 1.1 filters
(43 W3C tests) is effectively a second rendering engine.

Implement this plan only after [roadmap.md](roadmap.md) Phases 0–5, or when a concrete
asset corpus blocks release.

Cross-reference: [static-profile.md](static-profile.md) Tier 3.

## Browser reality

| Feature | Chrome | Safari | Firefox |
| --- | --- | --- | --- |
| SVG `<filter>` | Yes | Yes | Yes |
| `feGaussianBlur` | Yes | Yes | Yes |
| `feOffset` + `feMerge` (drop shadow) | Yes | Yes | Yes |
| `feColorMatrix` | Yes | Yes | Yes |
| Lighting (`feDiffuseLighting`, …) | Yes | Yes | Yes |
| `feTurbulence`, `feDisplacementMap` | Yes | Yes | Yes |
| CSS `filter:` on SVG elements | Yes | Yes | Yes |

SVGeeKit v1 does **not** target CSS `filter:` — only SVG filter elements, and only the
subset below.

## Recommended subset

### Implement (high value / moderate cost)

| Primitive | Typical use |
| --- | --- |
| `filter` | Container; `filterUnits`, `primitiveUnits`, `x/y/width/height` |
| `feGaussianBlur` | Blur, shadow softness |
| `feOffset` | Drop shadow displacement |
| `feFlood` | Solid color for shadow |
| `feComposite` | Combine flood with alpha |
| `feMerge` / `feMergeNode` | Layer shadows with source graphic |
| `feBlend` | Simple blend modes (`normal`, `multiply`, …) |
| `feColorMatrix` | Tint, saturation, opacity matrix |

### Defer (low ROI for static app icons)

| Primitive | Reason |
| --- | --- |
| `feConvolveMatrix` | Rare in app assets |
| `feDisplacementMap` | Rare; needs `feImage` |
| `feTurbulence` | Procedural noise |
| `feMorphology` | Erode/dilate |
| `feTile` | Tiling |
| `feDiffuseLighting`, `feSpecularLighting`, `feDistantLight`, `fePointLight`, `feSpotLight` | 3D lighting — very rare |
| `feImage` | External image refs conflict with [security-model.md](security-model.md) |
| `feComponentTransfer`, `feFuncR/G/B/A` | Niche color curves |

## Architecture sketch

Filters require an **offscreen render graph** before the existing command stream:

```
Element subtree → rasterize to alpha buffer (filter region)
    → apply filter primitive chain (DAG)
    → composite result back into parent
```

### Module placement

| Module | Responsibility |
| --- | --- |
| `SVGCore` | `SVGFilter`, `SVGFilterPrimitive` value types |
| `SVGParser` | Parse `<filter>` and subset primitives in `defs` |
| `SVGRenderer` | `SVGRenderCommand.applyFilter` or pre-pass filter lowering |
| `SVGRendererSwiftUI` | `CIFilter` or `CGContext` blur/offset/composite |

### Apple platform shortcut

For the recommended subset, consider mapping to Core Image:

- `feGaussianBlur` → `CIGaussianBlur`
- `feColorMatrix` → `CIColorMatrix`
- `feOffset` → `CIAffineTransform` + translate
- `feComposite` / `feBlend` → `CIBlendWithMask`, `CISourceOverCompositing`

Keep the `SVGRenderCommand` representation backend-neutral; implement CI in
`SVGRendererSwiftUI` / `CGContextRenderer` only.

### Color space

v1 raster output is **sRGB**. Do not implement `color-interpolation-filters=linearRGB`
unless a promoted W3C test proves otherwise.

## W3C conformance targets (subset)

Do not aim for all 43 `filters-*` tests initially. Suggested landing order:

| Test | Exercises |
| --- | --- |
| `filters-gauss-01-b` | `feGaussianBlur` uniform stdDeviation |
| `filters-offset-01-b` | `feOffset` |
| `filters-offset-02-b` | Offset + blur chain |
| `filters-felem-01-b` | `filter` on element |
| `filters-blend-01-b` | `feBlend` |
| `filters-color-01-b` | `feColorMatrix` |
| `filters-overview-01-b` | Multi-primitive chain |

Remove `filters` from `skipTags` in `overrides.json` only when the first primitive lands.

## Implementation checklist

### Model & parser

- [ ] `SVGFilter` definition in `SVGCore` (`id`, `filterUnits`, `x`, `y`, `width`, `height`)
- [ ] Primitive enum: gaussianBlur, offset, flood, composite, merge, blend, colorMatrix
- [ ] Parse `filter="url(#id)"` on shapes / groups
- [ ] Parse `in`, `in2`, `result` primitive wiring
- [ ] Reject `feImage` with external `href`

### Renderer

- [ ] Compute filter region (`objectBoundingBox` vs `userSpaceOnUse`)
- [ ] Rasterize filtered subtree to intermediate buffer
- [ ] Execute primitive chain
- [ ] Composite filtered output at correct transform

### Tests

- [ ] Unit tests per primitive (parser + region math)
- [ ] Snapshot tests for landing order table above
- [ ] Performance benchmark entry in `Benchmarks` for blur-heavy SVG

### Documentation

- [ ] Update [static-profile.md](static-profile.md) Tier 3 → Supported
- [ ] Document integrator fallback: "flatten effects in design tool"

## Exit criteria

- [ ] Curated subset renders correctly for landing-order W3C tests
- [ ] No external `feImage` fetch
- [ ] Filter performance documented (blur is expensive on large regions)
- [ ] Remaining `filters-*` tests either skipped with reason or passing

## Alternative: document as unsupported

If Phase 6 is cut from schedule, state clearly in README and static profile:

> SVG filter effects are not supported. Flatten blur and shadow in your design tool, or
> pre-render filtered assets to PNG.

This is acceptable for icon-first use cases (Heroicons, SF Symbols style assets).
