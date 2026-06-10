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

    /// Draw text. The renderer is responsible for font lookup, metrics, and
    /// baseline placement at `origin` honoring `font.anchor` for horizontal
    /// alignment. Y is the alphabetic baseline (SVG semantics).
    case drawText(
        string: String,
        origin: CGPoint,
        font: SVGFont,
        fill: SVGPaint,
        fillOpacity: CGFloat,
        stroke: SVGPaint,
        strokeOpacity: CGFloat,
        strokeWidth: CGFloat
    )
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
        let ctx = Context(paintServers: document.paintServers)
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
    }

    private static func lower(group: SVGGroup, ctx: Context, into commands: inout [SVGRenderCommand]) {
        commands.append(.pushState)
        if group.transform.matrix != .identity {
            commands.append(.concatenate(group.transform))
        }
        for child in group.children {
            lower(element: child, ctx: ctx, into: &commands)
        }
        commands.append(.popState)
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
            lower(text: t, into: &commands)
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

    private static func lower(text: SVGText, into commands: inout [SVGRenderCommand]) {
        guard !text.string.isEmpty else { return }
        guard text.paint.visibility == .visible else { return }

        let needsState = text.transform.matrix != .identity || text.paint.opacity < 1
        if needsState { commands.append(.pushState) }
        if text.transform.matrix != .identity {
            commands.append(.concatenate(text.transform))
        }
        if text.paint.opacity < 1 {
            commands.append(.beginOpacityLayer(text.paint.opacity))
        }

        // SVG default for <text> is fill=black, stroke=none. Element paint
        // already carries that cascade, so we just pass it through.
        commands.append(.drawText(
            string: text.string,
            origin: text.origin,
            font: text.font,
            fill: text.paint.fill,
            fillOpacity: text.paint.fillOpacity,
            stroke: text.paint.stroke,
            strokeOpacity: text.paint.strokeOpacity,
            strokeWidth: text.paint.strokeWidth
        ))

        if text.paint.opacity < 1 { commands.append(.endOpacityLayer) }
        if needsState { commands.append(.popState) }
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
        let needsState = transform.matrix != .identity || paint.opacity < 1
        if needsState { commands.append(.pushState) }
        if transform.matrix != .identity {
            commands.append(.concatenate(transform))
        }
        if paint.opacity < 1 {
            commands.append(.beginOpacityLayer(paint.opacity))
        }

        let bbox = path.boundingBoxOfPath
        let resolvedFill = resolvePaint(paint.fill, bbox: bbox, ctx: ctx)
        let resolvedStroke = resolvePaint(paint.stroke, bbox: bbox, ctx: ctx)

        if case .none = resolvedFill {} else {
            commands.append(.fillPath(
                path,
                paint: resolvedFill,
                opacity: paint.fillOpacity,
                evenOdd: paint.fillRule == .evenodd
            ))
        }
        if case .none = resolvedStroke {} else {
            commands.append(.strokePath(
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
            emitZeroLengthCapStamps(path: path, paint: stampPaint, into: &commands)
        }

        if paint.opacity < 1 { commands.append(.endOpacityLayer) }
        if needsState { commands.append(.popState) }
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
