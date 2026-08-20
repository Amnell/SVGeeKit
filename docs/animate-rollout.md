# SMIL animation rollout

SVGeeKit remains **static by default**. Optional declarative SMIL lives in the **`SVGAnimation`** product.

## Architecture

1. **`SVGParser`** captures `<animate>`, `<set>`, `<animateTransform>`, and `<animateMotion>` as metadata on parent elements — it does not run the timeline.
2. **`SVGAnimationEngine.sample(document:at:)`** applies animated attribute values at time `t` via **`SVGElementMutation`**, then the existing **`SVGRenderTree.lower`** path renders the sampled model.
3. **`SVGAnimationImageView`** (SwiftUI, iOS 17+) drives live playback with `TimelineView`; no `SVGScript` dependency. On iOS 16, sample with `SVGAnimationEngine` and render through `SVGImageView`.

## Scope

**In scope:** `animate-elem-*` (68 tests) and `animate-pservers-grad-*` (1, later).

**Permanently excluded** (DOM / script / interaction):

| Family | Count |
| --- | ---: |
| `animate-dom-*` | 2 |
| `animate-script-elem-*` | 1 |
| `animate-struct-dom-*` | 1 |
| `animate-interact-*` | 5 |

Event-based `begin` / `end` (`click`, `mouseover`, …) are not implemented — unresolved event specs leave the animation indefinite.

## Supported SMIL (v1)

| Element | Attributes (initial) |
| --- | --- |
| `<animate>` | `attributeName`, `from`, `to`, `values`, `dur`, `begin`, `fill`, `calcMode` (`linear`, `discrete`) |
| `<set>` | `attributeName`, `to`, `begin`, `dur`, `fill` |
| `<animateTransform>` | deferred — Phase 6 |
| `<animateMotion>` | deferred — Phase 7 |

## Testing

`ConformanceSuite` runs all **`animate-elem-*`** tests (68 cases). When a test has no
explicit `sampleAt` in `overrides.json`, the runner samples at
`SVGAnimationEngine.suggestedDuration` (end of the document timeline) before
rasterizing. Per-test `sampleAt` overrides remain available for pass-criteria times
that differ from the computed end.

Excluded animate families (`animate-dom-*`, `animate-script-elem-*`,
`animate-struct-dom-*`, `animate-interact-*`, `animate-pservers-grad-*`) stay
skipped via per-test entries in `overrides.json`.

```sh
swift test --filter SVGAnimationTests
swift test --filter ConformanceSuite
APPROVE_SNAPSHOTS=animate-elem-22-b swift test --filter ConformanceSuite
```

Promote baselines only after visual review against `<d:passCriteria>` and the W3C reference PNG.

## Key files

| File | Role |
| --- | --- |
| `Sources/SVGCore/SVGAnimation.swift` | `SVGTimedAnimation` value types |
| `Sources/SVGParser/SVGParser.swift` | Animation child capture |
| `Sources/SVGAnimation/SVGAnimationEngine.swift` | Timeline sampling |
| `Sources/SVGAnimation/SVGAnimationImageView.swift` | Live SwiftUI playback |
| `Tests/SVGAnimationTests/` | Parser + temporal render tests |

## Phases

See the full phased plan in the repository history. Summary:

1. Infrastructure — parser capture, engine stub
2. Basic `<animate>` — `animate-elem-22-b`
3. `<set>` — discrete attribute changes
4. Timing graph — syncbases, clock lists, repeat
5. `additive` / `accumulate` / `keyTimes`
6. `<animateTransform>`
7. `<animateMotion>`
8. Cross-element `xlink:href` targeting
9. Live Viewer scrubber
10. CSS class / image / text / gradient completions (non-script)
