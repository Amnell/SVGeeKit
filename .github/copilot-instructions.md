See [AGENTS.md](../AGENTS.md) for full orientation. Short version for Copilot:

- Static SVG only. No animation, scripting, DOM mutation, interactivity.
- Layers: `SVGCore` (model) → `SVGParser` → `SVGRenderer` (protocol) → `SVGRendererSwiftUI`. Never leak `SwiftUI` types into `SVGCore` or `SVGRenderer`.
- Add tests for every new element. Snapshot regressions must be either fixed in code or explicitly re-approved with `APPROVE_SNAPSHOTS=1`.
- Recipe for adding a feature lives in [docs/adding-a-feature.md](../docs/adding-a-feature.md).
- Codebase conventions in [docs/coding-conventions.md](../docs/coding-conventions.md).
