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
                // Gradients with a non-identity gradientTransform (including the
                // OBB→userSpace mapping for objectBoundingBox units) are painted
                // in gradient space: transform the context, inverse-transform
                // the path so it still clips in screen space.
                if let tx = gradientPaintTransform(paint) {
                    context.drawLayer { layerCtx in
                        layerCtx.concatenate(tx)
                        layerCtx.fill(
                            Path(cgPath).applying(tx.inverted()),
                            with: shading,
                            style: FillStyle(eoFill: evenOdd)
                        )
                    }
                } else {
                    context.fill(Path(cgPath), with: shading, style: FillStyle(eoFill: evenOdd))
                }

            case .fillTiled(let cgPath, let tileCommands, let pattern, let opacity, let evenOdd):
                context.drawLayer { layer in
                    layer.opacity *= opacity
                    layer.clip(to: Path(cgPath), style: FillStyle(eoFill: evenOdd))
                    tilePattern(
                        pattern,
                        tileCommands: tileCommands,
                        clipBounds: cgPath.boundingBoxOfPath,
                        context: &layer
                    )
                }

            case .strokePath(let cgPath, let paint, let opacity, let width, let cap, let join, let miterLimit, let dashArray, let dashPhase):
                guard let shading = shading(for: paint, opacity: opacity) else { continue }
                let style = StrokeStyle(
                    lineWidth: width,
                    lineCap: lineCap(cap),
                    lineJoin: lineJoin(join),
                    miterLimit: miterLimit,
                    dash: dashArray,
                    dashPhase: dashPhase
                )
                if let tx = gradientPaintTransform(paint) {
                    context.drawLayer { layerCtx in
                        layerCtx.concatenate(tx)
                        layerCtx.stroke(
                            Path(cgPath).applying(tx.inverted()),
                            with: shading,
                            style: style
                        )
                    }
                } else {
                    context.stroke(Path(cgPath), with: shading, style: style)
                }

            case .clipToPath(let cgPath, _):
                context.clip(to: Path(cgPath))

            case .maskedContent(let maskCommands, let region, let contentCommands):
                // SVG masking: the content is composited through the mask, where
                // each pixel's mask value is luminance × alpha. The mask content
                // here is rendered into a layer and its alpha channel is used as
                // the clip. For white mask content (luminance = 1) this is exact;
                // the alpha already carries the intended mask value.
                context.drawLayer { layer in
                    layer.clipToLayer { maskContext in
                        if let region {
                            maskContext.clip(to: Path(region))
                        }
                        self.execute(maskCommands, context: &maskContext)
                    }
                    self.execute(contentCommands, context: &layer)
                }

            case .groupLayer(let opacity, let commands):
                // SVG group opacity (§11.3): render children into an isolated
                // layer at full opacity, then composite the layer at `opacity`.
                // This prevents overlapping children from showing through each
                // other — unlike multiplying opacity per element.
                let savedOpacity = context.opacity
                context.opacity = savedOpacity * opacity
                context.drawLayer { layerCtx in
                    var l = layerCtx
                    self.execute(commands, context: &l)
                }
                context.opacity = savedOpacity
            }
        }
    }

    private func gradientPaintTransform(_ paint: SVGPaint) -> CGAffineTransform? {
        switch paint {
        case .linearGradient(let g) where !g.transform.matrix.isIdentity:
            return g.transform.matrix
        case .radialGradient(let g) where !g.transform.matrix.isIdentity:
            return g.transform.matrix
        default:
            return nil
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
        case .paintServer:
            // Unresolved server reference (lowering left it as-is, e.g. on
            // text where bbox isn't known). Treat as no paint.
            return nil
        case .pattern:
            // Patterns are lowered to `.fillTiled` before reaching the backend.
            return nil
        case .linearGradient(let g):
            guard !g.stops.isEmpty else { return nil }
            let stops = g.stops
                .sorted { $0.offset < $1.offset }
                .map { stop in
                    Gradient.Stop(
                        color: Color(
                            .sRGB,
                            red: Double(stop.color.red),
                            green: Double(stop.color.green),
                            blue: Double(stop.color.blue),
                            opacity: Double(stop.color.alpha * opacity)
                        ),
                        location: stop.offset
                    )
                }
            let options: GraphicsContext.GradientOptions
            switch g.spreadMethod {
            case .pad: options = []
            case .repeat: options = .repeat
            case .reflect: options = .mirror
            }
            return .linearGradient(
                Gradient(stops: stops),
                startPoint: CGPoint(x: g.x1, y: g.y1),
                endPoint: CGPoint(x: g.x2, y: g.y2),
                options: options
            )
        case .radialGradient(let g):
            guard !g.stops.isEmpty else { return nil }
            let stops = g.stops
                .sorted { $0.offset < $1.offset }
                .map { stop in
                    Gradient.Stop(
                        color: Color(
                            .sRGB,
                            red: Double(stop.color.red),
                            green: Double(stop.color.green),
                            blue: Double(stop.color.blue),
                            opacity: Double(stop.color.alpha * opacity)
                        ),
                        location: stop.offset
                    )
                }
            let options: GraphicsContext.GradientOptions
            switch g.spreadMethod {
            case .pad: options = []
            case .repeat: options = .repeat
            case .reflect: options = .mirror
            }
            return .radialGradient(
                Gradient(stops: stops),
                center: CGPoint(x: g.cx, y: g.cy),
                startRadius: 0,
                endRadius: g.r,
                options: options
            )
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

    /// Tile `tileCommands` across `clipBounds` using the resolved pattern grid.
    private func tilePattern(
        _ pattern: SVGResolvedPattern,
        tileCommands: [SVGRenderCommand],
        clipBounds: CGRect,
        context: inout GraphicsContext
    ) {
        let step = pattern.step
        guard step.width > 0, step.height > 0 else { return }

        let tileClip = CGRect(x: 0, y: 0, width: step.width, height: step.height)

        if pattern.tileLocalContent {
            // Grid may be transformed (patternTransform); compute tile indices in pattern space.
            let inv = pattern.patternToUser.matrix.inverted()
            let localBounds = clipBounds.applying(inv)
            let startI = Int(floor((localBounds.minX - pattern.x) / step.width)) - 1
            let endI = Int(ceil((localBounds.maxX - pattern.x) / step.width)) + 1
            let startJ = Int(floor((localBounds.minY - pattern.y) / step.height)) - 1
            let endJ = Int(ceil((localBounds.maxY - pattern.y) / step.height)) + 1

            for j in startJ...endJ {
                for i in startI...endI {
                    context.drawLayer { tile in
                        tile.concatenate(pattern.patternToUser.matrix)
                        tile.concatenate(CGAffineTransform(
                            translationX: pattern.x + CGFloat(i) * step.width,
                            y: pattern.y + CGFloat(j) * step.height
                        ))
                        tile.clip(to: Path(tileClip))
                        self.execute(tileCommands, context: &tile)
                    }
                }
            }
            return
        }

        // Tile indices are computed in pattern coordinate space.
        let inv = pattern.patternToUser.matrix.inverted()
        let localBounds = clipBounds.applying(inv)

        let startI = Int(floor((localBounds.minX - pattern.x) / step.width)) - 1
        let endI = Int(ceil((localBounds.maxX - pattern.x) / step.width)) + 1
        let startJ = Int(floor((localBounds.minY - pattern.y) / step.height)) - 1
        let endJ = Int(ceil((localBounds.maxY - pattern.y) / step.height)) + 1

        for j in startJ...endJ {
            for i in startI...endI {
                context.drawLayer { tile in
                    tile.concatenate(pattern.patternToUser.matrix)
                    tile.concatenate(CGAffineTransform(
                        translationX: pattern.x + CGFloat(i) * step.width,
                        y: pattern.y + CGFloat(j) * step.height
                    ))
                    tile.concatenate(pattern.contentMatrix.matrix)
                    self.execute(tileCommands, context: &tile)
                }
            }
        }
    }
}

#endif
