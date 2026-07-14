import CoreGraphics
import SVGCore

/// Core Graphics gradient construction for snapshot rendering.
/// Stop-color and stop-opacity are interpolated independently in sRGB, matching
/// W3C reference PNGs. (SVG 1.1 specifies linearRGB; the test-suite references
/// were produced with sRGB interpolation.)
enum SVGGradientDrawing {

    private static let gradientRGB: CGColorSpace = {
        if let srgb = CGColorSpace(name: CGColorSpace.sRGB) {
            return srgb
        }
        return CGColorSpaceCreateDeviceRGB()
    }()

    static func makeGradient(
        stops: [SVGGradientStop],
        paintOpacity: CGFloat,
        colorInterpolation: SVGColorInterpolation = .sRGB
    ) -> CGGradient? {
        let effectiveStops = resolvedStops(stops, colorInterpolation: colorInterpolation)
        guard !effectiveStops.isEmpty else { return nil }

        var colors: [CGColor] = []
        var locations: [CGFloat] = []
        colors.reserveCapacity(effectiveStops.count)
        locations.reserveCapacity(effectiveStops.count)

        for stop in effectiveStops {
            let a = stop.color.alpha * paintOpacity
            guard let color = CGColor(
                colorSpace: gradientRGB,
                components: [stop.color.red, stop.color.green, stop.color.blue, a]
            ) else {
                return nil
            }
            colors.append(color)
            locations.append(stop.offset)
        }

        return CGGradient(
            colorsSpace: gradientRGB,
            colors: colors as CFArray,
            locations: locations
        )
    }

    /// Resolve gradient stops for rendering, including opacity and color-space densification.
    static func resolvedStops(
        _ stops: [SVGGradientStop],
        colorInterpolation: SVGColorInterpolation
    ) -> [SVGGradientStop] {
        // Preserve document order at equal offsets (SVG: last stop controls overlap point).
        let sorted = stops.enumerated().sorted { lhs, rhs in
            if lhs.element.offset != rhs.element.offset {
                return lhs.element.offset < rhs.element.offset
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
        guard !sorted.isEmpty else { return [] }

        var effectiveStops = sorted
        if needsIndependentOpacityInterpolation(sorted) {
            effectiveStops = densifyStopsIndependentOpacity(sorted, stepsPerSegment: 32)
        }
        switch colorInterpolation {
        case .sRGB:
            break
        case .linearRGB:
            effectiveStops = densifyStopsLinearRGB(effectiveStops, stepsPerSegment: 32)
        }
        return effectiveStops
    }

    static func drawLinear(
        _ gradient: SVGLinearGradient,
        in ctx: CGContext,
        clipPath: CGPath,
        paintOpacity: CGFloat,
        evenOdd: Bool,
        transform: CGAffineTransform?
    ) {
        guard let cgGradient = makeGradient(
            stops: gradient.stops,
            paintOpacity: paintOpacity,
            colorInterpolation: gradient.colorInterpolation
        ) else {
            return
        }

        ctx.saveGState()
        if let transform {
            ctx.concatenate(transform)
            ctx.addPath(transformedPath(clipPath, by: transform.inverted()))
        } else {
            ctx.addPath(clipPath)
        }
        ctx.clip(using: evenOdd ? .evenOdd : .winding)

        let start = CGPoint(x: gradient.x1, y: gradient.y1)
        let end = CGPoint(x: gradient.x2, y: gradient.y2)
        ctx.drawLinearGradient(
            cgGradient,
            start: start,
            end: end,
            options: drawOptions(for: gradient.spreadMethod, start: start, end: end, in: ctx)
        )
        ctx.restoreGState()
    }

    static func drawRadial(
        _ gradient: SVGRadialGradient,
        in ctx: CGContext,
        clipPath: CGPath,
        paintOpacity: CGFloat,
        evenOdd: Bool,
        transform: CGAffineTransform?
    ) {
        guard let cgGradient = makeGradient(
            stops: gradient.stops,
            paintOpacity: paintOpacity,
            colorInterpolation: gradient.colorInterpolation
        ) else {
            return
        }

        ctx.saveGState()
        if let transform {
            ctx.concatenate(transform)
            ctx.addPath(transformedPath(clipPath, by: transform.inverted()))
        } else {
            ctx.addPath(clipPath)
        }
        ctx.clip(using: evenOdd ? .evenOdd : .winding)

        let focal = clampedFocal(
            cx: gradient.cx, cy: gradient.cy,
            fx: gradient.fx, fy: gradient.fy,
            r: gradient.r
        )
        let center = CGPoint(x: gradient.cx, y: gradient.cy)
        let radius = gradient.r
        ctx.drawRadialGradient(
            cgGradient,
            startCenter: focal,
            startRadius: 0,
            endCenter: center,
            endRadius: radius,
            options: drawOptions(for: gradient.spreadMethod, start: focal, end: CGPoint(x: center.x + radius, y: center.y), in: ctx)
        )
        ctx.restoreGState()
    }

    /// Pad extends the end stops; repeat/reflect need the gradient segment tiled in
    /// gradient space. Expand stops across the clip bounds projected onto the axis.
    static func drawLinearTiled(
        _ gradient: SVGLinearGradient,
        in ctx: CGContext,
        clipPath: CGPath,
        paintOpacity: CGFloat,
        evenOdd: Bool,
        transform: CGAffineTransform?
    ) {
        guard gradient.spreadMethod != .pad else {
            drawLinear(gradient, in: ctx, clipPath: clipPath, paintOpacity: paintOpacity, evenOdd: evenOdd, transform: transform)
            return
        }

        let axis = gradientAxis(gradient)
        let bounds = clipPath.boundingBoxOfPath
        guard axis.length > 0, !bounds.isNull else {
            drawLinear(gradient, in: ctx, clipPath: clipPath, paintOpacity: paintOpacity, evenOdd: evenOdd, transform: transform)
            return
        }

        let gradientCorners = corners(of: bounds, inverseTransform: transform)
        let ts = gradientCorners.map { project($0, onto: axis) / axis.length }
        let minT = ts.min() ?? 0
        let maxT = ts.max() ?? 1

        let expanded = expandedStops(
            stops: gradient.stops,
            spread: gradient.spreadMethod,
            minT: minT,
            maxT: maxT
        )
        guard expanded.baseSpan > 0 else {
            drawLinear(gradient, in: ctx, clipPath: clipPath, paintOpacity: paintOpacity, evenOdd: evenOdd, transform: transform)
            return
        }

        var mapped = gradient
        mapped.stops = normalize(expanded)
        mapped.spreadMethod = .pad

        let scale = axis.length
        let span = expanded.baseSpan
        mapped.x1 = axis.origin.x + expanded.baseOffset * scale * axis.dx
        mapped.y1 = axis.origin.y + expanded.baseOffset * scale * axis.dy
        mapped.x2 = axis.origin.x + (expanded.baseOffset + span) * scale * axis.dx
        mapped.y2 = axis.origin.y + (expanded.baseOffset + span) * scale * axis.dy

        drawLinear(mapped, in: ctx, clipPath: clipPath, paintOpacity: paintOpacity, evenOdd: evenOdd, transform: transform)
    }

    static func drawRadialTiled(
        _ gradient: SVGRadialGradient,
        in ctx: CGContext,
        clipPath: CGPath,
        paintOpacity: CGFloat,
        evenOdd: Bool,
        transform: CGAffineTransform?
    ) {
        guard gradient.spreadMethod != .pad, gradient.r > 0 else {
            drawRadial(gradient, in: ctx, clipPath: clipPath, paintOpacity: paintOpacity, evenOdd: evenOdd, transform: transform)
            return
        }

        let bounds = clipPath.boundingBoxOfPath
        guard !bounds.isNull else {
            drawRadial(gradient, in: ctx, clipPath: clipPath, paintOpacity: paintOpacity, evenOdd: evenOdd, transform: transform)
            return
        }

        let center = CGPoint(x: gradient.cx, y: gradient.cy)
        let gradientCorners = corners(of: bounds, inverseTransform: transform)
        // The shape includes the focal/center point at t = 0; corner distances alone
        // can omit the innermost band (pservers-grad-14-b radial reflect).
        var samplePoints = gradientCorners
        samplePoints.append(center)
        let maxDist = samplePoints.map { hypot($0.x - center.x, $0.y - center.y) }.max() ?? gradient.r
        let minT: CGFloat = 0
        let maxT = maxDist / gradient.r

        let expanded = expandedStops(
            stops: gradient.stops,
            spread: gradient.spreadMethod,
            minT: minT,
            maxT: maxT
        )
        guard expanded.baseSpan > 0 else {
            drawRadial(gradient, in: ctx, clipPath: clipPath, paintOpacity: paintOpacity, evenOdd: evenOdd, transform: transform)
            return
        }

        var tiled = gradient
        tiled.stops = normalize(expanded)
        tiled.spreadMethod = .pad
        tiled.r = gradient.r * expanded.baseSpan

        drawRadial(tiled, in: ctx, clipPath: clipPath, paintOpacity: paintOpacity, evenOdd: evenOdd, transform: transform)
    }

    // MARK: - Internals

    private struct Axis {
        var origin: CGPoint
        var dx: CGFloat
        var dy: CGFloat
        var length: CGFloat
    }

    private struct ExpandedStops {
        var stops: [SVGGradientStop]
        var baseOffset: CGFloat
        var baseSpan: CGFloat
    }

    private static func transformedPath(_ path: CGPath, by transform: CGAffineTransform) -> CGPath {
        var t = transform
        return path.copy(using: &t) ?? path
    }

    private static func corners(of bounds: CGRect, inverseTransform: CGAffineTransform?) -> [CGPoint] {
        let points = [
            CGPoint(x: bounds.minX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.minX, y: bounds.maxY),
            CGPoint(x: bounds.maxX, y: bounds.maxY),
        ]
        guard let inverseTransform else { return points }
        let inv = inverseTransform.inverted()
        return points.map { $0.applying(inv) }
    }

    private static func normalize(_ expanded: ExpandedStops) -> [SVGGradientStop] {
        let span = expanded.baseSpan
        guard span > 0 else { return expanded.stops }
        return expanded.stops.map { stop in
            SVGGradientStop(
                offset: (stop.offset - expanded.baseOffset) / span,
                color: stop.color
            )
        }
    }

    private static func gradientAxis(_ g: SVGLinearGradient) -> Axis {
        let dx = g.x2 - g.x1
        let dy = g.y2 - g.y1
        let length = hypot(dx, dy)
        guard length > 0 else {
            return Axis(origin: CGPoint(x: g.x1, y: g.y1), dx: 0, dy: 0, length: 0)
        }
        return Axis(origin: CGPoint(x: g.x1, y: g.y1), dx: dx / length, dy: dy / length, length: length)
    }

    private static func project(_ point: CGPoint, onto axis: Axis) -> CGFloat {
        let px = point.x - axis.origin.x
        let py = point.y - axis.origin.y
        return px * axis.dx + py * axis.dy
    }

    private static func drawOptions(
        for spread: SVGGradientSpread,
        start: CGPoint,
        end: CGPoint,
        in ctx: CGContext
    ) -> CGGradientDrawingOptions {
        switch spread {
        case .pad:
            // Extend the last stop color outward (required for userSpace radial
            // gradients smaller than the fill rect, e.g. pservers-grad-02-b).
            return [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        case .repeat, .reflect:
            // Tiled draws remap the 0…1 segment; pad extension is unused.
            return []
        }
    }

    private static let stopEpsilon: CGFloat = 0.000_1

    /// SVG 1.1: clamp focal to the circle perimeter when outside `(cx, cy, r)`.
    private static func clampedFocal(
        cx: CGFloat, cy: CGFloat, fx: CGFloat, fy: CGFloat, r: CGFloat
    ) -> CGPoint {
        let dx = fx - cx, dy = fy - cy
        let dist = hypot(dx, dy)
        guard dist > r, dist > 0, r > 0 else { return CGPoint(x: fx, y: fy) }
        let s = r / dist
        return CGPoint(x: cx + dx * s, y: cy + dy * s)
    }

    private static func needsIndependentOpacityInterpolation(_ stops: [SVGGradientStop]) -> Bool {
        stops.contains { $0.color.alpha < 1 - stopEpsilon }
    }

    /// Sample stop-color and stop-opacity independently along each segment.
    private static func densifyStopsIndependentOpacity(
        _ stops: [SVGGradientStop],
        stepsPerSegment: Int
    ) -> [SVGGradientStop] {
        guard stops.count >= 2, stepsPerSegment > 1 else { return stops }
        var result: [SVGGradientStop] = []
        result.reserveCapacity((stops.count - 1) * stepsPerSegment + 1)
        for index in 0..<(stops.count - 1) {
            let start = stops[index]
            let end = stops[index + 1]
            if index == 0 { result.append(start) }
            for step in 1..<stepsPerSegment {
                let fraction = CGFloat(step) / CGFloat(stepsPerSegment)
                let offset = start.offset + (end.offset - start.offset) * fraction
                result.append(
                    SVGGradientStop(
                        offset: offset,
                        color: SVGColor(
                            red: start.color.red + (end.color.red - start.color.red) * fraction,
                            green: start.color.green + (end.color.green - start.color.green) * fraction,
                            blue: start.color.blue + (end.color.blue - start.color.blue) * fraction,
                            alpha: start.color.alpha + (end.color.alpha - start.color.alpha) * fraction
                        )
                    )
                )
            }
            result.append(end)
        }
        return result
    }

    private static func srgbToLinear(_ channel: CGFloat) -> CGFloat {
        if channel <= 0.04045 { return channel / 12.92 }
        return pow((channel + 0.055) / 1.055, 2.4)
    }

    private static func linearToSrgb(_ channel: CGFloat) -> CGFloat {
        if channel <= 0.0031308 { return 12.92 * channel }
        return 1.055 * pow(channel, 1.0 / 2.4) - 0.055
    }

    private static func interpolateColorLinearRGB(_ a: SVGColor, _ b: SVGColor, t: CGFloat) -> SVGColor {
        func channel(_ va: CGFloat, _ vb: CGFloat) -> CGFloat {
            let linear = srgbToLinear(va) * (1 - t) + srgbToLinear(vb) * t
            return linearToSrgb(linear)
        }
        return SVGColor(
            red: channel(a.red, b.red),
            green: channel(a.green, b.green),
            blue: channel(a.blue, b.blue),
            alpha: a.alpha * (1 - t) + b.alpha * t
        )
    }

    private static func densifyStopsLinearRGB(
        _ stops: [SVGGradientStop],
        stepsPerSegment: Int
    ) -> [SVGGradientStop] {
        guard stops.count >= 2, stepsPerSegment > 1 else { return stops }
        var result: [SVGGradientStop] = []
        result.reserveCapacity((stops.count - 1) * stepsPerSegment + 1)
        for index in 0..<(stops.count - 1) {
            let start = stops[index]
            let end = stops[index + 1]
            if index == 0 { result.append(start) }
            for step in 1..<stepsPerSegment {
                let fraction = CGFloat(step) / CGFloat(stepsPerSegment)
                let offset = start.offset + (end.offset - start.offset) * fraction
                result.append(
                    SVGGradientStop(
                        offset: offset,
                        color: interpolateColorLinearRGB(start.color, end.color, t: fraction)
                    )
                )
            }
            result.append(end)
        }
        return result
    }

    private static func expandedStops(
        stops: [SVGGradientStop],
        spread: SVGGradientSpread,
        minT: CGFloat,
        maxT: CGFloat
    ) -> ExpandedStops {
        let sorted = stops.sorted { $0.offset < $1.offset }
        guard !sorted.isEmpty else {
            return ExpandedStops(stops: [], baseOffset: 0, baseSpan: 1)
        }

        let startPeriod = Int(floor(minT))
        let endPeriod = Int(ceil(maxT))
        var out: [SVGGradientStop] = []

        for period in startPeriod...endPeriod {
            let reversed = spread == .reflect && (period % 2 != 0)
            let segment = reversed ? sorted.reversed() : sorted
            for stop in segment {
                let local = reversed ? (1 - stop.offset) : stop.offset
                let global = CGFloat(period) + local
                if let last = out.last, abs(last.offset - global) < stopEpsilon {
                    // Repeat tiles meet lime→blue at period boundaries; keep both
                    // colors at a micro-step (CGGradient cannot discontinuity-jump).
                    if spread == .repeat && last.color != stop.color {
                        out.append(
                            SVGGradientStop(offset: global + stopEpsilon, color: stop.color)
                        )
                    } else {
                        out[out.count - 1] = SVGGradientStop(offset: global, color: stop.color)
                    }
                } else {
                    out.append(SVGGradientStop(offset: global, color: stop.color))
                }
            }
        }

        let baseOffset = CGFloat(startPeriod)
        let baseSpan = CGFloat(endPeriod - startPeriod + 1)
        return ExpandedStops(stops: out, baseOffset: baseOffset, baseSpan: baseSpan)
    }
}
