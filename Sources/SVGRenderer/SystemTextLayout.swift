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
        let ctFont = SystemFontResolver.font(for: font)
        let attributed = NSAttributedString(
            string: string,
            attributes: [kCTFontAttributeName as NSAttributedString.Key: ctFont]
        )
        let line = CTLineCreateWithAttributedString(attributed)

        let typographicWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
        let anchoredX: CGFloat = {
            switch font.anchor {
            case .start: return origin.x
            case .middle: return origin.x - CGFloat(typographicWidth) / 2
            case .end: return origin.x - CGFloat(typographicWidth)
            }
        }()

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
                let transform = CGAffineTransform(translationX: anchoredX + positions[i].x, y: origin.y)
                    .scaledBy(x: 1, y: -1)
                result.addPath(glyphPath, transform: transform)
            }
        }

        return result.isEmpty ? nil : result
    }
}

/// Resolves an `SVGFont` to a `CTFont`. Caches by (family, size, weight)
/// because font lookup is surprisingly expensive on macOS.
private enum SystemFontResolver {

    private struct Key: Hashable {
        let family: String?
        let size: CGFloat
        let weight: SVGFontWeight
    }

    private static let cache = Cache()

    static func font(for font: SVGFont) -> CTFont {
        cache.font(for: Key(family: font.family, size: font.size, weight: font.weight))
    }

    private final class Cache: @unchecked Sendable {
        private var storage: [Key: CTFont] = [:]
        private let lock = NSLock()

        func font(for key: Key) -> CTFont {
            lock.lock()
            defer { lock.unlock() }
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
