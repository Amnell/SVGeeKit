# Snapshot workflow

## Why approval snapshots

We do not pixel-diff against the W3C reference PNGs because they were rendered
by historical implementations whose antialiasing, font, and color management
differ from Core Graphics. Instead, the first time SVGeeKit renders a test, a
human reviews the output and approves it as the baseline. Future runs diff
against that approved baseline.

## Two-tier baseline system

Baselines live in two directories:

```
Tests/__Snapshots__/<test-id>/baseline.png        # COMMITTED — verified, gate-kept
Tests/__PartialSnapshots__/<test-id>/baseline.png # COMMITTED — auto-tracked, unverified
Tests/__SnapshotResults__/<test-id>/actual.png    # ephemeral (gitignored)
```

| Tier | Written by | Mismatches | Fails CI? | Promote via |
|---|---|---|---|---|
| **Real** (`__Snapshots__`) | `APPROVE_SNAPSHOTS=1` or Viewer Approve | overwrites on re-approve, otherwise fails | ✅ Yes | already verified |
| **Partial** (`__PartialSnapshots__`) | auto-written on first render | silently updates in place | ❌ No | Viewer Approve or `APPROVE_SNAPSHOTS=<id>` |

### Status codes in the conformance report

- `passed` — render matches a verified real baseline within tolerance.
- `partialBaseline` — render is captured and tracked, but not yet visually verified against the W3C reference. Not a failure. **`diffMaxChannel: 0` does not mean correct** — it only means actual matches the auto-captured partial baseline; compare against `<d:passCriteria>` and `W3C-SVG-1.1/png/<test-id>.png` before promoting.
- `failed` — render exceeds tolerance against the real baseline. Must be fixed or re-approved.
- `skipped` — test explicitly excluded in `overrides.json`.
- `parseError` / `renderError` — something threw during parsing or rasterisation.

## Commands

```sh
# Normal development — auto-updates partial baselines, strict on real baselines
swift test

# Re-approve a drifted real baseline (intentional rendering improvement)
APPROVE_SNAPSHOTS=1 swift test

# Promote one or more partial baselines to real after visual review in the Viewer
APPROVE_SNAPSHOTS=pservers-grad-02-b,masking-path-02-b swift test --filter ConformanceSuite

# Only run conformance
swift test --filter ConformanceSuite
```

## Typical workflow for a new SVG feature

1. Implement the feature (parser + renderer).
2. Run `swift test --filter ConformanceSuite`. The newly-rendering tests auto-write partial baselines and report `partialBaseline`.
3. Open the Viewer (`swift run Viewer`). Inspect each `partialBaseline` test:
   - Render looks correct vs. the W3C reference PNG → click **Approve** (promotes to `__Snapshots__`, deletes partial).
   - Render looks wrong → fix the code and repeat.
   - Optional programmatic pre-check: `diffAgainstW3C(testId:)` in `Tests/SVGRendererTests/PatternRenderTests.swift` diffs against `W3C-SVG-1.1/png/<test-id>.png` without touching baselines.
4. Commit both the code and the updated `__Snapshots__/` entries together. Optionally commit the `__PartialSnapshots__/` for tests not yet promoted.

## When a real baseline mismatches (CI red)

1. Find the failing test id, compare `Tests/__SnapshotResults__/<id>/actual.png` against `Tests/__Snapshots__/<id>/baseline.png`.
2. Decide:
   - **Regression** → fix the code. Do **not** re-approve.
   - **Improvement / intentional change** → visually verify in the Viewer, then:
     ```sh
     APPROVE_SNAPSHOTS=1 swift test --filter ConformanceSuite
     ```
     Commit the updated `baseline.png` together with the code change.

## Tolerance

Per-channel and per-pixel-fraction tolerances live in
`SVGConformanceRunner.Options.tolerance`. The default is forgiving enough for
Core Graphics anti-aliasing differences across macOS versions. Text-rendering
chapters will likely need looser tolerance — adjust per-tag once we get there.

## Never

- ❌ `APPROVE_SNAPSHOTS=1` in CI — it would silently overwrite ground truth.
- ❌ Editing `baseline.png` by hand.
- ❌ Re-approving without visual inspection in the Viewer.
- ❌ Using `APPROVE_SNAPSHOTS=1` intending to bulk-promote partials — it does **not** promote partial baselines; use explicit IDs or the Viewer instead.
