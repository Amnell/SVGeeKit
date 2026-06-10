# Snapshot workflow

## Why approval snapshots

We do not pixel-diff against the W3C reference PNGs because they were rendered
by historical implementations whose antialiasing, font, and color management
differ from Core Graphics. Instead, the first time SVGeeKit renders a test, a
human reviews the output and approves it as the baseline. Future runs diff
against that approved baseline.

## File layout

```
Tests/__Snapshots__/<test-id>/baseline.png    # COMMITTED — ground truth
Tests/__SnapshotResults__/<test-id>/actual.png  # ephemeral (gitignored)
```

## Commands

```sh
swift test                                    # diff against baselines
APPROVE_SNAPSHOTS=1 swift test                # accept new / changed baselines
swift test --filter ConformanceSuite          # only run conformance
```

## When a baseline mismatches

1. Find the failing test id in the output, then look at
   `Tests/__SnapshotResults__/<id>/actual.png` next to
   `Tests/__Snapshots__/<id>/baseline.png`.
2. Decide:
   - **Regression** (rendering got worse for a feature that already worked) →
     fix the renderer / parser. Do **not** re-approve.
   - **Improvement / intentional change** (anti-aliasing tuned, missing feature
     now rendered, refactor with no semantic change) → re-approve with
     `APPROVE_SNAPSHOTS=1 swift test --filter ConformanceSuite` and commit the
     updated `baseline.png` together with the code change.
3. Use the Viewer app (Phase 2) to triage at scale — it loads
   `conformance-report.json` and shows source · render · baseline · reference
   · diff overlay per test.

## Tolerance

Per-channel and per-pixel-fraction tolerances live in
`SVGConformanceRunner.Options.tolerance`. The default is forgiving enough for
Core Graphics anti-aliasing differences across macOS versions. Text-rendering
chapters will likely need looser tolerance — adjust per-tag once we get there.

## Never

- ❌ `APPROVE_SNAPSHOTS=1` in CI — it would silently overwrite ground truth.
- ❌ Editing `baseline.png` by hand.
- ❌ Re-approving without visual inspection.
