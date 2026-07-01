# SVGeeKit — agent orientation

SVGeeKit is a Swift package for iOS 17+ / macOS 14+ that **parses and renders static SVG**, anchored on the W3C SVG 1.1 Second Edition test suite. It is built to be extended incrementally — one SVG feature at a time, with snapshot-based regression protection at every step.

## Ground rules

1. **No animation, no interactivity, no DOM mutation.** The library is purely static today (`<animate*>`, `<script>`, hit-testing, pointer events are out of scope).
2. **Parser and renderer are strictly separated.**
   - `SVGCore` defines pure value-type model data — no I/O, no rendering, no `SwiftUI`.
   - `SVGParser` only writes model values; it never touches a renderer.
   - `SVGRenderer` defines a backend-neutral protocol; commands are CG-shaped so a CoreGraphics or Metal backend can drop in.
   - `SVGRendererSwiftUI` is one concrete backend; do **not** leak `SwiftUI` types back into `SVGCore` / `SVGRenderer`.
3. **Never weaken a passing snapshot.** If a real baseline mismatches, first determine whether your change is an intentional rendering improvement (re-approve with `APPROVE_SNAPSHOTS=1`) or a regression (fix the code).
4. **Add tests for every new element / attribute.** Each new SVG feature lands together with at least one W3C-style test file under `Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/`.
5. **Always read a W3C test's embedded metadata before implementing it.** Every W3C SVG file carries a `<d:SVGTestCase>` block with `<d:testDescription>` (what the test exercises) and `<d:passCriteria>` (the exact visual outcome that counts as a pass — e.g. "four green circles visible, no red"). Read these *before* touching code: they tell you what the correct render is, independent of any existing baseline. Never infer correctness from a `__PartialSnapshots__` baseline alone — those are auto-captured and unverified, so they can enshrine a bug.
6. **Update [docs/conformance/report.md](docs/conformance/report.md)** is auto-generated — don't hand-edit; re-run the test suite to regenerate `conformance-report.json`.
7. **Baseline promotion always requires human verification.** Promoting a partial baseline to `__Snapshots__/` (`APPROVE_SNAPSHOTS=<id>`) or re-approving a drifted real baseline (`APPROVE_SNAPSHOTS=1`) must only happen after a human has visually confirmed the render against the W3C test's `passCriteria`. Do not run approval commands or commit promoted `__Snapshots__/` on your own — wait for explicit user confirmation.

## Where to start (by task)

| Task | Read first |
| --- | --- |
| Add a new SVG element | [docs/adding-a-feature.md](docs/adding-a-feature.md) |
| Text / SVG fonts (phased rollout) | [docs/font-rollout-plan.md](docs/font-rollout-plan.md) |
| Understand module boundaries | [docs/architecture.md](docs/architecture.md) |
| Re-approve / debug a snapshot | [docs/snapshot-workflow.md](docs/snapshot-workflow.md) |
| Tag a test or skip a broken one | [docs/test-tagging.md](docs/test-tagging.md) |
| Match the codebase's Swift style | [docs/coding-conventions.md](docs/coding-conventions.md) |

## Common commands

```sh
swift build                                              # build everything
swift test                                               # run all tests
swift test --filter ConformanceSuite                     # conformance only
swift test --filter SVGParserTests                       # parser unit tests only

# Snapshot approval (human-verified only — see ground rule 7)
APPROVE_SNAPSHOTS=1 swift test                           # re-approve drifted real baselines
APPROVE_SNAPSHOTS=<id1>,<id2> swift test --filter ConformanceSuite  # promote specific partial baselines
```

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
  architecture.md, adding-a-feature.md, font-rollout-plan.md,
  snapshot-workflow.md, test-tagging.md, coding-conventions.md
  conformance/conformance-report.json           # generated by test runs
```
