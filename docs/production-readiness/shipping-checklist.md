# Shipping checklist (v1)

Gates for calling SVGeeKit production-ready. Complete after [roadmap.md](roadmap.md)
Phases 0–5 (Phase 6 filters optional).

Check items off as they land. Link PRs or issues inline if helpful.

---

## 1. Feature completeness

- [ ] [static-profile.md](static-profile.md) reflects implemented reality (no stale "Supported" rows)
- [x] [security-model.md](security-model.md) Phase 0 checklist complete
- [ ] Tier-1 W3C tags at roadmap pass-rate targets (`color` 5/6; `struct` still below 45+)
- [~] `masking` chapter substantially passing (15/15 runnable; 3 non-filter + 1 filter skip remain)
- [ ] System-font `text` working for typical labels
- [ ] `<marker>` or documented workaround in static profile
- [ ] `partialBaseline` count ≤30 across in-profile tags (see Phase 5; currently 82 total / 16 struct)

---

## 2. Public API

### Parser

- [ ] `SVGParser.parse(data:options:)` with documented `SVGParser.Options`
- [ ] `SVGParser.parse(string:options:)`
- [ ] `parse(data:) throws -> SVGParseResult` with warnings for soft failures
- [ ] `SVGImageView(svgData:)` — non-throwing; empty layout on hard parse failure
- [ ] Document: parser `throws` on hard errors; views never throw
- [ ] `SVGParseError` cases cover limit exceeded, rejected href, malformed XML
- [ ] `SVGParseReport` (or equivalent) exposes warnings / unsupported elements
- [ ] No `baseURL` parameter on production API (or documented as test-only)

### Renderer

- [ ] `SVGRenderTree.lower(_:)` stable for profile elements
- [ ] `SVGRasterizer.rasterize(_:pixelSize:scale:)` documented color space (sRGB)
- [ ] `SVGImageView` documented for SwiftUI integration
- [ ] `SVGRendererBackend` protocol sufficient for a second backend (CoreGraphics headless)

### Capabilities

- [ ] `SVGCapabilities` (or static profile constant) listing supported elements
- [ ] Runtime query: `SVGCapabilities.isSupported(elementName:)` (optional but valuable)

---

## 3. Security & robustness

- [ ] External URI rejection tested
- [ ] Parse limits tested (oversized doc, deep nesting, huge path)
- [ ] No script execution in default `SVGKit` product
- [ ] `foreignObject` cannot embed HTML into render tree
- [ ] Fuzz or corpus test: hostile SVG never traps; malformed input `throws` or yields empty view

---

## 4. Performance

- [ ] `Benchmarks` executable documented in README (already present)
- [ ] Baseline numbers recorded for reference corpus (release notes or `docs/benchmarks.md`)
- [ ] No O(n²) surprises on deep `use` chains or large `defs`
- [ ] Filter note: if Phase 6 skipped, N/A; if shipped, document cost

---

## 5. Documentation

- [ ] README updated (remove "Phase 1 vertical slice / rect only" stale text)
- [ ] README links to [production-readiness/](README.md)
- [ ] [static-profile.md](static-profile.md) published as integrator contract
- [ ] Migration note: external href removal breaking change
- [ ] License filed (README says TBD)
- [ ] AGENTS.md table includes production readiness link

---

## 6. Testing & CI

- [ ] `swift test` green on macOS CI
- [ ] `ConformanceSuite` gate on `Tests/__Snapshots__/` (verified baselines)
- [ ] `__PartialSnapshots__` never fail CI (already the case)
- [ ] Conformance report committed or CI artifact on each run
- [ ] Parser unit tests for every new profile feature
- [ ] At least one integration test: parse real-world icon SVG corpus (in-repo samples)

---

## 7. Optional modules (explicitly separate)

- [ ] `SVGScript` not a dependency of `SVGKit`
- [ ] `SVGAnimation` not a dependency of `SVGKit`
- [ ] README states optional modules are conformance / tooling only

---

## 8. Release

- [ ] Version tagged (SemVer `0.x` → `1.0.0` when checklist complete)
- [ ] CHANGELOG entry: supported profile, breaking security changes, known gaps
- [ ] SPM minimum platforms documented (iOS 17+, macOS 14+)
- [ ] Known limitations section: filters, textPath, external fonts, animation, script

---

## Known limitations template (for CHANGELOG / README)

Copy and trim at release:

```markdown
### Supported
- Self-contained SVG 1.1 static graphics: shapes, paths, gradients, patterns,
  transforms, CSS styling, clip-path, mask, system-font text, fragment-based `<use>`.

### Not supported
- External resource references (`http:`, relative paths, `font-face-uri` fetch)
- JavaScript and DOM mutation
- SMIL animation
- Hyperlinks and `<view>` navigation
- `foreignObject`
- SVG filter effects (or: blur/shadow subset only — see static profile)
- `textPath`, `altGlyph`, complex bidi text
- `color-interpolation=linearRGB`
```

---

## Post-v1 backlog

Track here or in issues; not blocking ship:

- [ ] [filters-plan.md](filters-plan.md) curated subset
- [ ] `textPath`
- [ ] `SVGRendererCoreGraphics` headless backend
- [ ] Metal backend
- [ ] Hit testing without scripts
- [ ] PDF export
