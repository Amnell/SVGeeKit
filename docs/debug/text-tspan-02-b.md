# Debug report: `text-tspan-02-b`

Status as of 2026-06-23. **Parser slice done** — character-stream `xml:space` normalization
and deferred `rotate` assignment land in `TextCharacterStream.swift` + `finalizeTextRuns`.
Green-text parser test `normalizesTextCharacterStreamForTspan02GreenText` passes.
**Visual conformance still open** — run `text-tspan-02-b` against W3C reference before
snapshot approval. Do not add run-boundary whitespace heuristics.

Committed: rotate parsing + partial baseline (`63624bc`). Renderer: rotated pen
advance, single-`x` semantics, skip anchor for rotated text (`TextLayout.swift`).
Parser heuristic WIP **reverted** — replaced by character-stream normalization.

## What this test checks

[W3C SVG `text-tspan-02-b.svg`](../../Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/text-tspan-02-b.svg) exercises the `rotate` attribute on `<text>` and nested `<tspan>` elements:

- Lists longer than character count (last value repeats)
- Lists shorter than character count (unused values propagate to child tspans without `rotate`)
- Ancestor `rotate` inherited by descendants without their own `rotate`
- `rotate` continues across text interrupted by nested tspans

**Pass criteria:** The green sentence *"Not all characters in the text have a specified rotation"* must fully cover the red reference (wrong) rendering beneath it. Any visible red = fail.

The SVG also draws small rotation annotation numbers (`#rotation_values`, `xml:space="preserve"`) and a red duplicate of the sentence for comparison.

## Symptom

Our render does **not** match the W3C reference PNG:

| Metric | Our render vs W3C reference |
| --- | --- |
| Pixel mismatch | ~15–16% |
| Red pixels visible | ~5,000+ (should be ~0 when green is correct) |
| Green coverage | Present but mis-positioned |

Visual issues observed:

1. **Red bleeding through** — green glyphs do not fully occlude the red layer.
2. **Overlapping / stacked glyphs** — especially `"text"` (child4 tspan) and dense runs like `"specified"`.
3. **Diagonal / fan layouts** — some runs (e.g. `"rotation"` at 55°) spread diagonally; partially expected per spec, but ours is worse than reference.
4. **Messy first line** — red and green interleave on `"all characters in the"`.

Partial baseline (`Tests/__PartialSnapshots__/text-tspan-02-b/`) matches **our** broken render (0% self-drift), not the W3C PNG. Do not promote until reference-aligned.

## Architecture (relevant pieces)

```
Parse (SVGParser)
  → SVGText.runs[] with per-run string, font, paint, explicitX/Y, rotations[]
Finalize (finalizeTextRuns) — whitespace cleanup
Layout (TextLayout.layoutCharacterPositions)
  → per-char CGPoint + rotation
  → SVGFontTextLayout / SystemTextLayout glyph paths
Render (SVGRenderer) — red text first, green on top
```

Font: `SVGFreeSansASCII` via `@font-face` URI (same as other text tests).

## Root causes identified

### 1. Renderer: single `x` on `<tspan>` stacked all glyphs (fixed in WIP)

**Bug:** `explicitPositions` repeated the sole `x` value for every character:

```swift
// OLD — wrong for x="20" on a 4-char run "text"
xs[min(i, xs.count - 1)]  // all glyphs at x=20
```

**SVG rule:** A single `x` sets the position of the **first** character only; subsequent characters advance via glyph widths (in the rotated coordinate system).

**Fix (WIP):** `layoutCharacterPositions` in `TextLayout.swift` — use explicit `xs[i]` only when `i < xs.count`; otherwise continue from pen.

**Affects:** child4 `<tspan x="20" y="180">text</tspan>` in the green text block.

### 2. Renderer: rotation did not advance the pen (fixed in WIP)

**Bug:** Glyphs were rotated at their positions, but the pen always advanced horizontally by full string width. SVG requires advance in the **rotated** coordinate system:

```
nextPen = pos + (advance * cos(θ), advance * sin(θ))
```

**Fix (WIP):** Unified `layoutCharacterPositions` for all runs (explicit-x and flowing). Added `charAdvance` per character in `SVGFontTextLayout` and `SystemTextLayout`.

### 3. Renderer: `text-anchor` shift with rotated text (fixed in WIP)

**Bug:** `applyAnchorShift` aligned bounding box to `text.origin.x`. With rotated glyphs, `bounds.minX` ≠ first glyph anchor → spurious horizontal shift (same class of bug as `text-tspan-01-b` explicit-x).

**Fix (WIP):** Skip `applyAnchorShift` when any run has `rotations != nil` (in addition to `explicitX`).

### 4. Parser: `rotate` consumed before whitespace stripped (partially fixed in WIP)

**Bug:** Leading XML indentation/newlines were in the run string when `rotate` values were consumed, so `"Not"` could get angles meant for discarded whitespace, or later chars got repeating `55°`.

**Fix (WIP):** In `flushActiveTextRun`, strip formatting whitespace and trim leading (first run) / excess trailing **before** consuming from `RotateCursor`.

**Also:** When a child `<tspan rotate="…">` opens, exhaust parent's unused rotate indices (SVG propagation — parent values are skipped, child's list takes over).

### 5. Parser: inter-run whitespace is still wrong (open)

**Bug:** `green.string` from parser does not match expected collapsed text:

```
Actual:   "Not        all characters          in            thetext        have a        specifiedrotation"
Expected: "Not all characters in the text have a specified rotation"
```

Contributing factors:

| Issue | Detail |
| --- | --- |
| Internal space runs | XML indentation left as multiple spaces **inside** runs (e.g. `"all characters          "`) |
| Dropped separator runs | Whitespace-only runs between tspans are **removed** in `finalizeTextRuns`, losing word separators → `"thetext"` |
| `trimExcessTrailing` on whitespace-only | If a run is only spaces, `trimExcessTrailing` (>2 rule) can empty it before finalize converts it to a separator |
| Order of operations | `handleTspanStart` flushes whitespace **before** `x`/`y` are applied to the new tspan, so inter-tspan space runs don't get `explicitX` |

**Impact:** Even with correct layout math, **extra space characters in run strings** lay out additional (invisible) glyphs at wrong rotations, spreading text horizontally and leaving red visible.

**Attempted fixes (reverted or incomplete):**

- `collapseInternalWhitespace` per run + sync rotations array
- Convert whitespace-only runs to `" "` instead of dropping
- `dedupeSeparatorSpaceRuns` between runs
- Discard whitespace before explicit-x tspan when previous run already ends with space

These conflict with other tests (`collapsesWhitespaceAndFlattensTspan`, `parsesTspanExplicitXYWithoutLeadingWhitespaceRun`, `stripsIgnorableWhitespaceFromIndentedTextRuns`).

### 6. Parser: rotation list propagation (likely correct for simple cases)

`RotateCursor` stack + exhaust-on-child-open handles the basic case verified by `parsesTspanRotatePropagation` and first run of green text:

```
run[0] "Not" → rotations [5, 15, 25]  ✓
child4      → explicitX [20], explicitY 180, string "text"  ✓ (after leading trim on positioned runs)
last run    → "rotation" with all 55°  ✓ (when whitespace fixed)
```

Complex nested propagation (child2 excess → child3 `"the"`, child1 `-40°` → child4) not yet validated run-by-run against spec.

## Files touched (uncommitted WIP)

| File | Changes |
| --- | --- |
| `Sources/SVGRenderer/TextLayout.swift` | `layoutCharacterPositions`, `charAdvance`, skip anchor for rotations |
| `Sources/SVGRenderer/SystemTextLayout.swift` | `charAdvance`, rotation on positioned glyphs |
| `Sources/SVGParser/SVGParser.swift` | `RotateCursor` exhaust, flush-time whitespace, `trimExcess*` helpers, `handleTspanStart` whitespace discard heuristic |
| `Tests/SVGParserTests/SVGParserTests.swift` | `parsesTextTspan02GreenTextRuns` (diagnostic; currently fails on `green.string`) |

## Test status

| Test | Status |
| --- | --- |
| Full `swift test` (conformance) | Passes (partial baseline never fails CI) |
| `parsesTspanRotatePropagation` | Pass |
| `parsesTextTspan02GreenTextRuns` | **Fails** on `green.string` whitespace |
| `parsesTspanExplicitXYWithoutLeadingWhitespaceRun` | May fail when whitespace heuristics enabled |
| `text-tspan-01-b` | Should re-verify after layout changes (explicit-x + anchor) |

## Recommended next steps

### A. Character-stream `xml:space` (prerequisite — do this first)

Implement at `</text>`, not as per-run heuristics:

1. SAX collects raw span chunks + style + `rotate` frame open/close events.
2. Walk spans in order; apply `xml:space="default"` / `preserve` to produce one
   layout character stream (spaces between nested tspans are real characters).
3. Run `RotateCursor` once per normalized character; slice `rotations[]` back into runs.
4. Group adjacent same-style characters into `SVGTextRun[]` (or keep runs aligned
   1:1 with normalized substrings).

Add a table-driven parser test after step 3: each green-text run's `string` +
`rotations` vs pass-criteria bullets in the SVG.

### B. Verify renderer (after parser fix)

Renderer layout is already spec-aligned:

- Rotated pen advance
- Single `x` on `<tspan>`
- Skip `text-anchor` when `explicitX` or `rotations` present

Re-run conformance; compare `actual.png` to W3C PNG.

### C. Annotation text (`#rotation_values`)

Separate follow-up: `xml:space="preserve"` + explicit `x` on many small tspans.

### D. Re-approve workflow

Only after visual match to W3C PNG:

```sh
swift test --filter ConformanceSuite/text-tspan-02-b
# inspect Tests/__SnapshotResults__/text-tspan-02-b/actual.png vs W3C png
APPROVE_SNAPSHOTS=text-tspan-02-b swift test --filter ConformanceSuite
```

## Abandoned approach (do not continue)

Run-boundary heuristics (inject separator on dropped whitespace runs, `explicitX`
exceptions, newline-based `trimLeading`, `trimExcess` thresholds) cannot satisfy
`text-tspan-02-b` and existing parser tests (`collapsesWhitespaceAndFlattensTspan`,
`stripsIgnorableWhitespaceFromIndentedTextRuns`, `parsesTspanExplicitXYWithoutLeadingWhitespaceRun`)
simultaneously. The spec is character-stream first; heuristics patch symptoms only.

## Quick repro commands

```sh
# Run single conformance test (updates partial baseline + actual.png)
swift test --filter ConformanceSuite/text-tspan-02-b

# Parser diagnostic (add after character-stream slice lands)
# swift test --filter parsesTextTspan02GreenTextRuns

# Compare output paths
open Tests/__SnapshotResults__/text-tspan-02-b/actual.png
open Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/png/text-tspan-02-b.png
```

## Reference: green text DOM structure

```xml
<text font-size="35" fill="green" x="20" y="120" rotate="5,15,25,35,45,55" stroke="green" stroke-width="0.5">
  Not
  <tspan rotate="-10,-20,-30,-40">all characters
    <tspan rotate="70,60,50,40,30,20,10">in
      <tspan>the</tspan>
    </tspan>
    <tspan x="20" y="180">text</tspan>
    have a
  </tspan>
  <tspan rotate="-10">specified</tspan>
  rotation
</text>
```

Expected rotations (from pass criteria):

| Text | Rotations (degrees) |
| --- | --- |
| `Not` | 5, 15, 25 |
| `all characters` (first 4) | −10, −20, −30, −40; then −40 |
| `in ` | 70, 60, 50 (+ space consumes one) |
| `the` | 40, 30, 20 (propagated from child2) |
| `text` | −40 (inherited) |
| `have a` | −40 |
| `specified` | −10 |
| `rotation` | 55 |

Spaces between words consume rotate values per spec ("the space in the text consumes a rotate value").

## Related prior fixes (same branch)

- `text-tspan-01-b`: whitespace between tags, `text-anchor` vs explicit `x`, FreeSerif bold — **passed / snapshot approved** (`e1d42ad`).
- Same whitespace lessons apply here but `rotate` makes run/run boundaries and per-char alignment critical.
