import CoreGraphics
import SVGCore
import SVGRenderer

#if canImport(AppKit) || canImport(UIKit)

/// Core Graphics backend for `[SVGRenderCommand]` streams.
/// Used by `SVGRasterizer` for snapshot-quality output with SVG-correct gradients.
struct CGContextRenderer {

    private struct GfxState {
        var alpha: CGFloat = 1
    }

    func execute(_ commands: [SVGRenderCommand], in ctx: CGContext) {
        var gfx = GfxState()
        execute(commands, in: ctx, gfx: &gfx)
    }

    private func execute(
        _ commands: [SVGRenderCommand],
        in ctx: CGContext,
        gfx: inout GfxState
    ) {
        var stateStack: [GfxState] = []

        for command in commands {
            switch command {
            case .pushState:
                stateStack.append(gfx)
                ctx.saveGState()

            case .popState:
                if let restored = stateStack.popLast() {
                    gfx = restored
                }
                ctx.restoreGState()

            case .concatenate(let transform):
                ctx.concatenate(transform.matrix)

            case .beginOpacityLayer(let opacity):
                stateStack.append(gfx)
                gfx.alpha *= opacity

            case .endOpacityLayer:
                if let restored = stateStack.popLast() {
                    gfx = restored
                }

            case .fillPath(let cgPath, let paint, let opacity, let evenOdd):
                fill(
                    cgPath,
                    paint: paint,
                    paintOpacity: opacity,
                    gfx: gfx,
                    evenOdd: evenOdd,
                    in: ctx
                )

            case .fillTiled(let cgPath, let tileCommands, let pattern, let opacity, let evenOdd):
                ctx.saveGState()
                ctx.addPath(cgPath)
                ctx.clip(using: evenOdd ? .evenOdd : .winding)
                var tileGfx = gfx
                tileGfx.alpha *= opacity
                tilePattern(
                    pattern,
                    tileCommands: tileCommands,
                    clipBounds: cgPath.boundingBoxOfPath,
                    gfx: &tileGfx,
                    in: ctx
                )
                ctx.restoreGState()

            case .strokePath(let cgPath, let paint, let opacity, let width, let cap, let join, let miterLimit, let dashArray, let dashPhase):
                stroke(
                    cgPath,
                    paint: paint,
                    paintOpacity: opacity,
                    gfx: gfx,
                    width: width,
                    cap: cap,
                    join: join,
                    miterLimit: miterLimit,
                    dashArray: dashArray,
                    dashPhase: dashPhase,
                    in: ctx
                )

            case .clipToPath(let cgPath, let evenOdd):
                ctx.addPath(cgPath)
                ctx.clip(using: evenOdd ? .evenOdd : .winding)

            case .maskedContent(let maskCommands, let region, let contentCommands):
                ctx.saveGState()
                if let region {
                    ctx.clip(to: region)
                }
                if let mask = renderMaskImage(maskCommands, region: region, in: ctx) {
                    let clipRect = region ?? ctx.boundingBoxOfClipPath
                    ctx.clip(to: clipRect, mask: mask)
                }
                execute(contentCommands, in: ctx, gfx: &gfx)
                ctx.restoreGState()

            case .groupLayer(let opacity, let commands):
                ctx.saveGState()
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                execute(commands, in: ctx, gfx: &gfx)
                ctx.setAlpha(gfx.alpha * opacity)
                ctx.endTransparencyLayer()
                ctx.restoreGState()
            }
        }
    }

    // MARK: - Paint

    private func fill(
        _ path: CGPath,
        paint: SVGPaint,
        paintOpacity: CGFloat,
        gfx: GfxState,
        evenOdd: Bool,
        in ctx: CGContext
    ) {
        let effectiveOpacity = gfx.alpha * paintOpacity
        switch paint {
        case .none:
            return
        case .color(let c):
            ctx.saveGState()
            ctx.setFillColor(cgColor(c, opacity: effectiveOpacity))
            ctx.addPath(path)
            ctx.fillPath(using: evenOdd ? .evenOdd : .winding)
            ctx.restoreGState()
        case .linearGradient(let g):
            SVGGradientDrawing.drawLinearTiled(
                g,
                in: ctx,
                clipPath: path,
                paintOpacity: effectiveOpacity,
                evenOdd: evenOdd,
                transform: g.transform.matrix.isIdentity ? nil : g.transform.matrix
            )
        case .radialGradient(let g):
            SVGGradientDrawing.drawRadialTiled(
                g,
                in: ctx,
                clipPath: path,
                paintOpacity: effectiveOpacity,
                evenOdd: evenOdd,
                transform: g.transform.matrix.isIdentity ? nil : g.transform.matrix
            )
        case .paintServer, .pattern:
            return
        }
    }

    private func stroke(
        _ path: CGPath,
        paint: SVGPaint,
        paintOpacity: CGFloat,
        gfx: GfxState,
        width: CGFloat,
        cap: SVGLineCap,
        join: SVGLineJoin,
        miterLimit: CGFloat,
        dashArray: [CGFloat],
        dashPhase: CGFloat,
        in ctx: CGContext
    ) {
        guard paint != .none else { return }

        let effectiveOpacity = gfx.alpha * paintOpacity

        ctx.saveGState()
        ctx.setLineWidth(width)
        ctx.setLineCap(lineCap(cap))
        ctx.setLineJoin(lineJoin(join))
        ctx.setMiterLimit(miterLimit)
        if !dashArray.isEmpty {
            ctx.setLineDash(phase: dashPhase, lengths: dashArray)
        }

        switch paint {
        case .color(let c):
            ctx.setStrokeColor(cgColor(c, opacity: effectiveOpacity))
            ctx.addPath(path)
            ctx.strokePath()
        case .linearGradient(let g):
            guard let strokePath = strokedCopy(path, width: width, cap: cap, join: join, miterLimit: miterLimit) else {
                ctx.restoreGState()
                return
            }
            SVGGradientDrawing.drawLinearTiled(
                g,
                in: ctx,
                clipPath: strokePath,
                paintOpacity: effectiveOpacity,
                evenOdd: false,
                transform: g.transform.matrix.isIdentity ? nil : g.transform.matrix
            )
        case .radialGradient(let g):
            guard let strokePath = strokedCopy(path, width: width, cap: cap, join: join, miterLimit: miterLimit) else {
                ctx.restoreGState()
                return
            }
            SVGGradientDrawing.drawRadialTiled(
                g,
                in: ctx,
                clipPath: strokePath,
                paintOpacity: effectiveOpacity,
                evenOdd: false,
                transform: g.transform.matrix.isIdentity ? nil : g.transform.matrix
            )
        case .none, .paintServer, .pattern:
            break
        }

        ctx.restoreGState()
    }

    private func strokedCopy(
        _ path: CGPath,
        width: CGFloat,
        cap: SVGLineCap,
        join: SVGLineJoin,
        miterLimit: CGFloat
    ) -> CGPath? {
        path.copy(
            strokingWithWidth: width,
            lineCap: lineCap(cap),
            lineJoin: lineJoin(join),
            miterLimit: miterLimit
        )
    }

    private func cgColor(_ c: SVGColor, opacity: CGFloat) -> CGColor {
        CGColor(
            srgbRed: c.red,
            green: c.green,
            blue: c.blue,
            alpha: c.alpha * opacity
        )
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

    // MARK: - Mask

    private func renderMaskImage(
        _ maskCommands: [SVGRenderCommand],
        region: CGRect?,
        in ctx: CGContext
    ) -> CGImage? {
        let clipRect = region ?? ctx.boundingBoxOfClipPath
        guard !clipRect.isNull, clipRect.width > 0, clipRect.height > 0 else { return nil }

        let w = Int(ceil(clipRect.width))
        let h = Int(ceil(clipRect.height))
        guard w > 0, h > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let maskCtx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        maskCtx.translateBy(x: -clipRect.minX, y: -clipRect.minY)
        maskCtx.setFillColor(gray: 0, alpha: 1)
        maskCtx.fill(clipRect)
        var maskGfx = GfxState()
        execute(maskCommands, in: maskCtx, gfx: &maskGfx)

        return maskCtx.makeImage()
    }

    // MARK: - Patterns

    private func tilePattern(
        _ pattern: SVGResolvedPattern,
        tileCommands: [SVGRenderCommand],
        clipBounds: CGRect,
        gfx: inout GfxState,
        in ctx: CGContext
    ) {
        let step = pattern.step
        guard step.width > 0, step.height > 0 else { return }

        let tileClip = CGRect(x: 0, y: 0, width: step.width, height: step.height)

        if pattern.tileLocalContent {
            let inv = pattern.patternToUser.matrix.inverted()
            let localBounds = clipBounds.applying(inv)
            let startI = Int(floor((localBounds.minX - pattern.x) / step.width)) - 1
            let endI = Int(ceil((localBounds.maxX - pattern.x) / step.width)) + 1
            let startJ = Int(floor((localBounds.minY - pattern.y) / step.height)) - 1
            let endJ = Int(ceil((localBounds.maxY - pattern.y) / step.height)) + 1

            for j in startJ...endJ {
                for i in startI...endI {
                    ctx.saveGState()
                    ctx.concatenate(pattern.patternToUser.matrix)
                    ctx.concatenate(CGAffineTransform(
                        translationX: pattern.x + CGFloat(i) * step.width,
                        y: pattern.y + CGFloat(j) * step.height
                    ))
                    ctx.clip(to: tileClip)
                    execute(tileCommands, in: ctx, gfx: &gfx)
                    ctx.restoreGState()
                }
            }
            return
        }

        let inv = pattern.patternToUser.matrix.inverted()
        let localBounds = clipBounds.applying(inv)
        let startI = Int(floor((localBounds.minX - pattern.x) / step.width)) - 1
        let endI = Int(ceil((localBounds.maxX - pattern.x) / step.width)) + 1
        let startJ = Int(floor((localBounds.minY - pattern.y) / step.height)) - 1
        let endJ = Int(ceil((localBounds.maxY - pattern.y) / step.height)) + 1

        for j in startJ...endJ {
            for i in startI...endI {
                ctx.saveGState()
                ctx.concatenate(pattern.patternToUser.matrix)
                ctx.concatenate(CGAffineTransform(
                    translationX: pattern.x + CGFloat(i) * step.width,
                    y: pattern.y + CGFloat(j) * step.height
                ))
                ctx.concatenate(pattern.contentMatrix.matrix)
                execute(tileCommands, in: ctx, gfx: &gfx)
                ctx.restoreGState()
            }
        }
    }
}

#endif
