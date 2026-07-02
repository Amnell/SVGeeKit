# Script support rollout

SVGeeKit remains **static by default**. Optional scripting lives in the **`SVGScript`** product (JavaScriptCore on Apple platforms).

## Architecture

1. **`SVGParser`** captures `<script>` bodies, event-handler attributes, `contentScriptType`, and a full-document `elementIndex` — it does not execute JavaScript.
2. **`SVGScriptDocument`** owns a mutable `SVGDocument` plus a `JSContext` with a minimal DOM shim (`document.getElementById`, `element.setAttribute`, `evt.target`, `ownerDocument`).
3. After script mutations, the existing **`SVGRenderTree.lower`** path renders the updated model — no renderer-protocol changes required for basic attribute updates.
4. **`SVGScriptImageView`** (SwiftUI) forwards taps through **`SVGHitTester`** into `dispatchClick(at:)`.

## Supported DOM API (v1)

| API | Notes |
| --- | --- |
| `document.getElementById(id)` | Groups and `<text>` with `id` |
| `element.setAttribute('visibility', …)` | Groups and shapes/text |
| `element.setAttribute('fill', …)` | Basic named / `#rrggbb` colors |
| `element.ownerDocument` | Returns document wrapper |
| `evt.target` | Deepest hit-tested element |
| Inline `<script type="text/ecmascript">` | Evaluated on `dispatchLoad()` |
| `onclick`, `onload`, … attributes | Dispatched on click / load |

Deferred: `addEventListener`, DOM insert/remove, `SVGTransform` DOM, animation.

## MIME type gating

Scripts run only when `type` (or document `contentScriptType`, default `application/ecmascript`) is `text/ecmascript` or `application/ecmascript`. See W3C `script-specify-01-f` / `script-specify-02-f`.

## Security

`SVGScript` executes embedded JavaScript with **full JavaScriptCore privileges**. Treat scripted SVG like trusted code (same as loading arbitrary native libraries). There is no sandbox in v1.

## Testing interactive W3C cases

Static `ConformanceSuite` rasterizes once. Script tests such as **`script-handle-01-b`** need an operator step — see `SVGScriptTests.scriptHandle01bAfterClick`, which simulates a click and asserts DOM + raster output.

Promote post-interaction baselines only after visual review in the Viewer interactive preview or against `<d:passCriteria>`.

## Commands

```sh
swift test --filter SVGScriptTests
swift test --filter parsesScriptHandle01Metadata
APPROVE_SNAPSHOTS=script-handle-01-b swift test --filter ConformanceSuite
```
