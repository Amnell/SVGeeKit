# Vendored W3C SVG 1.1 Second Edition test resources

This directory mirrors the layout of the official W3C SVG 1.1 Second Edition
Test Suite (16 August 2011):

```
W3C-SVG-1.1/
  svg/          # Test source files (.svg) — what we render
  png/          # Reference PNGs from the W3C suite (optional, human reference only)
  overrides.json  # Per-test feature-tag and skip overrides
```

## Provenance

- Upstream: https://www.w3.org/Graphics/SVG/Test/20110816/
- License: W3C Software and Document License (https://www.w3.org/Consortium/Legal/2015/copyright-software-and-document)

The full test suite is *not* committed in this initial scaffold — only a small
in-house sample (`shapes-rect-basic-01.svg`) is present to exercise the
conformance harness. To vendor the full upstream suite:

1. Download the archive linked from the W3C page above.
2. Copy the contents of its `svg/` and `png/` directories here.
3. Commit, preserving the W3C copyright headers inside each file.

## How tags are derived

`SVGFeatureTag.fromW3CFilename` reads the leading chapter prefix from the
filename (e.g. `paths-data-01-t.svg` → `paths`). Override entries in
`overrides.json` can re-tag or skip a specific test:

```json
{
  "filters-blend-01-b": { "skip": "feFilter not implemented yet" },
  "interact-events-01-t": { "tag": "interact" }
}
```
