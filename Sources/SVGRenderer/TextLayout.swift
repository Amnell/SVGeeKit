import CoreGraphics
import Foundation
import SVGCore

/// Dispatches text layout to SVG fonts when available, otherwise CoreText.
enum TextLayout {

    /// Lays out all runs in a `<text>` element, applying `text-anchor` once for
    /// the whole string.
    static func glyphPath(
        text: SVGText,
        fontFaces: [SVGFontFace],
        fonts: [String: SVGFontDefinition]
    ) -> CGPath? {
        guard !text.runs.isEmpty else { return nil }

        var placements: [(run: SVGTextRun, origin: CGPoint)] = []
        var penX = text.origin.x
        var penY = text.origin.y
        var totalWidth: CGFloat = 0

        for run in text.runs {
            penX += run.dx
            penY += run.dy
            let origin = CGPoint(x: penX, y: penY)
            placements.append((run, origin))
            let width = typographicWidth(
                string: run.string,
                font: run.font,
                fontFaces: fontFaces,
                fonts: fonts
            )
            totalWidth = penX + width - text.origin.x
            penX += width
        }

        let anchorShift = anchorOffset(anchor: text.font.anchor, width: totalWidth)
        let result = CGMutablePath()

        for item in placements {
            guard !item.run.string.isEmpty else { continue }
            let origin = CGPoint(x: item.origin.x + anchorShift, y: item.origin.y)
            guard let path = glyphPathUnanchored(
                string: item.run.string,
                font: item.run.font,
                origin: origin,
                fontFaces: fontFaces,
                fonts: fonts
            ) else { continue }
            result.addPath(path)
        }

        return result.isEmpty ? nil : result
    }

    static func glyphPath(
        string: String,
        font: SVGFont,
        origin: CGPoint,
        fontFaces: [SVGFontFace],
        fonts: [String: SVGFontDefinition]
    ) -> CGPath? {
        let width = typographicWidth(string: string, font: font, fontFaces: fontFaces, fonts: fonts)
        let shift = anchorOffset(anchor: font.anchor, width: width)
        let anchored = CGPoint(x: origin.x + shift, y: origin.y)
        return glyphPathUnanchored(
            string: string,
            font: font,
            origin: anchored,
            fontFaces: fontFaces,
            fonts: fonts
        )
    }

    static func typographicWidth(
        string: String,
        font: SVGFont,
        fontFaces: [SVGFontFace],
        fonts: [String: SVGFontDefinition]
    ) -> CGFloat {
        if let definition = resolveSVGFont(family: font.family, fontFaces: fontFaces, fonts: fonts) {
            return SVGFontTextLayout.typographicWidth(string: string, font: font, definition: definition)
        }
        return SystemTextLayout.typographicWidth(string: string, font: font)
    }

    private static func glyphPathUnanchored(
        string: String,
        font: SVGFont,
        origin: CGPoint,
        fontFaces: [SVGFontFace],
        fonts: [String: SVGFontDefinition]
    ) -> CGPath? {
        if let definition = resolveSVGFont(family: font.family, fontFaces: fontFaces, fonts: fonts) {
            return SVGFontTextLayout.glyphPathUnanchored(
                string: string,
                font: font,
                origin: origin,
                definition: definition
            )
        }
        return SystemTextLayout.glyphPathUnanchored(string: string, font: font, origin: origin)
    }

    private static func anchorOffset(anchor: SVGTextAnchor, width: CGFloat) -> CGFloat {
        switch anchor {
        case .start: return 0
        case .middle: return -width / 2
        case .end: return -width
        }
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

    static func typographicWidth(
        string: String,
        font: SVGFont,
        definition: SVGFontDefinition
    ) -> CGFloat {
        guard definition.unitsPerEm > 0 else { return 0 }
        let scale = font.size / definition.unitsPerEm
        let fallback = definition.missingGlyph
            ?? SVGGlyph(commands: nil, advance: definition.defaultAdvance)
        var width: CGFloat = 0
        for scalar in string.unicodeScalars {
            let glyph = definition.glyphs[scalar] ?? fallback
            width += glyph.advance * scale
        }
        return width
    }

    static func glyphPathUnanchored(
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
        var placements: [(glyph: SVGGlyph, x: CGFloat)] = []

        for scalar in string.unicodeScalars {
            let glyph = definition.glyphs[scalar] ?? fallback
            placements.append((glyph, penX))
            penX += glyph.advance * scale
        }

        let result = CGMutablePath()
        for item in placements {
            guard let commands = item.glyph.commands, !commands.isEmpty else { continue }
            let glyphPath = commands.makeCGPath()
            let transform = CGAffineTransform(translationX: origin.x + item.x, y: origin.y)
                .scaledBy(x: scale, y: -scale)
            result.addPath(glyphPath, transform: transform)
        }

        return result.isEmpty ? nil : result
    }

    static func glyphPath(
        string: String,
        font: SVGFont,
        origin: CGPoint,
        definition: SVGFontDefinition
    ) -> CGPath? {
        let width = typographicWidth(string: string, font: font, definition: definition)
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
            origin: CGPoint(x: origin.x + shift, y: origin.y),
            definition: definition
        )
    }
}
