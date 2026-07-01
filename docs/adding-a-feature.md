# Adding a new SVG feature

The canonical recipe — follow each step in order. Each step has a single,
narrow responsibility and is independently testable.

## 1. Pick the spec section

- Identify the SVG 1.1 chapter (e.g. *Basic Shapes*, *Paths*, *Painting*).
- Note the W3C test filename prefix for the chapter (`shapes-`, `paths-`,
  `painting-`, `coords-`, `pservers-`, `struct-`, `styling-`, `masking-`,
  `text-`, `filters-`, …).

## 1a. Read the target test's embedded metadata FIRST

Before writing or changing any code for a specific test, open the test's own
SVG under `Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/<test-id>.svg`
and read its `<d:SVGTestCase>` block:

- **`<d:testDescription>`** — what SVG behavior the test exercises (e.g. "an
  invalid `xlink:href` on a `pattern` has no effect on the pattern").
- **`<d:passCriteria>`** — the exact visual outcome that defines a pass (e.g.
  "the test is passed if there are four green circles visible, and no red").

These two fields are the ground truth for what the render *should* look like.
Derive your expected output from them, then confirm the W3C reference PNG at
`…/W3C-SVG-1.1/png/<test-id>.png` matches that description.

> ⚠️ Do **not** trust a `Tests/__PartialSnapshots__/<test-id>/baseline.png` as
> the target — partial baselines are auto-captured from the *current* (possibly
> buggy) renderer and are explicitly unverified. If the partial baseline
> disagrees with the pass criteria, the renderer is wrong, not the criteria.
> A `partialBaseline` report row with `diffMaxChannel: 0` only means actual
> matches the partial baseline — **not** that the render is correct.

## 1b. Styling features (CSS) — parser-only path

Many `styling-*` tests need **no new element type** and **no renderer changes**.
Resolve styles into `SVGPaintProperties` / `SVGFont` at parse time instead.

| What | Where |
| --- | --- |
| `<style>` text capture | `SAXDelegate` — `foundCharacters` **and** `foundCDATA` (W3C tests use CDATA) |
| Stylesheet parsing | `Sources/SVGParser/CSSStylesheet.swift` |
| Cascade into paint | `mergePaint(into:from:parser:)` in `SVGParser.swift` |
| Cascade into font | `mergeFont(into:from:)` — extend when a test needs font props from CSS |

**Paint cascade order** (low → high priority):

1. Inherited paint from ancestors
2. Matching `<style>` class rules (document order; later rules override)
3. Inline `style="..."` attribute
4. Presentation attributes (`fill="…"`, `stroke-width="…"`, …) — win

Add a focused parser unit test under `Tests/SVGParserTests/` that asserts
resolved `paint` on shapes — no rendering required. See
[docs/styling-rollout.md](styling-rollout.md) for chapter status and next tests.

## 2. Extend the model in `SVGCore`

- Add a new `case` to `SVGElement` (e.g. `case circle(SVGCircle)`).
- Define the new struct as a value type, `Equatable + Sendable`.
- Reuse `SVGPaintProperties` and `SVGTransform` rather than inventing parallel types.

## 3. Extend the parser in `SVGParser`

- Add a `case "circle":` branch inside `SAXDelegate.didStartElement(...)`.
- Implement attribute parsing using helpers from `AttributeParsers.swift`; add
  new helpers (e.g. `path-d` grammar) when needed.
- Add a focused unit test under `Tests/SVGParserTests/` that asserts the parsed
  model. Don't render in parser tests.

## 4. Lower into render commands in `SVGRenderer`

- Add a `lower(circle:into:)` (or equivalent) in `SVGRenderTree`.
- Convert geometry into a `CGPath`, then emit `pushState` / `concatenate` /
  `fillPath` / `strokePath` / `popState` as needed. Mirror the existing rect
  lowering for opacity / transform handling.

## 5. Implement in the SwiftUI backend

- If the new feature uses an existing `SVGRenderCommand`, **no renderer changes
  are required** — the SwiftUI backend already handles all commands.
- If you need a brand-new command (e.g. clip path push/pop, gradient shading),
  add it to `SVGRenderCommand` AND extend `SwiftUICanvasRenderer.execute`.
  Keep the command CG-shaped, not SwiftUI-shaped.

## 6. Add W3C-style conformance tests

- Drop one or more SVG files under
  `Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/` named with the chapter
  prefix (e.g. `shapes-circle-basic-01.svg`).
- For complex new features, edit `Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/overrides.json`
  to skip tests that depend on unimplemented features (with a clear reason).

## 7. Approve baselines visually

```sh
APPROVE_SNAPSHOTS=1 swift test --filter ConformanceSuite
```

- Open the resulting `Tests/__Snapshots__/<test-id>/baseline.png` and verify it
  matches the W3C reference (`Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/png/<test-id>.png`)
  closely enough. The Viewer app (Phase 2) automates this side-by-side view.
  For a quick programmatic check before promoting, see `W3CReferenceDiff.diff(testId:w3cResourcesRoot:)`
  in `Sources/SVGConformance/W3CReferenceDiff.swift`.
- Commit the baseline PNG alongside the code change.

## 8. Verify no other chapters regressed

```sh
swift test
```

- Every previously-passing snapshot must still pass with no `APPROVE_SNAPSHOTS=1`.
- The auto-generated [docs/conformance/conformance-report.json](conformance/conformance-report.json) shows status per test.

## Anti-patterns

- ❌ Adding a `SwiftUI` import to `SVGCore` or `SVGRenderer`.
- ❌ Inlining new geometry inside the parser (use `SVGCore` types).
- ❌ Re-approving a baseline without visually inspecting the new image.
- ❌ Marking a failing test as `skip` instead of fixing the renderer — only
  skip when the test depends on a feature that genuinely is not yet implemented.
- ❌ Treating a `__PartialSnapshots__` baseline as the correct target instead of
  reading the test's `<d:passCriteria>` (see step 1a).
