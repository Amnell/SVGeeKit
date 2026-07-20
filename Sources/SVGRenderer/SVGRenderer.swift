@preconcurrency import CoreGraphics
import Foundation
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

    /// Fill `path` with a tiled pattern. `tileCommands` draw one tile in
    /// tile-local space; `pattern` supplies the tiling grid geometry.
    case fillTiled(
        CGPath,
        tileCommands: [SVGRenderCommand],
        pattern: SVGResolvedPattern,
        opacity: CGFloat,
        evenOdd: Bool
    )

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

    /// Draw a decoded raster image into `viewport` with `preserveAspectRatio` fitting.
    case drawImage(
        imageData: Data,
        viewport: CGRect,
        preserveAspectRatio: SVGPreserveAspectRatio,
        opacity: CGFloat
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
        let ctx = Context(
            paintServers: document.paintServers,
            externalPaintServers: document.externalPaintServers,
            clipPaths: document.clipPaths,
            masks: document.masks,
            fonts: document.fonts,
            fontFaces: document.fontFaces,
            definitions: document.definitions,
            resourcePolicy: document.resourcePolicy,
            parsingLimits: document.parsingLimits
        )
        commands.append(.pushState)
        if let viewBox = document.viewBox, let size = document.intrinsicSize {
            let sx = size.width / viewBox.width
            let sy = size.height / viewBox.height
            var t = CGAffineTransform(scaleX: sx, y: sy)
            t = t.translatedBy(x: -viewBox.origin.x, y: -viewBox.origin.y)
            commands.append(.concatenate(SVGTransform(t)))
        }
        if let clipRect = rootClipRect(document) {
            commands.append(.clipToPath(CGPath(rect: clipRect, transform: nil), evenOdd: false))
        }
        lower(group: document.root, ctx: ctx, into: &commands)
        commands.append(.popState)
        return commands
    }

    /// User-space clip rect for the outermost `<svg>` viewport (`overflow: hidden`).
    private static func rootClipRect(_ document: SVGDocument) -> CGRect? {
        if let viewBox = document.viewBox {
            return viewBox
        }
        if let size = document.intrinsicSize, size.width > 0, size.height > 0 {
            return CGRect(origin: .zero, size: size)
        }
        return nil
    }

    private static func lower(svg: SVGSVGElement, ctx: Context, into commands: inout [SVGRenderCommand]) {
        var inner: [SVGRenderCommand] = []
        inner.append(.pushState)
        if svg.origin != .zero {
            inner.append(.concatenate(SVGTransform(CGAffineTransform(
                translationX: svg.origin.x, y: svg.origin.y
            ))))
        }
        if svg.overflow == .hidden, svg.size.width > 0, svg.size.height > 0 {
            inner.append(.clipToPath(
                CGPath(rect: CGRect(origin: .zero, size: svg.size), transform: nil),
                evenOdd: false
            ))
        }
        if let vb = svg.viewBox, svg.size.width > 0, svg.size.height > 0, vb.width > 0, vb.height > 0 {
            let t = SVGPreserveAspectRatio.viewBoxTransform(
                viewBox: vb,
                viewportSize: svg.size,
                preserveAspectRatio: svg.preserveAspectRatio
            )
            inner.append(.concatenate(SVGTransform(t)))
        }
        for child in svg.children {
            lower(element: child, ctx: ctx, into: &inner)
        }
        inner.append(.popState)
        commands.append(contentsOf: inner)
    }

    fileprivate final class Context {
        let paintServers: [String: SVGPaintServer]
        let externalPaintServers: [String: [String: SVGPaintServer]]
        let clipPaths: [String: SVGClipPath]
        let masks: [String: SVGMask]
        let fonts: [String: SVGFontDefinition]
        let fontFaces: [SVGFontFace]
        let definitions: [String: SVGElement]
        let resourcePolicy: SVGResourcePolicy
        let parsingLimits: SVGParsingLimits
        /// Active `<use href>` ids while expanding a use subtree; breaks cycles.
        var useExpansionChain: Set<String> = []

        init(
            paintServers: [String: SVGPaintServer],
            externalPaintServers: [String: [String: SVGPaintServer]],
            clipPaths: [String: SVGClipPath],
            masks: [String: SVGMask],
            fonts: [String: SVGFontDefinition],
            fontFaces: [SVGFontFace],
            definitions: [String: SVGElement],
            resourcePolicy: SVGResourcePolicy,
            parsingLimits: SVGParsingLimits
        ) {
            self.paintServers = paintServers
            self.externalPaintServers = externalPaintServers
            self.clipPaths = clipPaths
            self.masks = masks
            self.fonts = fonts
            self.fontFaces = fontFaces
            self.definitions = definitions
            self.resourcePolicy = resourcePolicy
            self.parsingLimits = parsingLimits
        }
    }

    private static func lower(group: SVGGroup, ctx: Context, into commands: inout [SVGRenderCommand]) {
        var inner: [SVGRenderCommand] = []
        let hasClip = group.clipPathRef != nil
        let needsState = hasClip || group.transform.matrix != .identity
        if needsState { inner.append(.pushState) }
        if group.transform.matrix != .identity {
            inner.append(.concatenate(group.transform))
        }
        if let clipRef = group.clipPathRef {
            guard appendClipPath(clipRef, bbox: nil, ctx: ctx, into: &inner) else { return }
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
        if maskCommands.isEmpty { return nil }
        return [.maskedContent(mask: maskCommands, region: maskRegion(mask, bbox: bbox), content: content)]
    }

    /// Append a resolved clip path, or return `false` when the definition is empty
    /// (the caller must suppress the element per SVG 1.1 §14.3).
    @discardableResult
    private static func appendClipPath(
        _ ref: String,
        bbox: CGRect?,
        ctx: Context,
        into commands: inout [SVGRenderCommand]
    ) -> Bool {
        guard let clipDef = ctx.clipPaths[ref] else { return true }
        let path = lowerToClipPath(clipDef, bbox: bbox, ctx: ctx)
        guard !path.isEmpty else { return false }
        commands.append(.clipToPath(path, evenOdd: false))
        return true
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
        case .svg(let svg):
            lower(svg: svg, ctx: ctx, into: &commands)
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
        case .use(let u):
            lower(use: u, ctx: ctx, into: &commands)
        case .image(let img):
            lower(image: img, ctx: ctx, into: &commands)
        }
    }

    private static func lower(image: SVGImage, ctx: Context, into commands: inout [SVGRenderCommand]) {
        guard image.paint.visibility == .visible else { return }
        if let document = image.referencedDocument {
            lowerSVGImageContent(document: document, image: image, ctx: ctx, into: &commands)
            return
        }
        guard let imageData = SVGImageDataLoader.load(
            href: image.href,
            policy: ctx.resourcePolicy,
            limits: ctx.parsingLimits
        ) else { return }

        let viewport = CGRect(origin: image.origin, size: image.size)
        emitPaintedImage(
            imageData: imageData,
            viewport: viewport,
            preserveAspectRatio: image.preserveAspectRatio,
            paint: image.paint,
            transform: image.transform,
            ctx: ctx,
            into: &commands
        )
    }

    private static func lowerSVGImageContent(
        document: SVGDocument,
        image: SVGImage,
        ctx: Context,
        into commands: inout [SVGRenderCommand]
    ) {
        let contentViewBox: CGRect
        if let viewBox = document.viewBox {
            contentViewBox = viewBox
        } else if let size = document.intrinsicSize, size.width > 0, size.height > 0 {
            contentViewBox = CGRect(origin: .zero, size: size)
        } else {
            return
        }
        guard contentViewBox.width > 0, contentViewBox.height > 0 else { return }

        let intrinsicSize = contentViewBox.size
        var viewport = CGRect(origin: image.origin, size: image.size)
        if viewport.width <= 0 { viewport.size.width = intrinsicSize.width }
        if viewport.height <= 0 { viewport.size.height = intrinsicSize.height }
        guard viewport.width > 0, viewport.height > 0 else { return }

        let nestedCtx = Context(
            paintServers: document.paintServers,
            externalPaintServers: document.externalPaintServers,
            clipPaths: document.clipPaths,
            masks: document.masks,
            fonts: document.fonts,
            fontFaces: document.fontFaces,
            definitions: document.definitions,
            resourcePolicy: document.resourcePolicy,
            parsingLimits: document.parsingLimits
        )

        var painted: [SVGRenderCommand] = []
        let hasClip = image.paint.clipPathRef != nil
        let needsState = hasClip || image.transform.matrix != .identity || image.paint.opacity < 1
        if needsState { painted.append(.pushState) }
        if image.transform.matrix != .identity {
            painted.append(.concatenate(image.transform))
        }
        if let clipRef = image.paint.clipPathRef {
            guard appendClipPath(clipRef, bbox: viewport, ctx: ctx, into: &painted) else { return }
        }
        if image.paint.opacity < 1 {
            painted.append(.beginOpacityLayer(image.paint.opacity))
        }

        painted.append(.pushState)
        painted.append(.clipToPath(CGPath(rect: viewport, transform: nil), evenOdd: false))
        let fit = CGAffineTransform(translationX: viewport.minX, y: viewport.minY)
            .concatenating(SVGPreserveAspectRatio.viewBoxTransform(
                viewBox: contentViewBox,
                viewportSize: viewport.size,
                preserveAspectRatio: image.preserveAspectRatio
            ))
        painted.append(.concatenate(SVGTransform(fit)))
        lower(group: document.root, ctx: nestedCtx, into: &painted)
        painted.append(.popState)

        if image.paint.opacity < 1 { painted.append(.endOpacityLayer) }
        if needsState { painted.append(.popState) }

        guard let wrapped = applyMask(image.paint.maskRef, bbox: viewport, content: painted, ctx: ctx) else {
            return
        }
        commands.append(contentsOf: wrapped)
    }

    private static func emitPaintedImage(
        imageData: Data,
        viewport: CGRect,
        preserveAspectRatio: SVGPreserveAspectRatio,
        paint: SVGPaintProperties,
        transform: SVGTransform,
        ctx: Context,
        into commands: inout [SVGRenderCommand]
    ) {
        let bbox = viewport.isNull || viewport.isEmpty
            ? CGRect(origin: viewport.origin, size: CGSize(width: 1, height: 1))
            : viewport

        var painted: [SVGRenderCommand] = []
        let hasClip = paint.clipPathRef != nil
        let needsState = hasClip || transform.matrix != .identity || paint.opacity < 1
        if needsState { painted.append(.pushState) }
        if transform.matrix != .identity {
            painted.append(.concatenate(transform))
        }
        if let clipRef = paint.clipPathRef {
            guard appendClipPath(clipRef, bbox: bbox, ctx: ctx, into: &painted) else { return }
        }
        if paint.opacity < 1 {
            painted.append(.beginOpacityLayer(paint.opacity))
        }

        painted.append(.drawImage(
            imageData: imageData,
            viewport: viewport,
            preserveAspectRatio: preserveAspectRatio,
            opacity: 1
        ))

        if paint.opacity < 1 { painted.append(.endOpacityLayer) }
        if needsState { painted.append(.popState) }

        guard let wrapped = applyMask(paint.maskRef, bbox: bbox, content: painted, ctx: ctx) else { return }
        commands.append(contentsOf: wrapped)
    }

    private static func lower(use: SVGUse, ctx: Context, into commands: inout [SVGRenderCommand]) {
        guard use.paint.visibility == .visible else { return }
        guard !ctx.useExpansionChain.contains(use.href) else { return }
        ctx.useExpansionChain.insert(use.href)
        defer { ctx.useExpansionChain.remove(use.href) }

        guard let (element, placement) = expandUse(
            use, definitions: ctx.definitions, chain: &ctx.useExpansionChain
        ) else { return }
        var inner: [SVGRenderCommand] = []
        inner.append(.pushState)
        if placement != .identity {
            inner.append(.concatenate(SVGTransform(placement)))
        }
        lower(element: element, ctx: ctx, into: &inner)
        inner.append(.popState)
        commands.append(contentsOf: inner)
    }

    /// Resolve a `<use>` to instanced geometry and a placement transform.
    private static func expandUse(
        _ use: SVGUse,
        definitions: [String: SVGElement],
        chain: inout Set<String>
    ) -> (SVGElement, CGAffineTransform)? {
        guard let def = definitions[use.href] else { return nil }
        let placement = SVGUseExpansion.placementTransform(for: use)
        switch def {
        case .use(let inner):
            guard !chain.contains(inner.href) else { return nil }
            guard let (resolved, innerPlacement) = expandUse(
                inner, definitions: definitions, chain: &chain
            ) else {
                return nil
            }
            var instanced = SVGUseExpansion.instanceElement(resolved, use: inner)
            instanced = SVGUseExpansion.instanceElement(instanced, use: use)
            return (instanced, placement.concatenating(innerPlacement))
        default:
            let instanced = SVGUseExpansion.instanceElement(def, use: use)
            return (instanced, placement)
        }
    }

    private static func lower(rect: SVGRect, ctx: Context, into commands: inout [SVGRenderCommand]) {
        // SVG 1.1 §9.2: zero (or negative) width/height disables rendering.
        guard rect.size.width > 0, rect.size.height > 0 else { return }
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
        guard !polyline.points.isEmpty else { return }

        // SVG 1.1 §11.4 / painting-control-03-f: filled polylines close the path
        // for fill only; stroke follows the open point list.
        if !isPaintNone(polyline.paint.fill),
           let fillPath = polylinePath(points: polyline.points, closed: true) {
            var fillOnly = polyline.paint
            fillOnly.stroke = .none
            emitPaintedPath(fillPath, paint: fillOnly, transform: polyline.transform, ctx: ctx, into: &commands)
        }

        if !isPaintNone(polyline.paint.stroke),
           let strokePath = polylinePath(points: polyline.points, closed: false) {
            var strokeOnly = polyline.paint
            strokeOnly.fill = .none
            emitPaintedPath(strokePath, paint: strokeOnly, transform: polyline.transform, ctx: ctx, into: &commands)
        }
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
        guard !text.runs.isEmpty else { return }
        guard text.paint.visibility == .visible else { return }

        if text.runs.count == 1,
           let run = text.runs.first,
           run.dx == 0, run.dy == 0,
           run.explicitX == nil, run.explicitY == nil,
           run.font == text.font,
           run.paint == text.paint {
            guard !run.string.isEmpty else { return }
            guard let path = TextLayout.glyphPath(
                string: run.string,
                font: run.font,
                origin: text.origin,
                fontFaces: ctx.fontFaces,
                fonts: ctx.fonts
            ) else { return }
            emitPaintedPath(path, paint: run.paint, transform: text.transform, ctx: ctx, into: &commands)
            return
        }

        guard let path = TextLayout.glyphPath(
            text: text,
            fontFaces: ctx.fontFaces,
            fonts: ctx.fonts
        ) else { return }

        // Per-run paint: emit separate paths when runs differ in fill/stroke.
        let uniformPaint = text.runs.allSatisfy { $0.paint == text.runs[0].paint }
        if uniformPaint, let paint = text.runs.first?.paint {
            emitPaintedPath(path, paint: paint, transform: text.transform, ctx: ctx, into: &commands)
            return
        }

        emitRunsIndividually(text: text, ctx: ctx, into: &commands)
    }

    private static func emitRunsIndividually(
        text: SVGText,
        ctx: Context,
        into commands: inout [SVGRenderCommand]
    ) {
        let segments = TextLayout.layoutRuns(
            text: text,
            fontFaces: ctx.fontFaces,
            fonts: ctx.fonts
        )
        for segment in segments {
            guard segment.run.paint.visibility == .visible else { continue }
            emitPaintedPath(
                segment.path,
                paint: segment.run.paint,
                transform: text.transform,
                ctx: ctx,
                into: &commands
            )
        }
    }

    /// Build a `CGPath` from all shape children of a `<clipPath>` definition.
    /// When `clipPathUnits="objectBoundingBox"` and a `bbox` is supplied, the
    /// clip coordinates (in [0,1] space) are mapped to that bounding box.
    private static func lowerToClipPath(_ clipDef: SVGClipPath, bbox: CGRect?, ctx: Context) -> CGPath {
        let obbTransform: CGAffineTransform? = (clipDef.units == .objectBoundingBox)
            ? bbox.map { b in
                CGAffineTransform(translationX: b.minX, y: b.minY)
                    .scaledBy(x: b.width, y: b.height)
              }
            : nil
        let combined = CGMutablePath()
        for element in clipDef.children {
            combined.addPath(
                clipPathGeometry(for: element, transform: .identity, obbTransform: obbTransform, ctx: ctx, chain: [])
            )
        }
        return combined
    }

    private static func clipPathGeometry(
        for element: SVGElement,
        transform: CGAffineTransform,
        obbTransform: CGAffineTransform?,
        ctx: Context,
        chain: Set<String>
    ) -> CGPath {
        switch element {
        case .use(let u):
            guard u.paint.visibility == .visible else { return CGMutablePath() }
            guard !chain.contains(u.href) else { return CGMutablePath() }
            var expansionChain = chain
            expansionChain.insert(u.href)
            guard let (resolved, placement) = expandUse(
                u, definitions: ctx.definitions, chain: &expansionChain
            ) else {
                return CGMutablePath()
            }
            return clipPathGeometry(
                for: resolved,
                transform: transform.concatenating(placement),
                obbTransform: obbTransform,
                ctx: ctx,
                chain: expansionChain
            )
        case .group(let g):
            guard g.visibility == .visible else { return CGMutablePath() }
            let path = CGMutablePath()
            var gtx = transform
            if g.transform.matrix != .identity {
                gtx = gtx.concatenating(g.transform.matrix)
            }
            for child in g.children {
                path.addPath(
                    clipPathGeometry(for: child, transform: gtx, obbTransform: obbTransform, ctx: ctx, chain: chain)
                )
            }
            return path
        case .svg(let svg):
            let path = CGMutablePath()
            var tx = transform
            if svg.origin != .zero {
                tx = tx.concatenating(CGAffineTransform(translationX: svg.origin.x, y: svg.origin.y))
            }
            if let vb = svg.viewBox, svg.size.width > 0, svg.size.height > 0, vb.width > 0, vb.height > 0 {
                let t = SVGPreserveAspectRatio.viewBoxTransform(
                    viewBox: vb,
                    viewportSize: svg.size,
                    preserveAspectRatio: svg.preserveAspectRatio
                )
                tx = tx.concatenating(t)
            }
            for child in svg.children {
                path.addPath(
                    clipPathGeometry(for: child, transform: tx, obbTransform: obbTransform, ctx: ctx, chain: chain)
                )
            }
            return path
        case .rect(let r):
            guard r.paint.visibility == .visible else { return CGMutablePath() }
            guard r.size.width > 0, r.size.height > 0 else { return CGMutablePath() }
            let cgRect = CGRect(origin: r.origin, size: r.size)
            let p: CGPath = r.cornerRadii == .zero
                ? CGPath(rect: cgRect, transform: nil)
                : CGPath(roundedRect: cgRect, cornerWidth: r.cornerRadii.width,
                         cornerHeight: r.cornerRadii.height, transform: nil)
            var tx = transform.concatenating(r.transform.matrix)
            if let obb = obbTransform { tx = tx.isIdentity ? obb : tx.concatenating(obb) }
            return p.copy(using: &tx) ?? p
        case .circle(let c):
            guard c.paint.visibility == .visible else { return CGMutablePath() }
            guard c.radius > 0 else { return CGMutablePath() }
            let bounds = CGRect(
                x: c.center.x - c.radius, y: c.center.y - c.radius,
                width: c.radius * 2, height: c.radius * 2
            )
            let p = CGPath(ellipseIn: bounds, transform: nil)
            var tx = transform.concatenating(c.transform.matrix)
            if let obb = obbTransform { tx = tx.isIdentity ? obb : tx.concatenating(obb) }
            return p.copy(using: &tx) ?? p
        case .ellipse(let e):
            guard e.paint.visibility == .visible else { return CGMutablePath() }
            guard e.radii.width > 0, e.radii.height > 0 else { return CGMutablePath() }
            let bounds = CGRect(
                x: e.center.x - e.radii.width, y: e.center.y - e.radii.height,
                width: e.radii.width * 2, height: e.radii.height * 2
            )
            let p = CGPath(ellipseIn: bounds, transform: nil)
            var tx = transform.concatenating(e.transform.matrix)
            if let obb = obbTransform { tx = tx.isIdentity ? obb : tx.concatenating(obb) }
            return p.copy(using: &tx) ?? p
        case .path(let sp):
            guard sp.paint.visibility == .visible else { return CGMutablePath() }
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
            var tx = transform.concatenating(sp.transform.matrix)
            if let obb = obbTransform { tx = tx.isIdentity ? obb : tx.concatenating(obb) }
            return cg.copy(using: &tx) ?? cg
        case .polyline(let pl):
            guard pl.paint.visibility == .visible else { return CGMutablePath() }
            guard let p = polylinePath(points: pl.points, closed: false) else { return CGMutablePath() }
            var tx = transform.concatenating(pl.transform.matrix)
            if let obb = obbTransform { tx = tx.isIdentity ? obb : tx.concatenating(obb) }
            return p.copy(using: &tx) ?? p
        case .polygon(let pg):
            guard pg.paint.visibility == .visible else { return CGMutablePath() }
            guard let p = polylinePath(points: pg.points, closed: true) else { return CGMutablePath() }
            var tx = transform.concatenating(pg.transform.matrix)
            if let obb = obbTransform { tx = tx.isIdentity ? obb : tx.concatenating(obb) }
            return p.copy(using: &tx) ?? p
        case .line, .text, .image:
            return CGMutablePath()
        }
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
        if let clipRef = paint.clipPathRef {
            guard appendClipPath(clipRef, bbox: bbox, ctx: ctx, into: &painted) else { return }
        }
        if paint.opacity < 1 {
            painted.append(.beginOpacityLayer(paint.opacity))
        }

        let resolvedFill = resolvePaint(paint.fill, bbox: bbox, currentColor: paint.color, ctx: ctx)
        let resolvedStroke = resolvePaint(paint.stroke, bbox: bbox, currentColor: paint.color, ctx: ctx)

        if case .pattern(let pat) = resolvedFill {
            emitTiledFill(
                path, pattern: pat, opacity: paint.fillOpacity,
                evenOdd: paint.fillRule == .evenodd, ctx: ctx, into: &painted
            )
        } else if case .none = resolvedFill {} else {
            painted.append(.fillPath(
                path,
                paint: resolvedFill,
                opacity: paint.fillOpacity,
                evenOdd: paint.fillRule == .evenodd
            ))
        }
        if case .pattern(let pat) = resolvedStroke {
            let outline = path.copy(
                strokingWithWidth: paint.strokeWidth,
                lineCap: cgLineCap(paint.lineCap),
                lineJoin: cgLineJoin(paint.lineJoin),
                miterLimit: paint.miterLimit
            )
            emitTiledFill(
                outline, pattern: pat, opacity: paint.strokeOpacity,
                evenOdd: false, ctx: ctx, into: &painted
            )
            var stampPaint = paint
            stampPaint.stroke = resolvedStroke
            emitZeroLengthCapStamps(path: path, paint: stampPaint, into: &painted)
        } else if case .none = resolvedStroke {} else {
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

    private static func isPaintNone(_ paint: SVGPaint) -> Bool {
        if case .none = paint { return true }
        return false
    }

    /// Convert `.paintServer` references into concrete paint cases with the
    /// gradient endpoints baked into user space against `bbox`. Returns the
    /// input unchanged for colors and `.none`; returns `.none` for dangling
    /// or stop-less references. Uses the optional fallback paint when the
    /// server is missing or invalid (SVG 1.1 §13.2.4).
    private static func resolvePaint(
        _ paint: SVGPaint,
        bbox: CGRect,
        currentColor: SVGColor,
        ctx: Context
    ) -> SVGPaint {
        switch paint {
        case .currentColor:
            return .color(currentColor)
        case .paintServer(let id, let fallback, let scope):
            let servers: [String: SVGPaintServer] = {
                switch scope {
                case .document:
                    return ctx.paintServers
                case .external(let sourceKey):
                    return ctx.externalPaintServers[sourceKey] ?? [:]
                }
            }()
            guard let server = servers[id] else {
                if let fallback { return .color(fallback) }
                return .none
            }
            let resolved = resolvePaintServer(server, bbox: bbox, ctx: ctx)
            if case .none = resolved {
                let useFallback: Bool = {
                    switch server {
                    case .pattern(let p):
                        if p.width <= 0 || p.height <= 0 {
                            return p.viewBox == nil
                        }
                        return false
                    default:
                        return true
                    }
                }()
                if useFallback, let fallback { return .color(fallback) }
                return .none
            }
            return resolved
        default:
            return paint
        }
    }

    private static func resolvePaintServer(
        _ server: SVGPaintServer,
        bbox: CGRect,
        ctx: Context
    ) -> SVGPaint {
        switch server {
        case .linearGradient(let g):
            guard !g.stops.isEmpty else { return .none }
            var concrete = g
            if g.units == .objectBoundingBox {
                // Lines (and other 1-D geometry) have a degenerate bbox; OBB
                // gradients are undefined and the ICC fallback applies
                // (pservers-grad-17-b, pservers-grad-20-b).
                guard bbox.width > 0, bbox.height > 0 else { return .none }
                // Map gradient coordinates through the bounding-box affine
                // transform (same as radial gradients). Baking endpoints into user
                // space would keep stop lines perpendicular in user space instead
                // of skewing them when width ≠ height (pservers-grad-04-b).
                let obbToUser = CGAffineTransform(translationX: bbox.minX, y: bbox.minY)
                    .scaledBy(x: bbox.width, y: bbox.height)
                let gt = g.transform.matrix
                concrete.transform = SVGTransform(gt.isIdentity ? obbToUser : obbToUser.concatenating(gt))
                concrete.units = .userSpaceOnUse
            }
            return .linearGradient(concrete)
        case .radialGradient(let g):
            guard !g.stops.isEmpty else { return .none }
            var concrete = g
            if g.units == .objectBoundingBox {
                let obbToUser = CGAffineTransform(translationX: bbox.minX, y: bbox.minY)
                    .scaledBy(x: bbox.width, y: bbox.height)
                let gt = g.transform.matrix
                concrete.transform = SVGTransform(gt.isIdentity ? obbToUser : obbToUser.concatenating(gt))
                concrete.units = .userSpaceOnUse
            }
            return .radialGradient(concrete)
        case .pattern(let p):
            guard p.width > 0, p.height > 0 else { return .none }
            guard let resolved = resolvePattern(p, referencingBBox: bbox, ctx: ctx) else { return .none }
            return .pattern(resolved)
        }
    }

    private static func resolvePattern(
        _ pattern: SVGPattern,
        referencingBBox: CGRect,
        ctx: Context
    ) -> SVGResolvedPattern? {
        let tileLocalContent = pattern.patternContentUnits == .userSpaceOnUse && pattern.viewBox == nil
        let boundingBoxContent = pattern.patternContentUnits == .objectBoundingBox && pattern.viewBox == nil
        var x = pattern.x
        var y = pattern.y
        var step = CGSize(width: pattern.width, height: pattern.height)
        var patternToUser = pattern.transform.matrix

        if boundingBoxContent || tileLocalContent {
            if pattern.patternUnits == .objectBoundingBox {
                guard !referencingBBox.isNull, !referencingBBox.isEmpty else { return nil }
                x = referencingBBox.minX + pattern.x * referencingBBox.width
                y = referencingBBox.minY + pattern.y * referencingBBox.height
                step = CGSize(
                    width: pattern.width * referencingBBox.width,
                    height: pattern.height * referencingBBox.height
                )
            }
        } else {
            switch pattern.patternUnits {
            case .userSpaceOnUse:
                break
            case .objectBoundingBox:
                guard !referencingBBox.isNull, !referencingBBox.isEmpty else { return nil }
                let obb = CGAffineTransform(translationX: referencingBBox.minX, y: referencingBBox.minY)
                    .scaledBy(x: referencingBBox.width, y: referencingBBox.height)
                patternToUser = obb.concatenating(pattern.transform.matrix)
            }
        }

        return SVGResolvedPattern(
            children: pattern.children,
            patternToUser: SVGTransform(patternToUser),
            x: x,
            y: y,
            step: step,
            contentMatrix: SVGTransform(patternContentMatrix(pattern, referencingBBox: referencingBBox)),
            tileLocalContent: tileLocalContent,
            boundingBoxContent: boundingBoxContent
        )
    }

    /// Maps pattern content coordinates into tile-local `(0,0)…(width,height)`.
    private static func patternContentMatrix(
        _ pattern: SVGPattern,
        referencingBBox: CGRect
    ) -> CGAffineTransform {
        if pattern.patternContentUnits == .userSpaceOnUse, pattern.viewBox == nil {
            return .identity
        }
        var t = CGAffineTransform.identity
        if pattern.patternContentUnits == .objectBoundingBox,
           !referencingBBox.isNull, !referencingBBox.isEmpty {
            t = CGAffineTransform(translationX: referencingBBox.minX, y: referencingBBox.minY)
                .scaledBy(x: referencingBBox.width, y: referencingBBox.height)
        }
        if let vb = pattern.viewBox, vb.width > 0, vb.height > 0 {
            let vbMap = CGAffineTransform(translationX: -vb.minX, y: -vb.minY)
                .scaledBy(x: pattern.width / vb.width, y: pattern.height / vb.height)
            t = pattern.patternContentUnits == .objectBoundingBox
                ? t.concatenating(vbMap)
                : vbMap
        }
        return t
    }

    private static func emitTiledFill(
        _ path: CGPath,
        pattern: SVGResolvedPattern,
        opacity: CGFloat,
        evenOdd: Bool,
        ctx: Context,
        into commands: inout [SVGRenderCommand]
    ) {
        var tileCommands: [SVGRenderCommand] = []
        for child in pattern.children {
            lower(element: child, ctx: ctx, into: &tileCommands)
        }
        commands.append(.fillTiled(
            path,
            tileCommands: tileCommands,
            pattern: pattern,
            opacity: opacity,
            evenOdd: evenOdd
        ))
    }

    private static func cgLineCap(_ cap: SVGLineCap) -> CGLineCap {
        switch cap {
        case .butt: return .butt
        case .round: return .round
        case .square: return .square
        }
    }

    private static func cgLineJoin(_ join: SVGLineJoin) -> CGLineJoin {
        switch join {
        case .miter: return .miter
        case .round: return .round
        case .bevel: return .bevel
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
