# Font & text rollout plan

Phased plan for SVG 1.1 text rendering and SVG font support in SVGeeKit.
Follows the module boundaries in [architecture.md](architecture.md) and the
feature recipe in [adding-a-feature.md](adding-a-feature.md).

## Goals

1. Render `<text>` with correct placement, paint, clip-path, and mask behaviour.
2. Load **SVG fonts** so W3C conformance tests produce deterministic output.
3. Converge on **path-based glyph rendering** so text uses the same
   `fillPath` / `strokePath` pipeline as shapes (gradients, masking bbox, future
   Metal backend).

## Current state

| Area | Status |
| --- | --- |
| Parser | `<text>`, `tspan` runs, character-stream `xml:space` at `</text>`, deferred `rotate` assignment |
| Model | `SVGFont`, `SVGText` on `SVGElement` |
| Lowering | `.drawText` command; mask wrapper with `bbox: .null`; **no** `clip-path` on text |
| Backend | CoreText `CTLineDraw` in `SwiftUICanvasRenderer`; gradients on text skipped |
| SVG fonts | Not parsed; `<font-face>` / `<font>` / `<glyph>` ignored |
| External refs | Parser has no document base URL — `font-face-uri` `xlink:href` cannot resolve |
| Conformance | `text` and `fonts` tags skipped in `overrides.json` |

## W3C suite context

- ~**525** test SVGs declare the standard `SVGFreeSansASCII` boilerplate via
  `<font-face-uri xlink:href="../resources/SVGFreeSans.svg#ascii"/>`.
- **62** `text-*` tests; **17** `fonts-*` tests.
- SVG font glyphs are already path data (`d="…"`) — the same grammar as
  `<path>`. System fonts reach paths via CoreText outline extraction.

## Architecture target

```
Parse (with baseURL)
    → SVGDocument + fontFaces + fontDefinitions
    → SVGRenderTree: layout text run → per-glyph CGPath
    → emitPaintedPath (fill, stroke, clip, mask, gradients)
    → backend executes path commands only
```

### Module responsibilities

| Module | Responsibility |
| --- | --- |
| `SVGCore` | `SVGFontFace`, `SVGFontDefinition`, `SVGGlyph`, `document.fontFaces`, `document.fonts` — pure value types, no I/O |
| `SVGParser` | Parse `<font-face>`, `<font-face-uri>`, `<font>`, `<glyph>`, `<missing-glyph>`; resolve external font SVGs when given a base URL |
| `SVGRenderer` | `TextLayout` + `GlyphSource` → combined `CGPath`; lower through `emitPaintedPath`; remove long-term dependence on `.drawText` |
| `SVGRendererSwiftUI` | Delete `drawText` / `TextFontResolver` once path lowering is complete |
| `SVGConformance` | Pass `testCase.svgURL` as parser base URL |

### Glyph source abstraction (internal to `SVGRenderer`)

```swift
// Sketch — not public API yet
struct Glyph { path: CGPath; advance: CGFloat }
protocol GlyphSource {
    func glyphs(for string: String, font: SVGFont, faces: [SVGFontFace], fonts: [String: SVGFontDefinition]) -> [GlyphRun]
}
```

- **SVG font table** — lookup by `unicode` in parsed `<glyph>` elements.
- **System font** — CoreText line → glyph runs → `CTFontCreatePathForGlyph`.
- Both feed the same path combiner and `emitPaintedPath`.

### Coordinate transform

SVG fonts and CoreText use **y-up** glyph coordinates. When building paths in
user space:

1. Scale by `font-size / units-per-em`.
2. Position each glyph at cumulative `horiz-adv-x` (or CoreText advances).
3. Apply `translate(origin.x, origin.y)` with `text-anchor` offset.
4. Flip Y (`scale(1, -1)`) once at the text-element level so baselines match
   SVG's y-down user space.

---

## Phase 1 — Infrastructure & path-based system-font text

**Objective:** Unblock text feature work without SVG fonts. Establish the path
pipeline and parser base URL.

### 1.1 Parser base URL

- Add `SVGParser.parse(data:baseURL:)` and `parse(url:)` (sync + async).
- `baseURL` resolves relative `xlink:href` / `href` for external resources.
- Thread through `SVGConformanceRunner`, Viewer (`TestStore`, `DropZoneView`),
  and `SVGParser.parse(url:)` convenience.
- Unit test: relative href resolution (mirror existing gradient href tests).

### 1.2 Path-based text lowering

- Add `Sources/SVGRenderer/TextLayout.swift` (or similar):
  - CoreText shaping for a single run (no bidi yet).
  - Extract glyph outlines → `CGMutablePath`.
  - Compute typographic width for `text-anchor`.
- Change `lower(text:)` to build a path and call `emitPaintedPath` instead of
  `.drawText`.
- Fixes for free once on the path rail:
  - `clip-path` on text
  - Real bbox for `objectBoundingBox` masks
  - Solid-color gradient-ready paint resolution (gradients when paint server
    support is extended to text bbox)

### 1.3 Keep `.drawText` temporarily (optional shim)

- Either remove `.drawText` in the same PR or leave a deprecated backend path
  behind a flag until Phase 2 lands. **Prefer removing** once path lowering
  passes parser tests and a smoke render.

### 1.4 Tests & conformance

- Parser unit tests: text with `clip-path`, `mask` attributes parsed on text
  paint (already parsed today — verify lowering).
- Add **local** conformance SVGs under `W3C-SVG-1.1/svg/` (e.g.
  `text-path-basic-01.svg`) using **system** `font-family="Helvetica"` or
  `sans-serif` — do not depend on SVGFreeSans yet.
- Leave `text` / `fonts` in `skipTags`; no W3C text chapter enablement yet.

### Exit criteria

- [x] `swift test` green; no regressions in passing snapshots.
- [x] Local `text-path-basic-01` snapshot approved.
- [x] Text with `clip-path` renders correctly in Viewer.
- [x] `.drawText` removed or marked for removal in a follow-up issue.

---

## Phase 2 — SVGFreeSans wedge (external `font-face-uri`)

**Objective:** Load the one external font the entire W3C suite depends on.

### 2.1 Model (`SVGCore`)

```swift
public struct SVGFontFace: Equatable, Sendable { /* family, weight, style, unicodeRange, src */ }
public struct SVGGlyph: Equatable, Sendable { /* unicode, advance, path or d-string */ }
public struct SVGFontDefinition: Equatable, Sendable {
    public var unitsPerEm: CGFloat
    public var ascent: CGFloat
    public var descent: CGFloat
    public var defaultAdvance: CGFloat
    public var glyphs: [UnicodeScalar: SVGGlyph]
    public var missingGlyph: SVGGlyph?
}
// SVGDocument:
public var fontFaces: [SVGFontFace]   // CSS @font-face declarations
public var fonts: [String: SVGFontDefinition]  // keyed by <font id="…">
```

Store glyph `d` as parsed `CGPath` at parse time (reuse path-d parser from
`SVGParser`).

### 2.2 Parser

- Parse `<font-face>`, `<font-face-src>`, `<font-face-uri>`, `<font-face-name>`.
- On `font-face-uri` with `xlink:href="file.svg#fragment"`:
  - Resolve URL relative to document `baseURL`.
  - Parse external SVG (nested parse); extract `<font id="fragment">`.
  - Merge into `document.fonts`.
- Parse inline `<font>` / `<glyph>` / `<missing-glyph>` in `<defs>` (needed for
  Phase 3 but cheap to add here).

### 2.3 Font matching (minimal)

For Phase 2, sufficient rules:

1. Split `font-family` on commas; trim quotes.
2. Match first face where `font-family` equals `SVGFontFace.family`.
3. Resolve face → font definition via `font-face-uri` / `font-face-name`.
4. Fallback: generic `sans-serif` → system `GlyphSource`.

Defer: full `unicode-range`, weight/style selection across multiple faces.

### 2.4 Renderer

- `SVGFontGlyphSource` reads from `document.fonts`.
- Scale glyph paths: `font-size / units-per-em`.
- Wire into `TextLayout` before system fallback.

### 2.5 Tests & conformance

- Parser tests: load `SVGFreeSans.svg#ascii` from a temp directory layout mirroring
  W3C `resources/`.
- Enable individual W3C tests in `overrides.json` incrementally:
  1. `text-text-01-b` (after `textLength` — may need Phase 3 layout attrs)
  2. `text-align-01-b`, `text-align-02-b`, …
  3. `text-intro-01-t` (simple intro)
- Remove `text` from `skipTags` only when ≥1 text test is intentionally `run:
  true` and passing.

### Exit criteria

- [x] `text-align-01-b` passes snapshot against W3C reference.
- [x] Any test file's revision line (`$Revision:…$`) renders with
  SVGFreeSansASCII when body uses that family.
- [x] Parser round-trips `SVGFreeSans.svg` glyph count and a spot-check `d` path.

---

## Phase 3 — Text layout attributes

**Objective:** Pass the bulk of `text-*` tests before tackling the full
`fonts-*` chapter.

Work in roughly this order (each with parser + lowering + W3C test):

| Feature | Example tests | Notes |
| --- | --- | --- |
| `tspan` positioning | `text-tspan-01-b` | Per-tspan `x`/`y`/`dx`/`dy`; `SVGTextRun[]` model — **passed** |
| `xml:space` | `text-ws-01-t`, `text-tspan-02-b` | **Prerequisite** for per-character layout attrs. Build a normalized character stream at `</text>` before assigning `rotate` / `x` / `y` lists |
| `tspan` rotate | `text-tspan-02-b` | Parser character-stream + deferred `rotate` assignment done; visual conformance pending |
| `textLength` / `lengthAdjust` | `text-text-01-b` | `spacing` = adjust advances; `spacingAndGlyphs` = scale glyph paths |
| `writing-mode`, `direction`, `unicode-bidi` | `text-intro-02-b` | Bidi may need CoreText levels; some lines use system i18n fonts |
| `text-decoration` | `text-deco-01-b` | Underline/overline as extra paths |
| `textPath` | `text-path-01-b` | Glyph placement along `CGPath` |

### Parser: character-stream normalization

SVG 1.1 text layout is **character-stream first**. `<tspan>` boundaries change style and
open/close `rotate` frames, but `rotate`, `x`, `y`, `dx`, and `dy` are consumed per
character on the **post-`xml:space` stream** — including spaces between nested tspans.

Do **not** fix `text-tspan-02-b` with run-boundary heuristics (inject/drop separator
spaces, `explicitX` exceptions, newline sniffing). That approach fights the spec and
breaks unrelated parser tests.

Pipeline at `</text>` (implemented in `TextCharacterStream.swift`):

```
SAX → raw spans (string chunk + style + rotate-frame events + preserveSpace)
    → normalize to layout character stream (xml:space rules)
    → assign rotate / x / y per character index
    → group adjacent same-style chars into SVGTextRun[] for rendering
```

`text-tspan-02-b` green-text parser assertions pass (`normalizesTextCharacterStreamForTspan02GreenText`).
Visual conformance still open — see [debug/text-tspan-02-b.md](debug/text-tspan-02-b.md).

### Model evolution

Replace flat `SVGText.string` with structured runs when `tspan` lands:

- [x] `SVGTextRun` model (`string`, `font`, `paint`, `dx`, `dy`, `preserveSpace`)
- [x] Parser: `<tspan>` style inheritance, `dx`/`dy`, per-run paint
- [x] Renderer: multi-run layout with element-level `text-anchor`
- [x] Per-glyph `x`/`y` lists on `<tspan>` (`text-tspan-01-b` § tspan03)
- [x] Weight/style-aware `@font-face` matching (FreeSerif bold via CoreText or SVG font)
- [x] `rotate` on `<text>` / `<tspan>` — renderer (`TextLayout` rotated pen, single-`x`, skip anchor) + parser character-stream assignment ([debug report](debug/text-tspan-02-b.md))
- [x] `rotations: [CGFloat]?` per run (model + SAX flush for simple propagation)
- [x] Character-stream normalization at `</text>` (`xml:space` default + preserve boundaries)
- [x] Per-character `rotate` assignment on normalized stream (simple + nested propagation)
- [ ] `xml:space="preserve"` end-to-end (`#rotation_values` in `text-tspan-02-b`)
- [ ] `text-tspan-02-b` visual conformance (parser string/rotate aligned ✓; renderer verify)

### SVG `rotate` semantics (reference)

Per [SVG 1.1 Text — `rotate` / Example tspan05](https://www.w3.org/TR/SVG11/text.html#TSpanElementRotateAttribute):

- Per-character supplemental rotation; glyph advances occur in a **temporary rotated coordinate system**
- Spaces consume `rotate` values; last value repeats when the list is shorter than remaining characters; surplus propagates to descendant `<tspan>` elements without their own `rotate`
- When a child `<tspan>` specifies `rotate`, parent's unused values are discarded (exhausted)
- `rotate` + `xml:space="default"` require a **normalized character stream before** rotation assignment — consuming on raw SAX runs desynchronizes indices

See also [debug/text-tspan-02-b.md](debug/text-tspan-02-b.md).

```swift
public struct SVGTextRun: Equatable, Sendable {
    public var string: String
    public var origin: CGPoint?  // nil = continue from previous run
    public var font: SVGFont    // delta over parent cascade
}
public struct SVGText {
    public var runs: [SVGTextRun]
    // ...
}
```

### Exit criteria

- [ ] ≥50% of `text-*` tests passing or `partialBaseline` with known gaps
  documented.
- [ ] `text` removed from `skipTags` in `overrides.json`.

---

## Phase 4 — Inline embedded fonts (`fonts-*`)

**Objective:** Fonts chapter tests that embed `<font>` directly (e.g. Comic Sans
in `fonts-elem-02-t.svg`).

### Scope

- Fonts defined entirely inside the test SVG's `<defs>` (no external URI).
- `units-per-em` scaling (see `fonts-overview-201-t.svg` — same glyph at 10,
  1000, 10000 upem).
- Accurate glyph overlay vs reference paths (anti-aliasing tolerance).

### Out of scope for initial Phase 4

- `hkern` / `vkern`
- Multiple weights of SVGFreeSans (Bold, Italic, …) unless a test requires them
- `altGlyph`, `glyphRef`, `font-face-format`

### Exit criteria

- [ ] `fonts-elem-02-t` passes.
- [ ] `fonts` removed from `skipTags`.
- [ ] ≥10 `fonts-*` tests passing.

---

## Phase 5 — Full font matching & polish

**Objective:** Remaining font edge cases and cross-chapter text in non-text tests.

| Item | Notes |
| --- | --- |
| `unicode-range` on `font-face` | Filter faces by codepoint |
| `font-weight` / `font-style` | Match face table; map to SVGFreeSans variants |
| SVGFreeSans variants | `SVGFreeSansBold.svg`, oblique, ISO-8859-1, … |
| Kerning | `hkern`/`vkern` if tests fail without them |
| Colored text in masks | Luminance from fill colour, not alpha-only approx |
| Performance | Glyph path cache keyed by `(fontId, glyphId, size)` |

### Exit criteria

- [ ] All non-skipped `text-*` and `fonts-*` tests `passed` or explicitly
  `skip` with reason (e.g. `altGlyph` unsupported).
- [ ] Annotation text in shape/painting tests matches W3C reference when those
  chapters are enabled.

---

## Per-phase workflow (unchanged)

Each slice still follows [adding-a-feature.md](adding-a-feature.md):

1. Model in `SVGCore`
2. Parser + unit tests
3. Lowering in `SVGRenderer`
4. Backend only if new commands (Phases 1–4 should not need new commands)
5. W3C or local SVG fixture
6. Visual approve: `APPROVE_SNAPSHOTS=<id> swift test --filter ConformanceSuite`
7. Full `swift test` — no regressions

## Risk register

| Risk | Mitigation |
| --- | --- |
| Snapshot drift from system fonts in i18n tests | Prefer SVGFreeSans for ASCII; skip or relax tolerance for tests that require Arial Unicode MS |
| Recursive external SVG parse | Cap depth; cache loaded font documents by URL |
| `drawText` / path duplication during migration | Single PR removes `.drawText` once path path is default |
| `textLength` algorithm underspecified | Match W3C reference image, not a specific browser |
| Large SVGFreeSans glyph tables | Parse once; store `CGPath` in model; share across renders |
| `rotate` + run-boundary whitespace | **Resolved** — character-stream `xml:space` at `</text>` in `TextCharacterStream.swift`; do not add run-boundary heuristics |

## Suggested PR sequence

| PR | Title (suggested) | Phase |
| --- | --- | --- |
| 1 | Add parser baseURL for relative href resolution | 1.1 |
| 2 | Lower text to glyph paths via CoreText | 1.2 |
| 3 | Local text-path conformance fixture + clip-path on text | 1.4 |
| 4 | SVG font model + inline glyph parsing | 2.1–2.2 |
| 5 | font-face-uri loading (SVGFreeSans) | 2.2–2.4 |
| 6 | Enable text-align W3C tests | 2.5 |
| 7+ | One PR per text layout feature (tspan, textLength, …) | 3 |
| N | fonts-elem embedded fonts | 4 |

## References

- W3C SVG 1.1 — [Text](https://www.w3.org/TR/SVG11/text.html), [Fonts](https://www.w3.org/TR/SVG11/fonts.html)
- Test resources: `Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/resources/SVGFreeSans.svg`
- Test overrides: `Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/overrides.json`
