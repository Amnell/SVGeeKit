import CoreGraphics
import SwiftUI
import SVGCore
import SVGRenderer

#if canImport(SwiftUI)

/// SwiftUI `GraphicsContext`-based implementation of `SVGRendererBackend`.
/// Used directly inside `Canvas { ctx, _ in ... }` and indirectly by `Rasterizer`.
public struct SwiftUICanvasRenderer {

    public init() {}

    /// Execute a render-command stream into the supplied SwiftUI graphics context.
    /// The caller owns the context (set up by `Canvas` or `ImageRenderer`).
    public func execute(
        _ commands: [SVGRenderCommand],
        context: inout GraphicsContext
    ) {
        var stateStack: [GraphicsContext] = []

        for command in commands {
            switch command {
            case .pushState:
                stateStack.append(context)

            case .popState:
                if let restored = stateStack.popLast() {
                    context = restored
                }

            case .concatenate(let transform):
                context.concatenate(transform.matrix)

            case .beginOpacityLayer(let opacity):
                stateStack.append(context)
                context.opacity *= opacity

            case .endOpacityLayer:
                if let restored = stateStack.popLast() {
                    context = restored
                }

            case .fillPath(let cgPath, let paint, let opacity, let evenOdd):
                guard let shading = shading(for: paint, opacity: opacity) else { continue }
                let path = Path(cgPath)
                context.fill(path, with: shading, style: FillStyle(eoFill: evenOdd))

            case .strokePath(let cgPath, let paint, let opacity, let width, let cap, let join, let miterLimit):
                guard let shading = shading(for: paint, opacity: opacity) else { continue }
                let style = StrokeStyle(
                    lineWidth: width,
                    lineCap: lineCap(cap),
                    lineJoin: lineJoin(join),
                    miterLimit: miterLimit
                )
                context.stroke(Path(cgPath), with: shading, style: style)
            }
        }
    }

    private func shading(for paint: SVGPaint, opacity: CGFloat) -> GraphicsContext.Shading? {
        switch paint {
        case .none:
            return nil
        case .color(let c):
            let color = Color(
                .sRGB,
                red: Double(c.red),
                green: Double(c.green),
                blue: Double(c.blue),
                opacity: Double(c.alpha * opacity)
            )
            return .color(color)
        }
    }

    private func lineCap(_ c: SVGLineCap) -> CGLineCap {
        switch c {
        case .butt: return .butt
        case .round: return .round
        case .square: return .square
        }
    }

    private func lineJoin(_ j: SVGLineJoin) -> CGLineJoin {
        switch j {
        case .miter: return .miter
        case .round: return .round
        case .bevel: return .bevel
        }
    }
}

#endif
