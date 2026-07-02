# Vendored W3C SVG 1.1 Second Edition test resources

This directory mirrors the layout of the official W3C SVG 1.1 Second Edition
Test Suite (16 August 2011):

```
W3C-SVG-1.1/
  svg/            # Test source files (.svg) — what we render
  png/            # Reference PNGs from the W3C suite — shown side-by-side in the Viewer
  images/         # Raster assets referenced by some tests via <image>
  resources/      # Shared SVG/CSS/font assets referenced by some tests
  overrides.json  # Tag/skip configuration (see below)
```

## Provenance

- Upstream: <https://www.w3.org/Graphics/SVG/Test/20110816/>
- Archive: <https://www.w3.org/Graphics/SVG/Test/20110816/archives/W3C_SVG_11_TestSuite.tar.gz>
- Vendored snapshot: full `svg/`, `png/`, `images/`, and `resources/` directories
  from the upstream archive (W3C-published 2011-08-09). The `harness/` and
  `svgweb/` directories from the archive are intentionally omitted — they are an
  HTML test runner that we don't need.
- License: W3C Software and Document License
  (<https://www.w3.org/Consortium/Legal/2015/copyright-software-and-document>) —
  redistribution permitted, copyright headers inside each file are preserved.

The `svg/` directory also contains a small set of in-house fixtures
(`shapes-rect-basic-01.svg`, `shapes-circle-01.svg`, …). Their IDs are chosen
not to collide with the W3C suffix convention (`-01-b`, `-01-t`, `-01-f`), so
they coexist cleanly with the vendored files and provide a stable green
baseline while we extend SVG coverage.

## Tag derivation and skip configuration

`SVGFeatureTag.fromW3CFilename` reads the leading chapter prefix from each
filename (e.g. `paths-data-01-t.svg` → `paths`).

`overrides.json` is loaded in one of two shapes:

```json
{
  "skipReason": "feature family not yet supported",
  "skipTags": ["filters", "text", "fonts", "script", "interact", "masking", "linking", "extend"],
  "tests": {
    "filters-blend-01-b": { "skip": "explicit per-test note" },
    "interact-events-01-t": { "tag": "interact" }
  }
}
```

- `skipTags` skips every test whose derived feature tag is in the list.
- `skipReason` is the default reason shown when a test is skipped via a tag.
- `tests` holds per-ID overrides; an entry with `skip` always wins over tag
  rules. An entry with `tag` re-tags a test that the filename heuristic would
  otherwise mis-classify.

A bare `[String: SVGTestOverride]` map is still accepted for backwards
compatibility with the original minimal scaffold.
