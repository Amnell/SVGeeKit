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

        let needsState = rect.transform.matrix != .identity || rect.paint.opacity < 1
        if needsState { commands.append(.pushState) }
        if rect.transform.matrix != .identity {
            commands.append(.concatenate(rect.transform))
        }
        if rect.paint.opacity < 1 {
            commands.append(.beginOpacityLayer(rect.paint.opacity))
        }

        if case .none = rect.paint.fill {} else {
            commands.append(.fillPath(
                path,
                paint: rect.paint.fill,
                opacity: rect.paint.fillOpacity,
                evenOdd: false
            ))
        }
        if case .none = rect.paint.stroke {} else {
            commands.append(.strokePath(
                path,
                paint: rect.paint.stroke,
                opacity: rect.paint.strokeOpacity,
                width: rect.paint.strokeWidth,
                lineCap: rect.paint.lineCap,
                lineJoin: rect.paint.lineJoin,
                miterLimit: rect.paint.miterLimit
            ))
        }

        if rect.paint.opacity < 1 { commands.append(.endOpacityLayer) }
        if needsState { commands.append(.popState) }
    }
}
