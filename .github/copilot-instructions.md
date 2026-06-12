See [AGENTS.md](../AGENTS.md) for full orientation. Short version for Copilot:

- Static SVG only. No animation, scripting, DOM mutation, interactivity.
- Layers: `SVGCore` (model) → `SVGParser` → `SVGRenderer` (protocol) → `SVGRendererSwiftUI`. Never leak `SwiftUI` types into `SVGCore` or `SVGRenderer`.
- Two-tier snapshots: `__Snapshots__/` = verified/gate-kept, `__PartialSnapshots__/` = auto-tracked/never-failing. See [docs/snapshot-workflow.md](../docs/snapshot-workflow.md).
  - `APPROVE_SNAPSHOTS=1` re-approves drifted **real** baselines only — does **not** bulk-promote partials.
  - `APPROVE_SNAPSHOTS=<id1>,<id2>` promotes those specific partial baselines to real after visual review.
  - Viewer Approve button promotes the selected test surgically.
- Add tests for every new element. Real-baseline regressions must be fixed in code or explicitly re-approved.
- Recipe for adding a feature lives in [docs/adding-a-feature.md](../docs/adding-a-feature.md).
- Codebase conventions in [docs/coding-conventions.md](../docs/coding-conventions.md).
