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
        miterLimit: CGFloat
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
        commands.append(.pushState)
        if let viewBox = document.viewBox, let size = document.intrinsicSize {
            let sx = size.width / viewBox.width
            let sy = size.height / viewBox.height
            var t = CGAffineTransform(scaleX: sx, y: sy)
            t = t.translatedBy(x: -viewBox.origin.x, y: -viewBox.origin.y)
            commands.append(.concatenate(SVGTransform(t)))
        }
        lower(group: document.root, into: &commands)
        commands.append(.popState)
        return commands
    }

    private static func lower(group: SVGGroup, into commands: inout [SVGRenderCommand]) {
        commands.append(.pushState)
        if group.transform.matrix != .identity {
            commands.append(.concatenate(group.transform))
        }
        for child in group.children {
            lower(element: child, into: &commands)
        }
        commands.append(.popState)
    }

    private static func lower(element: SVGElement, into commands: inout [SVGRenderCommand]) {
        switch element {
        case .group(let g):
            lower(group: g, into: &commands)
        case .rect(let r):
            lower(rect: r, into: &commands)
        case .circle(let c):
            lower(circle: c, into: &commands)
        case .ellipse(let e):
            lower(ellipse: e, into: &commands)
        case .line(let l):
            lower(line: l, into: &commands)
        case .polyline(let p):
            lower(polyline: p, into: &commands)
        case .polygon(let p):
            lower(polygon: p, into: &commands)
        case .text(let t):
            lower(text: t, into: &commands)
        }
    }

    private static func lower(rect: SVGRect, into commands: inout [SVGRenderCommand]) {
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
        emitPaintedPath(path, paint: rect.paint, transform: rect.transform, into: &commands)
    }

    private static func lower(circle: SVGCircle, into commands: inout [SVGRenderCommand]) {
        guard circle.radius > 0 else { return }
        let bounds = CGRect(
            x: circle.center.x - circle.radius,
            y: circle.center.y - circle.radius,
            width: circle.radius * 2,
            height: circle.radius * 2
        )
        let path = CGPath(ellipseIn: bounds, transform: nil)
        emitPaintedPath(path, paint: circle.paint, transform: circle.transform, into: &commands)
    }

    private static func lower(ellipse: SVGEllipse, into commands: inout [SVGRenderCommand]) {
        guard ellipse.radii.width > 0, ellipse.radii.height > 0 else { return }
        let bounds = CGRect(
            x: ellipse.center.x - ellipse.radii.width,
            y: ellipse.center.y - ellipse.radii.height,
            width: ellipse.radii.width * 2,
            height: ellipse.radii.height * 2
        )
        let path = CGPath(ellipseIn: bounds, transform: nil)
        emitPaintedPath(path, paint: ellipse.paint, transform: ellipse.transform, into: &commands)
    }

    private static func lower(line: SVGLine, into commands: inout [SVGRenderCommand]) {
        let mutable = CGMutablePath()
        mutable.move(to: line.start)
        mutable.addLine(to: line.end)
        // `<line>` has no fillable area; suppress fill regardless of cascade.
        var paint = line.paint
        paint.fill = .none
        emitPaintedPath(mutable, paint: paint, transform: line.transform, into: &commands)
    }

    private static func lower(polyline: SVGPolyline, into commands: inout [SVGRenderCommand]) {
        guard let path = polylinePath(points: polyline.points, closed: false) else { return }
        emitPaintedPath(path, paint: polyline.paint, transform: polyline.transform, into: &commands)
    }

    private static func lower(polygon: SVGPolygon, into commands: inout [SVGRenderCommand]) {
        guard let path = polylinePath(points: polygon.points, closed: true) else { return }
        emitPaintedPath(path, paint: polygon.paint, transform: polygon.transform, into: &commands)
    }

    private static func lower(text: SVGText, into commands: inout [SVGRenderCommand]) {
        guard !text.string.isEmpty else { return }

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
        into commands: inout [SVGRenderCommand]
    ) {
        let needsState = transform.matrix != .identity || paint.opacity < 1
        if needsState { commands.append(.pushState) }
        if transform.matrix != .identity {
            commands.append(.concatenate(transform))
        }
        if paint.opacity < 1 {
            commands.append(.beginOpacityLayer(paint.opacity))
        }

        if case .none = paint.fill {} else {
            commands.append(.fillPath(
                path,
                paint: paint.fill,
                opacity: paint.fillOpacity,
                evenOdd: false
            ))
        }
        if case .none = paint.stroke {} else {
            commands.append(.strokePath(
                path,
                paint: paint.stroke,
                opacity: paint.strokeOpacity,
                width: paint.strokeWidth,
                lineCap: paint.lineCap,
                lineJoin: paint.lineJoin,
                miterLimit: paint.miterLimit
            ))
        }

        if paint.opacity < 1 { commands.append(.endOpacityLayer) }
        if needsState { commands.append(.popState) }
    }
}
