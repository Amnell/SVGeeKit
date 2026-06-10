# Test tagging

Every conformance test carries a single `SVGFeatureTag` so the report can group
pass/fail counts by SVG chapter.

## Automatic tagging

`SVGFeatureTag.fromW3CFilename(_:)` derives the tag from the leading
chapter prefix of the W3C filename:

| Filename prefix | Tag |
| --- | --- |
| `shapes-…`   | `.shapes` |
| `paths-…`    | `.paths` |
| `painting-…` | `.painting` |
| `coords-…`   | `.coords` |
| `pservers-…` | `.pservers` |
| `struct-…`   | `.struct` |
| `styling-…`  | `.styling` |
| `masking-…`  | `.masking` |
| `text-…`     | `.text` |
| `filters-…`  | `.filters` |
| (unrecognized) | `.other` |

## Overrides

`Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/overrides.json` accepts
per-test entries keyed by test id (filename without extension):

```json
{
  "filters-blend-01-b": {
    "skip": "feBlend not implemented yet"
  },
  "interact-events-01-t": {
    "tag": "interact"
  },
  "text-fonts-02-t": {
    "skip": "depends on SVG fonts loading"
  }
}
```

- `tag` — replaces the filename-derived tag.
- `skip` — marks the test as `.skipped` in the conformance report with the
  supplied reason. Use this **only** when the feature genuinely isn't implemented
  yet — never as a way to silence a regression.

## Adding a new chapter

If you start vendoring tests from a chapter that doesn't have an enum case yet,
add it to `SVGFeatureTag` in
[Sources/SVGConformance/FeatureTags.swift](../Sources/SVGConformance/FeatureTags.swift).
The case `rawValue` must match the filename prefix lowercased.
