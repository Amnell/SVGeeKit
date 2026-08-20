# SVGeeKit — agent orientation

SVGeeKit is a Swift package for iOS 16+ / macOS 14+ that **parses and renders static SVG**, anchored on the W3C SVG 1.1 Second Edition test suite. It is built to be extended incrementally — one SVG feature at a time, with snapshot-based regression protection at every step.

## Ground rules

1. **Static by default; scripting and animation are opt-in.** The core library parses and renders static SVG (`SVGKit`) on iOS 16+ / macOS 14+. Optional `SVGScript` adds JavaScriptCore-backed event handlers and DOM attribute mutation (iOS 17+). Optional `SVGAnimation` adds declarative SMIL (`<animate>`, `<set>`, …); `SVGAnimationEngine` is available on iOS 16+, while `SVGAnimationImageView` requires iOS 17+. Hit-testing beyond scripting and pointer events without scripts remain out of scope.
2. **Parser and renderer are strictly separated.**
   - `SVGCore` defines pure value-type model data — no I/O, no rendering, no `SwiftUI`.
   - `SVGParser` only writes model values; it never touches a renderer.
   - `SVGRenderer` defines a backend-neutral protocol; commands are CG-shaped so a CoreGraphics or Metal backend can drop in.
   - `SVGRendererSwiftUI` is one concrete backend; do **not** leak `SwiftUI` types back into `SVGCore` / `SVGRenderer`.
3. **Never weaken a passing snapshot.** If a real baseline mismatches, first determine whether your change is an intentional rendering improvement (re-approve with `APPROVE_SNAPSHOTS=1`) or a regression (fix the code).
4. **Add tests for every new element / attribute.** Each new SVG feature lands together with at least one W3C-style test file under `Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/`.
5. **Always read a W3C test's embedded metadata before implementing it.** Every W3C SVG file carries a `<d:SVGTestCase>` block with `<d:testDescription>` (what the test exercises) and `<d:passCriteria>` (the exact visual outcome that counts as a pass — e.g. "four green circles visible, no red"). Read these *before* touching code: they tell you what the correct render is, independent of any existing baseline. Never infer correctness from a `__PartialSnapshots__` baseline alone — those are auto-captured and unverified, so they can enshrine a bug.
6. **Coverage docs are generated.** [`docs/conformance/conformance-report.json`](docs/conformance/conformance-report.json) is rewritten by the test suite. The GitHub-browseable gallery ([`docs/conformance/README.md`](docs/conformance/README.md) and per-chapter pages) is generated from that JSON — don't hand-edit; run `swift run CoverageReport` after a full conformance run.
7. **Baseline promotion always requires human verification.** Promoting a partial baseline to `__Snapshots__/` (`APPROVE_SNAPSHOTS=<id>`) or re-approving a drifted real baseline (`APPROVE_SNAPSHOTS=1`) must only happen after a human has visually confirmed the render against the W3C test's `passCriteria`. Do not run approval commands or commit promoted `__Snapshots__/` on your own — wait for explicit user confirmation.

## Where to start (by task)

| Task | Read first |
| --- | --- |
| Production scope / v1 roadmap | [docs/production-readiness/README.md](docs/production-readiness/README.md) |
| Security model implementation | [docs/production-readiness/security-implementation.md](docs/production-readiness/security-implementation.md) |
| Add a new SVG element | [docs/adding-a-feature.md](docs/adding-a-feature.md) |
| CSS / class / `<style>` styling | [docs/styling-rollout.md](docs/styling-rollout.md), `Sources/SVGParser/CSSStylesheet.swift` |
| ECMAScript / event handlers | [docs/script-rollout.md](docs/script-rollout.md), `Sources/SVGScript/` |
| SMIL declarative animation | [docs/animate-rollout.md](docs/animate-rollout.md), `Sources/SVGAnimation/` |
| Text / SVG fonts (phased rollout) | [docs/font-rollout-plan.md](docs/font-rollout-plan.md) |
| Understand module boundaries | [docs/architecture.md](docs/architecture.md) |
| Re-approve / debug a snapshot | [docs/snapshot-workflow.md](docs/snapshot-workflow.md) |
| Tag a test or skip a broken one | [docs/test-tagging.md](docs/test-tagging.md) |
| Match the codebase's Swift style | [docs/coding-conventions.md](docs/coding-conventions.md) |

## Common commands

```sh
swift build                                              # build everything
swift test                                               # run all tests
swift test --filter ConformanceSuite                     # conformance only (all W3C tests)
swift test --filter SVGParserTests                       # parser unit tests only
swift test --filter 'appliesClassStylesFromStyleElement' # filter by parser unit-test name

# Snapshot approval (human-verified only — see ground rule 7)
APPROVE_SNAPSHOTS=1 swift test                           # re-approve drifted real baselines
APPROVE_SNAPSHOTS=<id1>,<id2> swift test --filter ConformanceSuite  # promote specific partial baselines

# Optional W3C reference pre-check (does not touch baselines)
swift test --filter stylingCss01bMatchesW3CReference

# GitHub-browseable coverage gallery (markdown + relative PNG links)
swift run CoverageReport

# iOS 16 smoke app (local package, IPHONEOS_DEPLOYMENT_TARGET = 16.0)
open Apps/iOS16Smoke/iOS16Smoke.xcodeproj
xcodebuild -project Apps/iOS16Smoke/iOS16Smoke.xcodeproj -scheme iOS16Smoke \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

**W3C reference diff helper:** `W3CReferenceDiff` in `Sources/SVGConformance/W3CReferenceDiff.swift`
renders a bundled test case and diffs against `W3C-SVG-1.1/png/<test-id>.png`. Useful before
promoting a partial baseline — a large diff against the W3C PNG is a red flag even when
`diffMaxChannel: 0` against `__PartialSnapshots__`.

Conformance cases are one parametrized `render(_:)` test — **filter by suite name** (`ConformanceSuite`), not by test id. To run or promote a single W3C test, use `APPROVE_SNAPSHOTS=<test-id>` with `--filter ConformanceSuite`.

## Troubleshooting

**Test runner segfault (signal 11).** Stale build artifacts can cause the SwiftPM test helper to crash, especially after large refactors or when many parametrized conformance cases run at once. Before debugging code, do a full clean:

```sh
rm -rf .build
swift package clean
# If you use Xcode for the Viewer app or open the package there:
rm -rf ~/Library/Developer/Xcode/DerivedData/*SVGeeKit*
swift test
```

If tests pass after a clean, the crash was environmental — not a logic bug in the renderer.

## Two-tier snapshot system

Conformance tests use two baseline directories:

- **`Tests/__Snapshots__/`** — verified, gate-kept. A mismatch fails CI. Written by `APPROVE_SNAPSHOTS=1` or the Viewer Approve button.
- **`Tests/__PartialSnapshots__/`** — auto-tracked. Written automatically on first render; silently updated when the render changes; never fails CI. Promotes to `__Snapshots__/` only via explicit per-ID approval after human visual verification.

This means every non-skipped, renderable test is tracked for regressions from the first run, while `passed` stays a trustworthy signal.

**`partialBaseline` with zero diff is not a pass.** A row with `diffMaxChannel: 0` only means the current render matches the auto-captured partial baseline — both can be wrong. Before promoting, compare against the test's `<d:passCriteria>` and the W3C reference PNG at `Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/png/<test-id>.png`.

See [docs/snapshot-workflow.md](docs/snapshot-workflow.md) for full details.

## Repository layout

```
Sources/
  SVGCore/              # value-type model (SVGDocument, SVGRect, SVGPaint, …)
  SVGParser/            # XMLParser-based reader → SVGCore
  SVGRenderer/          # backend-neutral protocol + render-tree lowering
  SVGRendererSwiftUI/   # SwiftUI Canvas backend + Core Graphics rasterizer
  SVGKit/               # umbrella re-export (public API)
  SVGConformance/       # test-support: suite index, snapshot diff, report
Tests/
  SVGCoreTests/, SVGParserTests/, SVGConformanceTests/
  __Snapshots__/            # COMMITTED — verified baselines
  __PartialSnapshots__/     # COMMITTED — auto-tracked, unverified baselines
docs/
  architecture.md, adding-a-feature.md, font-rollout-plan.md, styling-rollout.md,
  snapshot-workflow.md, test-tagging.md, coding-conventions.md
  conformance/README.md                         # generated coverage gallery index
  conformance/*.md                              # one chapter per feature tag (generated)
  conformance/conformance-report.json           # generated by test runs
Apps/
  Viewer/                   # macOS conformance viewer (SPM executable)
  CoverageReport/           # markdown gallery generator (`swift run CoverageReport`)
  iOS16Smoke/               # iOS 16 verification app (Xcode project)
```
