# Production readiness plan

SVGeeKit v1 targets **self-contained static SVG 1.1** for iOS 17+ / macOS 14+: shapes,
paths, gradients, patterns, transforms, CSS styling, clipping, masking, text with system
fonts, and fragment-based `<use>` — with **no scripting, animation, external resources, or
network I/O** in the production API (`.production` / `.restricted` policy).

External file references — including `<use xlink:href="other.svg#id">`, `<image href="…">`,
and linked CSS — resolve only under explicit `.localFiles(at:)` (conformance corpus, Viewer,
benchmarks). Production parse rejects them with warnings.

This folder is the living plan for getting there. Update checkboxes and status tables as
work lands. Re-run `swift test` to refresh conformance numbers in
[conformance-report.json](../conformance/conformance-report.json).

## Documents

| Document | Purpose |
| --- | --- |
| [static-profile.md](static-profile.md) | Supported / unsupported SVG subset (the public contract) |
| [security-model.md](security-model.md) | External-resource policy, limits, parse modes |
| [security-implementation.md](security-implementation.md) | **Step-by-step Phase 0 build plan** (start here for coding) |
| [roadmap.md](roadmap.md) | Phased implementation checklist with conformance targets |
| [filters-plan.md](filters-plan.md) | Optional post-v1 filter subset (blur, shadow, color matrix) |
| [shipping-checklist.md](shipping-checklist.md) | API surface, docs, and release gates |

### Related rollout docs (feature detail)

These pre-date the production plan and contain implementation recipes. The roadmap
references them; do not duplicate their step-by-step content here.

| Area | Doc |
| --- | --- |
| CSS / `<style>` / `class` | [styling-rollout.md](../styling-rollout.md) |
| Text & fonts | [font-rollout-plan.md](../font-rollout-plan.md) |
| Feature recipe | [adding-a-feature.md](../adding-a-feature.md) |
| Snapshots | [snapshot-workflow.md](../snapshot-workflow.md) |
| Test overrides | [test-tagging.md](../test-tagging.md) |

### Explicitly out of production scope

| Area | Doc | Notes |
| --- | --- | --- |
| ECMAScript / events | [script-rollout.md](../script-rollout.md) | Internal / conformance only |
| SMIL animation | [animate-rollout.md](../animate-rollout.md) | Internal / conformance only |

## Current snapshot (baseline for this plan)

*Last measured: 2026-07-20 (post `color-prof-01-f` promote). Re-run tests to refresh.*

### Conformance suite (535 W3C tests)

| Status | Count | Meaning |
| --- | ---: | --- |
| `passed` | 221 | Verified baseline in `Tests/__Snapshots__/` |
| `partialBaseline` | 81 | Renders; auto-tracked, needs human verification |
| `skipped` | 233 | Feature family or test explicitly out of scope |

### By feature tag (in-profile chapters)

| Tag | Total | Passed | Partial | Skipped | Profile tier |
| --- | ---: | ---: | ---: | ---: | --- |
| `shapes` | 30 | 30 | 0 | 0 | Tier 1 ✓ |
| `paths` | 21 | 19 | 0 | 2 | Tier 1 ✓ |
| `coords` | 32 | 28 | 0 | 4 | Tier 1 ✓ |
| `painting` | 31 | 22 | 0 | 9 | Tier 1 |
| `pservers` | 33 | 33 | 0 | 0 | Tier 1 ✓ |
| `styling` | 18 | 15 | 0 | 3 | Tier 1 ✓ |
| `struct` | 72 | 30 | 16 | 26 | Tier 1 |
| `render` | 8 | 8 | 0 | 0 | Tier 1 ✓ |
| `color` | 6 | 6 | 0 | 0 | Tier 1 ✓ |
| `masking` | 19 | 15 | 0 | 4 | Tier 1 → Tier 2 |
| `text` | 64 | 4 | 0 | 60 | Tier 2 |
| `fonts` | 17 | 0 | 0 | 17 | Tier 2 (inline only) |
| `filters` | 43 | 0 | 0 | 43 | Tier 3 (optional v1.1) |
| `animate` | 78 | 8 | 60 | 10 | Out of scope |
| `script` | 6 | 1 | 0 | 5 | Out of scope |
| `interact` | 24 | 0 | 0 | 24 | Out of scope |
| `linking` | 12 | 0 | 0 | 12 | Out of scope |
| `extend` | 1 | 0 | 0 | 1 | Out of scope |

### Phase status

| Phase | Focus | Status |
| --- | --- | --- |
| 0 | [Security model](security-model.md) — lock external refs | **Complete** (Steps 0–9) |
| 1 | [Roadmap §1](roadmap.md#phase-1--core-static-rendering) — core geometry & paint | Core exit met; `struct` 1e still open |
| 2 | [Roadmap §2](roadmap.md#phase-2--masking--clipping) — `clipPath` / `mask` | Nearly done (15/15 non-skipped; 4 remaining skips) |
| 3 | [Roadmap §3](roadmap.md#phase-3--text) — system-font text | Not started |
| 4 | [Roadmap §4](roadmap.md#phase-4--structure--reuse) — `symbol`, `marker` | Not started |
| 5 | [Roadmap §5](roadmap.md#phase-5--baseline-verification-sweep) — promote verified partials | Not started |
| 6 | [Filters plan](filters-plan.md) — optional blur/shadow subset | Deferred |
| Ship | [Shipping checklist](shipping-checklist.md) | Not started |

### Recent milestones

- **2026-07-20:** Promoted `color-prof-01-f` — ICC `<color-profile>` on raster `<image>`
  (`color` chapter **6/6** verified; Phase 1 core ≥90% exit met).
- **2026-07-20:** Masking sweep — promoted `masking-path-04-b` … `08-b`, `10-b`, `11-b`,
  `13-f`, `14-f` (plus earlier `01-b`…`03-b`, `05-f`, `06-b`, `07-b`). Chapter at
  **15 passed / 0 partial / 4 skipped** (goal 15+ met among runnable tests).
- **2026-07-20:** Promoted `struct-image-12-b`, `struct-image-19-f` — image sizing /
  aspect (`struct` 30 passed / 16 partial).
- **2026-07-20:** Promoted `struct-use-04-b` / `01-t` / `05-b` — external `<use>` under
  `.localFiles`, linked CSS, computed values across document boundaries.
## How to use this plan

1. Pick the next open phase in [roadmap.md](roadmap.md).
2. Read the linked rollout doc and [adding-a-feature.md](../adding-a-feature.md).
3. Implement one W3C test (or unit test) at a time.
4. Verify against `<d:passCriteria>` and the W3C reference PNG — not partial baselines alone.
5. Update this README's status tables when a phase milestone lands.
6. When v1 ships, publish [static-profile.md](static-profile.md) as the integrator contract.

## Definition of done (v1)

- [ ] [Static profile](static-profile.md) implemented and documented
- [x] [Security model](security-model.md) enforced in parser (no silent external fetch)
- [ ] In-profile W3C chapters at target pass rates in [roadmap.md](roadmap.md)
- [ ] [Shipping checklist](shipping-checklist.md) complete
- [ ] `SVGScript` / `SVGAnimation` remain optional modules, not required for `SVGKit`
