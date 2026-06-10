import CoreGraphics
import CoreText
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
                context.stroke(Path(cgPath), with: shading, style: style)

            case .drawText(let string, let origin, let font, let fill, let fillOp, let stroke, let strokeOp, let strokeWidth):
                drawText(
                    string: string,
                    origin: origin,
                    font: font,
                    fill: fill,
                    fillOpacity: fillOp,
                    stroke: stroke,
                    strokeOpacity: strokeOp,
                    strokeWidth: strokeWidth,
                    in: &context
                )
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

    // MARK: - Text

    private func drawText(
        string: String,
        origin: CGPoint,
        font: SVGFont,
        fill: SVGPaint,
        fillOpacity: CGFloat,
        stroke: SVGPaint,
        strokeOpacity: CGFloat,
        strokeWidth: CGFloat,
        in context: inout GraphicsContext
    ) {
        let ctFont = TextFontResolver.font(for: font)

        // Width is independent of color, measure once from a plain font-only line.
        let measureLine = TextFontResolver.line(
            string: string, font: ctFont, foreground: nil
        )
        let typographicWidth = CTLineGetTypographicBounds(measureLine, nil, nil, nil)

        let anchoredX: CGFloat = {
            switch font.anchor {
            case .start: return origin.x
            case .middle: return origin.x - CGFloat(typographicWidth) / 2
            case .end: return origin.x - CGFloat(typographicWidth)
            }
        }()

        let fillColor = cgColor(for: fill, opacity: fillOpacity)
        let strokeColor = cgColor(for: stroke, opacity: strokeOpacity)
        let fillVisible = !isNone(fill) && fillColor.alpha > 0
        let strokeVisible = !isNone(stroke) && strokeColor.alpha > 0 && strokeWidth > 0

        guard fillVisible || strokeVisible else { return }

        context.drawLayer { layer in
            layer.translateBy(x: anchoredX, y: origin.y)
            // Flip the Y axis so CoreText's baseline-up convention draws into
            // SwiftUI's Y-down space. After this, baseline sits on y = 0.
            layer.scaleBy(x: 1, y: -1)

            layer.withCGContext { cg in
                cg.textMatrix = .identity
                cg.textPosition = .zero

                if fillVisible {
                    let line = TextFontResolver.line(
                        string: string, font: ctFont, foreground: fillColor
                    )
                    cg.setTextDrawingMode(.fill)
                    CTLineDraw(line, cg)
                }
                if strokeVisible {
                    cg.textPosition = .zero
                    cg.setTextDrawingMode(.stroke)
                    cg.setStrokeColor(strokeColor)
                    cg.setLineWidth(strokeWidth)
                    // Stroked glyphs use the CG stroke color, not the
                    // attributed-string foreground.
                    CTLineDraw(measureLine, cg)
                }
            }
        }
    }

    private func isNone(_ paint: SVGPaint) -> Bool {
        if case .none = paint { return true }
        return false
    }

    private func cgColor(for paint: SVGPaint, opacity: CGFloat) -> CGColor {
        switch paint {
        case .none:
            return CGColor(red: 0, green: 0, blue: 0, alpha: 0)
        case .color(let c):
            return CGColor(
                red: c.red, green: c.green, blue: c.blue,
                alpha: c.alpha * opacity
            )
        }
    }
}

/// Resolves an `SVGFont` to a `CTFont`. Caches by (family, size, weight)
/// because the renderer is invoked many times per render and font lookup is
/// surprisingly expensive on macOS.
private enum TextFontResolver {

    private struct Key: Hashable {
        let family: String?
        let size: CGFloat
        let weight: SVGFontWeight
    }

    private static let cache = Cache()

    static func font(for font: SVGFont) -> CTFont {
        cache.font(for: Key(family: font.family, size: font.size, weight: font.weight))
    }

    static func line(string: String, font: CTFont, foreground: CGColor?) -> CTLine {
        var attrs: [NSAttributedString.Key: Any] = [.font: font]
        if let foreground {
            attrs[kCTForegroundColorAttributeName as NSAttributedString.Key] = foreground
        }
        let attributed = NSAttributedString(string: string, attributes: attrs)
        return CTLineCreateWithAttributedString(attributed)
    }

    private final class Cache: @unchecked Sendable {
        private var storage: [Key: CTFont] = [:]
        private let lock = NSLock()

        func font(for key: Key) -> CTFont {
            lock.lock(); defer { lock.unlock() }
            if let cached = storage[key] { return cached }
            let resolved = makeFont(family: key.family, size: key.size, weight: key.weight)
            storage[key] = resolved
            return resolved
        }

        private func makeFont(family: String?, size: CGFloat, weight: SVGFontWeight) -> CTFont {
            let descriptor = descriptor(for: family, weight: weight)
            return CTFontCreateWithFontDescriptor(descriptor, size, nil)
        }

        private func descriptor(for family: String?, weight: SVGFontWeight) -> CTFontDescriptor {
            let traits: [CFString: Any] = [
                kCTFontWeightTrait: weightValue(for: weight)
            ]
            var attributes: [CFString: Any] = [
                kCTFontTraitsAttribute: traits as CFDictionary
            ]
            for name in candidateFamilyNames(from: family) {
                attributes[kCTFontFamilyNameAttribute] = name
                let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
                let matched = CTFontDescriptorCreateMatchingFontDescriptor(descriptor, nil)
                if matched != nil {
                    return matched!
                }
            }
            // Final fallback: just the traits, let the system pick a default sans.
            attributes.removeValue(forKey: kCTFontFamilyNameAttribute)
            return CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        }

        /// Split a CSS-style font-family list and substitute generics with
        /// system fonts that actually exist (`SVGFreeSansASCII` is the W3C's
        /// embedded font and is not installed; fall back to Helvetica).
        private func candidateFamilyNames(from raw: String?) -> [String] {
            guard let raw, !raw.isEmpty else { return ["Helvetica"] }
            var result: [String] = []
            for token in raw.split(separator: ",") {
                let name = String(token)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                guard !name.isEmpty else { continue }
                switch name.lowercased() {
                case "sans-serif": result.append("Helvetica")
                case "serif": result.append("Times")
                case "monospace": result.append("Menlo")
                case "cursive": result.append("Apple Chancery")
                case "fantasy": result.append("Papyrus")
                default: result.append(name)
                }
            }
            if result.isEmpty { result.append("Helvetica") }
            // Always end with a guaranteed-available fallback.
            if !result.contains("Helvetica") { result.append("Helvetica") }
            return result
        }

        private func weightValue(for weight: SVGFontWeight) -> CGFloat {
            switch weight {
            case .normal: return 0
            case .bold: return 0.4
            case .numeric(let n):
                // Map CSS weight 100…900 onto CT's -1…1 range with 400 → 0.
                let clamped = max(100, min(900, n))
                return CGFloat(clamped - 400) / 500.0
            }
        }
    }
}

#endif
