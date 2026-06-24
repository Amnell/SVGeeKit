import CoreGraphics
import CoreText
import Foundation
import SVGCore

/// Builds glyph outline paths for system-font text using CoreText.
enum SystemTextLayout {

    /// Combined fill/stroke outline for `string` in SVG user space (y-down).
    /// `origin.y` is the alphabetic baseline; `font.anchor` adjusts horizontal
    /// placement.
    static func glyphPath(string: String, font: SVGFont, origin: CGPoint) -> CGPath? {
        let width = typographicWidth(string: string, font: font)
        let shift: CGFloat = {
            switch font.anchor {
            case .start: return 0
            case .middle: return -width / 2
            case .end: return -width
            }
        }()
        return glyphPathUnanchored(
            string: string,
            font: font,
            origin: CGPoint(x: origin.x + shift, y: origin.y)
        )
    }

    static func typographicWidth(string: String, font: SVGFont) -> CGFloat {
        let ctFont = SystemFontResolver.font(for: font)
        let attributed = NSAttributedString(
            string: string,
            attributes: [kCTFontAttributeName as NSAttributedString.Key: ctFont]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    static func charAdvance(string: String, font: SVGFont) -> CGFloat {
        guard let char = string.first else { return 0 }
        let ctFont = SystemFontResolver.font(for: font)
        var glyph = CGGlyph(0)
        let scalar = String(char)
        guard CTFontGetGlyphsForCharacters(ctFont, Array(scalar.utf16), &glyph, 1) else {
            return 0
        }
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(ctFont, .default, [glyph], &advance, 1)
        return advance.width
    }

    static func glyphPathUnanchored(
        string: String,
        font: SVGFont,
        origin: CGPoint,
        rotations: [CGFloat]? = nil
    ) -> CGPath? {
        let ctFont = SystemFontResolver.font(for: font)
        let attributed = NSAttributedString(
            string: string,
            attributes: [kCTFontAttributeName as NSAttributedString.Key: ctFont]
        )
        let line = CTLineCreateWithAttributedString(attributed)

        let result = CGMutablePath()
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        for run in runs {
            let glyphCount = CTRunGetGlyphCount(run)
            guard glyphCount > 0 else { continue }

            var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
            var positions = [CGPoint](repeating: .zero, count: glyphCount)
            CTRunGetGlyphs(run, CFRange(location: 0, length: glyphCount), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: glyphCount), &positions)

            for i in 0..<glyphCount {
                guard let glyphPath = CTFontCreatePathForGlyph(ctFont, glyphs[i], nil) else {
                    continue
                }
                let angle = rotations.flatMap { $0.indices.contains(i) ? $0[i] : nil } ?? 0
                let transform = textGlyphTransform(
                    at: CGPoint(x: origin.x + positions[i].x, y: origin.y),
                    rotationDegrees: angle,
                    scaleX: 1,
                    scaleY: -1
                )
                result.addPath(glyphPath, transform: transform)
            }
        }

        return result.isEmpty ? nil : result
    }

    static func glyphPathAtPositions(
        string: String,
        font: SVGFont,
        positions: [CGPoint],
        rotations: [CGFloat]? = nil
    ) -> CGPath? {
        let ctFont = SystemFontResolver.font(for: font)
        let chars = Array(string)
        guard !chars.isEmpty else { return nil }

        let result = CGMutablePath()
        for (i, char) in chars.enumerated() {
            guard i < positions.count else { break }
            var glyph = CGGlyph(0)
            let scalar = String(char)
            guard CTFontGetGlyphsForCharacters(ctFont, Array(scalar.utf16), &glyph, 1) else {
                continue
            }
            guard let glyphPath = CTFontCreatePathForGlyph(ctFont, glyph, nil) else { continue }
            let pos = positions[i]
            let angle = rotations.flatMap { $0.indices.contains(i) ? $0[i] : nil } ?? 0
            let transform = textGlyphTransform(
                at: pos,
                rotationDegrees: angle,
                scaleX: 1,
                scaleY: -1
            )
            result.addPath(glyphPath, transform: transform)
        }
        return result.isEmpty ? nil : result
    }
}

func textGlyphTransform(
    at position: CGPoint,
    rotationDegrees: CGFloat,
    scaleX: CGFloat = 1,
    scaleY: CGFloat = 1
) -> CGAffineTransform {
    var transform = CGAffineTransform(translationX: position.x, y: position.y)
    if rotationDegrees != 0 {
        transform = transform.rotated(by: rotationDegrees * .pi / 180)
    }
    return transform.scaledBy(x: scaleX, y: scaleY)
}

/// Resolves an `SVGFont` to a `CTFont`. Caches by (family, size, weight)
/// because font lookup is surprisingly expensive on macOS.
private enum SystemFontResolver {

    private struct Key: Hashable {
        let family: String?
        let size: CGFloat
        let weight: SVGFontWeight
        let style: SVGFontStyle
    }

    private static let cache = Cache()

    static func font(for font: SVGFont) -> CTFont {
        cache.font(for: Key(
            family: font.family,
            size: font.size,
            weight: font.weight,
            style: font.style
        ))
    }

    private final class Cache: @unchecked Sendable {
        private var storage: [Key: CTFont] = [:]
        private let lock = NSLock()

        func font(for key: Key) -> CTFont {
            lock.lock()
            defer { lock.unlock() }
            if let cached = storage[key] { return cached }
            let resolved = makeFont(
                family: key.family,
                size: key.size,
                weight: key.weight,
                style: key.style
            )
            storage[key] = resolved
            return resolved
        }

        private func makeFont(
            family: String?,
            size: CGFloat,
            weight: SVGFontWeight,
            style: SVGFontStyle
        ) -> CTFont {
            let descriptor = descriptor(for: family, weight: weight, style: style)
            return CTFontCreateWithFontDescriptor(descriptor, size, nil)
        }

        private func descriptor(
            for family: String?,
            weight: SVGFontWeight,
            style: SVGFontStyle
        ) -> CTFontDescriptor {
            var traits: [CFString: Any] = [
                kCTFontWeightTrait: weightValue(for: weight)
            ]
            if style == .italic || style == .oblique {
                traits[kCTFontSlantTrait] = 1.0
            }
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
            if !result.contains("Helvetica") { result.append("Helvetica") }
            return result
        }

        private func weightValue(for weight: SVGFontWeight) -> CGFloat {
            switch weight {
            case .normal: return 0
            case .bold: return 0.4
            case .numeric(let n):
                let clamped = max(100, min(900, n))
                return CGFloat(clamped - 400) / 500.0
            }
        }
    }
}
