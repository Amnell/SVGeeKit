@preconcurrency import CoreGraphics
import SVGCore

/// Backend-neutral primitive emitted by the render-tree walker.
/// Designed CG-shaped so future CoreGraphics / Metal backends are direct mappings.
public enum SVGRenderCommand: Equatable, Sendable {
    /// Save current graphics state (clip, transform, opacity layer).
    case pushState
    /// Restore previous graphics state.
    case popState

    /// Multiply the current transform by `transform`.
    case concatenate(SVGTransform)

    /// Begin a transparency layer with the given group opacity.
    case beginOpacityLayer(CGFloat)
    case endOpacityLayer

    /// Fill `path` with `paint` using the given fill-opacity and rule.
    case fillPath(CGPath, paint: SVGPaint, opacity: CGFloat, evenOdd: Bool)

    /// Stroke `path` with the given paint and stroke parameters.
    case strokePath(
        CGPath,
        paint: SVGPaint,
        opacity: CGFloat,
        width: CGFloat,
        lineCap: SVGLineCap,
        lineJoin: SVGLineJoin,
        miterLimit: CGFloat,
        dashArray: [CGFloat],
        dashPhase: CGFloat
    )

    /// Clip subsequent drawing to `path`. Must be bracketed by pushState/popState.
    case clipToPath(CGPath, evenOdd: Bool)

    /// Render `content` into an isolated transparency group, then composite
    /// the result onto the canvas at `opacity`. This implements SVG group
    /// opacity (§11.3): overlapping children do not show through each other.
    case groupLayer(opacity: CGFloat, content: [SVGRenderCommand])

    /// Composite `content` through a luminance mask built from `mask`.
    /// The mask's per-pixel luminance × alpha becomes the alpha applied to the
    /// content. `region`, when present, clips the mask to that rectangle so
    /// content outside it is fully masked out (SVG `maskUnits` region).
    case maskedContent(mask: [SVGRenderCommand], region: CGRect?, content: [SVGRenderCommand])
}

/// A renderer consumes a render-command stream and draws it into its backend.
/// The render tree is what the parser/lowering layer produces; renderers never
/// see `SVGDocument` directly.
public protocol SVGRendererBackend {
    /// Execute the supplied commands into the renderer's current context.
    func execute(_ commands: [SVGRenderCommand])
}

public enum SVGRenderTree {
    /// Lower a parsed document into a flat command stream.
    public static func lower(_ document: SVGDocument) -> [SVGRenderCommand] {
        var commands: [SVGRenderCommand] = []
        let ctx = Context(
            paintServers: document.paintServers,
            clipPaths: document.clipPaths,
            masks: document.masks,
            fonts: document.fonts,
            fontFaces: document.fontFaces
        )
        commands.append(.pushState)
        if let viewBox = document.viewBox, let size = document.intrinsicSize {
            let sx = size.width / viewBox.width
            let sy = size.height / viewBox.height
            var t = CGAffineTransform(scaleX: sx, y: sy)
            t = t.translatedBy(x: -viewBox.origin.x, y: -viewBox.origin.y)
            commands.append(.concatenate(SVGTransform(t)))
        }
        lower(group: document.root, ctx: ctx, into: &commands)
        commands.append(.popState)
        return commands
    }

    fileprivate struct Context {
        let paintServers: [String: SVGPaintServer]
        let clipPaths: [String: SVGClipPath]
        let masks: [String: SVGMask]
        let fonts: [String: SVGFontDefinition]
        let fontFaces: [SVGFontFace]
    }

    private static func lower(group: SVGGroup, ctx: Context, into commands: inout [SVGRenderCommand]) {
        var inner: [SVGRenderCommand] = []
        let hasClip = group.clipPathRef != nil
        let needsState = hasClip || group.transform.matrix != .identity
        if needsState { inner.append(.pushState) }
        if let clipRef = group.clipPathRef, let clipDef = ctx.clipPaths[clipRef] {
            inner.append(.clipToPath(lowerToClipPath(clipDef, bbox: nil, ctx: ctx), evenOdd: false))
        }
        if group.transform.matrix != .identity {
            inner.append(.concatenate(group.transform))
        }
        for child in group.children {
            lower(element: child, ctx: ctx, into: &inner)
        }
        if needsState { inner.append(.popState) }

        // Group opacity < 1 requires compositing children as a unit (SVG §11.3).
        // Wrap in groupLayer so the backend renders an isolated layer.
        let opaque = inner
        let withOpacity: [SVGRenderCommand] = group.opacity < 1
            ? [.groupLayer(opacity: group.opacity, content: opaque)]
            : opaque

        // An empty mask suppresses the group (applyMask returns nil); a present
        // mask wraps the lowered children in a `.maskedContent` command.
        guard let wrapped = applyMask(group.maskRef, bbox: .null, content: withOpacity, ctx: ctx) else { return }
        commands.append(contentsOf: wrapped)
    }

    /// Wrap `content` in a `.maskedContent` command when `ref` resolves to a
    /// non-empty mask. Returns `content` unchanged when there is no mask, and
    /// `nil` when the mask is empty (the caller must suppress the element per
    /// SVG 1.1 §14.4).
    private static func applyMask(
        _ ref: String?,
        bbox: CGRect,
        content: [SVGRenderCommand],
        ctx: Context
    ) -> [SVGRenderCommand]? {
        guard let ref, let mask = ctx.masks[ref] else { return content }
        if mask.children.isEmpty { return nil }
        var maskCommands: [SVGRenderCommand] = []
        for child in mask.children {
            lower(element: child, ctx: ctx, into: &maskCommands)
        }
        return [.maskedContent(mask: maskCommands, region: maskRegion(mask, bbox: bbox), content: content)]
    }

    /// Resolve the mask region rectangle in user space, or `nil` for no clip.
    private static func maskRegion(_ mask: SVGMask, bbox: CGRect) -> CGRect? {
        switch mask.maskUnits {
        case .userSpaceOnUse:
            guard let x = mask.x, let y = mask.y, let w = mask.width, let h = mask.height else {
                return nil
            }
            return CGRect(x: x, y: y, width: w, height: h)
        case .objectBoundingBox:
            guard !bbox.isNull, !bbox.isEmpty else { return nil }
            let x = mask.x ?? -0.1
            let y = mask.y ?? -0.1
            let w = mask.width ?? 1.2
            let h = mask.height ?? 1.2
            return CGRect(
                x: bbox.minX + x * bbox.width,
                y: bbox.minY + y * bbox.height,
                width: w * bbox.width,
                height: h * bbox.height
            )
        }
    }

    private static func lower(element: SVGElement, ctx: Context, into commands: inout [SVGRenderCommand]) {
        switch element {
        case .group(let g):
            lower(group: g, ctx: ctx, into: &commands)
        case .rect(let r):
            lower(rect: r, ctx: ctx, into: &commands)
        case .circle(let c):
            lower(circle: c, ctx: ctx, into: &commands)
        case .ellipse(let e):
            lower(ellipse: e, ctx: ctx, into: &commands)
        case .line(let l):
            lower(line: l, ctx: ctx, into: &commands)
        case .polyline(let p):
            lower(polyline: p, ctx: ctx, into: &commands)
        case .polygon(let p):
            lower(polygon: p, ctx: ctx, into: &commands)
        case .path(let p):
            lower(path: p, ctx: ctx, into: &commands)
        case .text(let t):
            lower(text: t, ctx: ctx, into: &commands)
        }
    }

    private static func lower(rect: SVGRect, ctx: Context, into commands: inout [SVGRenderCommand]) {
        let cgRect = CGRect(origin: rect.origin, size: rect.size)
        let path: CGPath = {
            if rect.cornerRadii == .zero {
                return CGPath(rect: cgRect, transform: nil)
            }
            return CGPath(
                roundedRect: cgRect,
                cornerWidth: rect.cornerRadii.width,
                cornerHeight: rect.cornerRadii.height,
                transform: nil
            )
        }()
        emitPaintedPath(path, paint: rect.paint, transform: rect.transform, ctx: ctx, into: &commands)
    }

    private static func lower(circle: SVGCircle, ctx: Context, into commands: inout [SVGRenderCommand]) {
        guard circle.radius > 0 else { return }
        let bounds = CGRect(
            x: circle.center.x - circle.radius,
            y: circle.center.y - circle.radius,
            width: circle.radius * 2,
            height: circle.radius * 2
        )
        let path = CGPath(ellipseIn: bounds, transform: nil)
        emitPaintedPath(path, paint: circle.paint, transform: circle.transform, ctx: ctx, into: &commands)
    }

    private static func lower(ellipse: SVGEllipse, ctx: Context, into commands: inout [SVGRenderCommand]) {
        guard ellipse.radii.width > 0, ellipse.radii.height > 0 else { return }
        let bounds = CGRect(
            x: ellipse.center.x - ellipse.radii.width,
            y: ellipse.center.y - ellipse.radii.height,
            width: ellipse.radii.width * 2,
            height: ellipse.radii.height * 2
        )
        let path = CGPath(ellipseIn: bounds, transform: nil)
        emitPaintedPath(path, paint: ellipse.paint, transform: ellipse.transform, ctx: ctx, into: &commands)
    }

    private static func lower(line: SVGLine, ctx: Context, into commands: inout [SVGRenderCommand]) {
        let mutable = CGMutablePath()
        mutable.move(to: line.start)
        mutable.addLine(to: line.end)
        // `<line>` has no fillable area; suppress fill regardless of cascade.
        var paint = line.paint
        paint.fill = .none
        emitPaintedPath(mutable, paint: paint, transform: line.transform, ctx: ctx, into: &commands)
    }

    private static func lower(polyline: SVGPolyline, ctx: Context, into commands: inout [SVGRenderCommand]) {
        guard let path = polylinePath(points: polyline.points, closed: false) else { return }
        emitPaintedPath(path, paint: polyline.paint, transform: polyline.transform, ctx: ctx, into: &commands)
    }

    private static func lower(polygon: SVGPolygon, ctx: Context, into commands: inout [SVGRenderCommand]) {
        guard let path = polylinePath(points: polygon.points, closed: true) else { return }
        emitPaintedPath(path, paint: polygon.paint, transform: polygon.transform, ctx: ctx, into: &commands)
    }

    private static func lower(path svgPath: SVGPath, ctx: Context, into commands: inout [SVGRenderCommand]) {
        let cg = CGMutablePath()
        for cmd in svgPath.commands {
            switch cmd {
            case .moveTo(let p):
                cg.move(to: p)
            case .lineTo(let p):
                cg.addLine(to: p)
            case .quadTo(let c, let end):
                cg.addQuadCurve(to: end, control: c)
            case .cubicTo(let c1, let c2, let end):
                cg.addCurve(to: end, control1: c1, control2: c2)
            case .close:
                cg.closeSubpath()
            }
        }
        guard !cg.isEmpty else { return }
        emitPaintedPath(cg, paint: svgPath.paint, transform: svgPath.transform, ctx: ctx, into: &commands)
    }

    private static func lower(text: SVGText, ctx: Context, into commands: inout [SVGRenderCommand]) {
        guard !text.string.isEmpty else { return }
        guard text.paint.visibility == .visible else { return }
        guard let path = TextLayout.glyphPath(
            string: text.string,
            font: text.font,
            origin: text.origin,
            fontFaces: ctx.fontFaces,
            fonts: ctx.fonts
        ) else { return }
        emitPaintedPath(path, paint: text.paint, transform: text.transform, ctx: ctx, into: &commands)
    }

    /// Build a `CGPath` from all shape children of a `<clipPath>` definition.
    /// When `clipPathUnits="objectBoundingBox"` and a `bbox` is supplied, the
    /// clip coordinates (in [0,1] space) are mapped to that bounding box.
    private static func lowerToClipPath(_ clipDef: SVGClipPath, bbox: CGRect?, ctx: Context) -> CGPath {
        // OBB clips: compose translate(bbox.origin)+scale(bbox.size) on each path.
        let obbTransform: CGAffineTransform? = (clipDef.units == .objectBoundingBox)
            ? bbox.map { b in
                CGAffineTransform(translationX: b.minX, y: b.minY)
                    .scaledBy(x: b.width, y: b.height)
              }
            : nil
        let combined = CGMutablePath()
        for element in clipDef.children {
            switch element {
            case .rect(let r):
                let cgRect = CGRect(origin: r.origin, size: r.size)
                let p: CGPath = r.cornerRadii == .zero
                    ? CGPath(rect: cgRect, transform: nil)
                    : CGPath(roundedRect: cgRect, cornerWidth: r.cornerRadii.width,
                             cornerHeight: r.cornerRadii.height, transform: nil)
                var tx = r.transform.matrix
                if let obb = obbTransform { tx = tx.isIdentity ? obb : tx.concatenating(obb) }
                combined.addPath(p, transform: tx)
            case .circle(let c):
                guard c.radius > 0 else { break }
                let bounds = CGRect(
                    x: c.center.x - c.radius, y: c.center.y - c.radius,
                    width: c.radius * 2, height: c.radius * 2
                )
                let p = CGPath(ellipseIn: bounds, transform: nil)
                var tx = c.transform.matrix
                if let obb = obbTransform { tx = tx.isIdentity ? obb : tx.concatenating(obb) }
                combined.addPath(p, transform: tx)
            case .ellipse(let e):
                guard e.radii.width > 0, e.radii.height > 0 else { break }
                let bounds = CGRect(
                    x: e.center.x - e.radii.width, y: e.center.y - e.radii.height,
                    width: e.radii.width * 2, height: e.radii.height * 2
                )
                let p = CGPath(ellipseIn: bounds, transform: nil)
                var tx = e.transform.matrix
                if let obb = obbTransform { tx = tx.isIdentity ? obb : tx.concatenating(obb) }
                combined.addPath(p, transform: tx)
            case .path(let sp):
                let cg = CGMutablePath()
                for cmd in sp.commands {
                    switch cmd {
                    case .moveTo(let pt):    cg.move(to: pt)
                    case .lineTo(let pt):    cg.addLine(to: pt)
                    case .quadTo(let c, let end): cg.addQuadCurve(to: end, control: c)
                    case .cubicTo(let c1, let c2, let end): cg.addCurve(to: end, control1: c1, control2: c2)
                    case .close:             cg.closeSubpath()
                    }
                }
                var tx = sp.transform.matrix
                if let obb = obbTransform { tx = tx.isIdentity ? obb : tx.concatenating(obb) }
                combined.addPath(cg, transform: tx)
            case .polyline(let pl):
                if let p = polylinePath(points: pl.points, closed: false) {
                    var tx = pl.transform.matrix
                    if let obb = obbTransform { tx = tx.isIdentity ? obb : tx.concatenating(obb) }
                    combined.addPath(p, transform: tx)
                }
            case .polygon(let pg):
                if let p = polylinePath(points: pg.points, closed: true) {
                    var tx = pg.transform.matrix
                    if let obb = obbTransform { tx = tx.isIdentity ? obb : tx.concatenating(obb) }
                    combined.addPath(p, transform: tx)
                }
            default:
                break
            }
        }
        return combined
    }

    private static func polylinePath(points: [CGPoint], closed: Bool) -> CGPath? {
        guard let first = points.first else { return nil }
        let path = CGMutablePath()
        path.move(to: first)
        for p in points.dropFirst() {
            path.addLine(to: p)
        }
        if closed { path.closeSubpath() }
        return path
    }

    private static func emitPaintedPath(
        _ path: CGPath,
        paint: SVGPaintProperties,
        transform: SVGTransform,
        ctx: Context,
        into commands: inout [SVGRenderCommand]
    ) {
        guard paint.visibility == .visible else { return }
        let bbox = path.boundingBoxOfPath

        var painted: [SVGRenderCommand] = []
        let hasClip = paint.clipPathRef != nil
        let needsState = hasClip || transform.matrix != .identity || paint.opacity < 1
        if needsState { painted.append(.pushState) }
        // SVG §14.3: clip-path is evaluated in the element's local coordinate
        // system (after the element's own transform). Apply transform first so
        // the clip path coordinates are in local space, not parent space.
        if transform.matrix != .identity {
            painted.append(.concatenate(transform))
        }
        if let clipRef = paint.clipPathRef, let clipDef = ctx.clipPaths[clipRef] {
            painted.append(.clipToPath(lowerToClipPath(clipDef, bbox: bbox, ctx: ctx), evenOdd: false))
        }
        if paint.opacity < 1 {
            painted.append(.beginOpacityLayer(paint.opacity))
        }

        let resolvedFill = resolvePaint(paint.fill, bbox: bbox, ctx: ctx)
        let resolvedStroke = resolvePaint(paint.stroke, bbox: bbox, ctx: ctx)

        if case .none = resolvedFill {} else {
            painted.append(.fillPath(
                path,
                paint: resolvedFill,
                opacity: paint.fillOpacity,
                evenOdd: paint.fillRule == .evenodd
            ))
        }
        if case .none = resolvedStroke {} else {
            painted.append(.strokePath(
                path,
                paint: resolvedStroke,
                opacity: paint.strokeOpacity,
                width: paint.strokeWidth,
                lineCap: paint.lineCap,
                lineJoin: paint.lineJoin,
                miterLimit: paint.miterLimit,
                dashArray: paint.strokeDashArray,
                dashPhase: paint.strokeDashOffset
            ))
            var stampPaint = paint
            stampPaint.stroke = resolvedStroke
            emitZeroLengthCapStamps(path: path, paint: stampPaint, into: &painted)
        }

        if paint.opacity < 1 { painted.append(.endOpacityLayer) }
        if needsState { painted.append(.popState) }

        // An empty mask suppresses the element (applyMask returns nil) per
        // SVG 1.1 §14.4; a present mask wraps the painted commands.
        guard let wrapped = applyMask(paint.maskRef, bbox: bbox, content: painted, ctx: ctx) else { return }
        commands.append(contentsOf: wrapped)
    }

    /// Convert `.paintServer` references into concrete paint cases with the
    /// gradient endpoints baked into user space against `bbox`. Returns the
    /// input unchanged for colors and `.none`; returns `.none` for dangling
    /// or stop-less references.
    private static func resolvePaint(_ paint: SVGPaint, bbox: CGRect, ctx: Context) -> SVGPaint {
        guard case .paintServer(let id) = paint else { return paint }
        guard let server = ctx.paintServers[id] else { return .none }
        switch server {
        case .linearGradient(let g):
            guard !g.stops.isEmpty else { return .none }
            var concrete = g
            if g.units == .objectBoundingBox {
                concrete.x1 = bbox.minX + g.x1 * bbox.width
                concrete.y1 = bbox.minY + g.y1 * bbox.height
                concrete.x2 = bbox.minX + g.x2 * bbox.width
                concrete.y2 = bbox.minY + g.y2 * bbox.height
                concrete.units = .userSpaceOnUse
            }
            return .linearGradient(concrete)
        case .radialGradient(let g):
            guard !g.stops.isEmpty else { return .none }
            var concrete = g
            if g.units == .objectBoundingBox {
                // SVG 1.1 §13.4.2: for objectBoundingBox, the gradient's own
                // coordinate system is [0,1]×[0,1] mapped to the bbox via
                // translate(bbox.origin) scale(bbox.size). Folding that into
                // concrete.transform lets the backend scale the context
                // non-uniformly, which naturally produces an ellipse on
                // non-square bboxes (correct per spec). Converting cx/cy/r
                // individually with avgDim would incorrectly force a circle.
                let obbToUser = CGAffineTransform(translationX: bbox.minX, y: bbox.minY)
                    .scaledBy(x: bbox.width, y: bbox.height)
                let gt = g.transform.matrix
                concrete.transform = SVGTransform(gt.isIdentity ? obbToUser : obbToUser.concatenating(gt))
                concrete.units = .userSpaceOnUse
            }
            return .radialGradient(concrete)
        }
    }

    /// SVG 1.1 §11.4: a zero-length subpath must render as a stamp of the
    /// stroke-linecap shape (circle for `round`, square for `square`).
    /// CoreGraphics renders the round case correctly but drops the square
    /// case, so we synthesize a fill rect at each zero-length subpath origin
    /// when the cap is `square`.
    private static func emitZeroLengthCapStamps(
        path: CGPath,
        paint: SVGPaintProperties,
        into commands: inout [SVGRenderCommand]
    ) {
        guard paint.lineCap == .square, paint.strokeWidth > 0 else { return }
        let origins = zeroLengthSubpathOrigins(in: path)
        guard !origins.isEmpty else { return }
        let half = paint.strokeWidth / 2
        for p in origins {
            let rect = CGRect(
                x: p.x - half, y: p.y - half,
                width: paint.strokeWidth, height: paint.strokeWidth
            )
            commands.append(.fillPath(
                CGPath(rect: rect, transform: nil),
                paint: paint.stroke,
                opacity: paint.strokeOpacity,
                evenOdd: false
            ))
        }
    }

    /// Walks subpaths and returns the origin of each one whose drawing
    /// elements never leave the start point.
    private static func zeroLengthSubpathOrigins(in path: CGPath) -> [CGPoint] {
        var origins: [CGPoint] = []
        var subpathStart: CGPoint? = nil
        var subpathHasMovement = false
        var currentPoint: CGPoint? = nil

        func closeOutSubpath() {
            if let start = subpathStart, !subpathHasMovement {
                origins.append(start)
            }
            subpathStart = nil
            subpathHasMovement = false
        }

        path.applyWithBlock { ptr in
            let element = ptr.pointee
            switch element.type {
            case .moveToPoint:
                closeOutSubpath()
                let p = element.points[0]
                subpathStart = p
                currentPoint = p
            case .addLineToPoint:
                let p = element.points[0]
                if let cur = currentPoint, !pointsApproximatelyEqual(cur, p) {
                    subpathHasMovement = true
                }
                currentPoint = p
            case .addQuadCurveToPoint:
                let end = element.points[1]
                if let cur = currentPoint, !pointsApproximatelyEqual(cur, end) {
                    subpathHasMovement = true
                }
                currentPoint = end
            case .addCurveToPoint:
                let end = element.points[2]
                if let cur = currentPoint, !pointsApproximatelyEqual(cur, end) {
                    subpathHasMovement = true
                }
                currentPoint = end
            case .closeSubpath:
                if let cur = currentPoint, let start = subpathStart,
                   !pointsApproximatelyEqual(cur, start) {
                    subpathHasMovement = true
                }
                currentPoint = subpathStart
            @unknown default:
                break
            }
        }
        closeOutSubpath()
        return origins
    }

    private static func pointsApproximatelyEqual(_ a: CGPoint, _ b: CGPoint) -> Bool {
        let eps: CGFloat = 1e-9
        return abs(a.x - b.x) < eps && abs(a.y - b.y) < eps
    }
}
