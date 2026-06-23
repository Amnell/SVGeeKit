import CoreGraphics
import Foundation
import SVGCore

/// Dispatches text layout to SVG fonts when available, otherwise CoreText.
enum TextLayout {

    static func glyphPath(
        string: String,
        font: SVGFont,
        origin: CGPoint,
        fontFaces: [SVGFontFace],
        fonts: [String: SVGFontDefinition]
    ) -> CGPath? {
        if let definition = resolveSVGFont(family: font.family, fontFaces: fontFaces, fonts: fonts) {
            return SVGFontTextLayout.glyphPath(
                string: string,
                font: font,
                origin: origin,
                definition: definition
            )
        }
        return SystemTextLayout.glyphPath(string: string, font: font, origin: origin)
    }

    private static func resolveSVGFont(
        family: String?,
        fontFaces: [SVGFontFace],
        fonts: [String: SVGFontDefinition]
    ) -> SVGFontDefinition? {
        for name in familyNames(from: family) {
            for face in fontFaces where face.family.caseInsensitiveCompare(name) == .orderedSame {
                if let def = fonts[face.fontID] { return def }
            }
        }
        return nil
    }

    private static func familyNames(from raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        return raw.split(separator: ",").map {
            String($0)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        }.filter { !$0.isEmpty }
    }
}

enum SVGFontTextLayout {

    static func glyphPath(
        string: String,
        font: SVGFont,
        origin: CGPoint,
        definition: SVGFontDefinition
    ) -> CGPath? {
        guard definition.unitsPerEm > 0 else { return nil }
        let scale = font.size / definition.unitsPerEm
        let fallback = definition.missingGlyph
            ?? SVGGlyph(commands: nil, advance: definition.defaultAdvance)

        var penX: CGFloat = 0
        var typographicWidth: CGFloat = 0
        var placements: [(glyph: SVGGlyph, x: CGFloat)] = []

        for scalar in string.unicodeScalars {
            let glyph = definition.glyphs[scalar] ?? fallback
            placements.append((glyph, penX))
            let advance = glyph.advance * scale
            penX += advance
            typographicWidth += advance
        }

        let anchoredX: CGFloat = {
            switch font.anchor {
            case .start: return origin.x
            case .middle: return origin.x - typographicWidth / 2
            case .end: return origin.x - typographicWidth
            }
        }()

        let result = CGMutablePath()
        for item in placements {
            guard let commands = item.glyph.commands, !commands.isEmpty else { continue }
            let glyphPath = commands.makeCGPath()
            let transform = CGAffineTransform(translationX: anchoredX + item.x, y: origin.y)
                .scaledBy(x: scale, y: -scale)
            result.addPath(glyphPath, transform: transform)
        }

        return result.isEmpty ? nil : result
    }
}
