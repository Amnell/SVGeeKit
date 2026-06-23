import CoreGraphics
import Foundation
import SVGCore

/// Dispatches text layout to SVG fonts when available, otherwise CoreText.
enum TextLayout {

    struct RunSegment {
        var run: SVGTextRun
        var path: CGPath
    }

    static func glyphPath(
        text: SVGText,
        fontFaces: [SVGFontFace],
        fonts: [String: SVGFontDefinition]
    ) -> CGPath? {
        let segments = layoutRuns(text: text, fontFaces: fontFaces, fonts: fonts)
        guard !segments.isEmpty else { return nil }
        let result = CGMutablePath()
        for segment in segments {
            result.addPath(segment.path)
        }
        return result
    }

    static func layoutRuns(
        text: SVGText,
        fontFaces: [SVGFontFace],
        fonts: [String: SVGFontDefinition]
    ) -> [RunSegment] {
        guard !text.runs.isEmpty else { return [] }

        var penX = text.origin.x
        var penY = text.origin.y
        var segments: [RunSegment] = []

        for run in text.runs {
            penX += run.dx
            penY += run.dy
            guard !run.string.isEmpty else { continue }

            let path: CGPath?
            if let xs = run.explicitX {
                let y = run.explicitY ?? penY
                let positions = explicitPositions(string: run.string, xs: xs, y: y)
                path = glyphPathAtPositions(
                    string: run.string,
                    font: run.font,
                    positions: positions,
                    rotations: run.rotations,
                    fontFaces: fontFaces,
                    fonts: fonts
                )
                if let last = positions.last {
                    let lastWidth = typographicWidth(
                        of: run.string.last.map(String.init) ?? "",
                        font: run.font,
                        fontFaces: fontFaces,
                        fonts: fonts
                    )
                    penX = last.x + lastWidth
                }
                penY = y
            } else {
                let origin = CGPoint(x: penX, y: penY)
                path = glyphPathUnanchored(
                    string: run.string,
                    font: run.font,
                    origin: origin,
                    rotations: run.rotations,
                    fontFaces: fontFaces,
                    fonts: fonts
                )
                penX += typographicWidth(
                    string: run.string,
                    font: run.font,
                    fontFaces: fontFaces,
                    fonts: fonts
                )
            }

            if let path, !path.isEmpty {
                segments.append(RunSegment(run: run, path: path))
            }
        }

        // Per-glyph `x` on `<tspan>` are absolute coordinates; text-anchor must
        // not re-shift them to align bounds with `text.origin.x`.
        if text.runs.contains(where: { $0.explicitX != nil }) {
            return segments
        }
        return applyAnchorShift(segments: segments, anchor: text.font.anchor, anchorX: text.origin.x)
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
        return glyphPathUnanchored(
            string: string,
            font: font,
            origin: CGPoint(x: origin.x + shift, y: origin.y),
            rotations: nil,
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
        typographicWidth(of: string, font: font, fontFaces: fontFaces, fonts: fonts)
    }

    private static func typographicWidth(
        of string: String,
        font: SVGFont,
        fontFaces: [SVGFontFace],
        fonts: [String: SVGFontDefinition]
    ) -> CGFloat {
        if let definition = resolveSVGFont(font: font, fontFaces: fontFaces, fonts: fonts) {
            return SVGFontTextLayout.typographicWidth(string: string, font: font, definition: definition)
        }
        return SystemTextLayout.typographicWidth(string: string, font: font)
    }

    private static func explicitPositions(
        string: String,
        xs: [CGFloat],
        y: CGFloat
    ) -> [CGPoint] {
        let chars = Array(string)
        guard !chars.isEmpty, !xs.isEmpty else { return [] }
        return chars.indices.map { i in
            CGPoint(x: xs[min(i, xs.count - 1)], y: y)
        }
    }

    private static func glyphPathAtPositions(
        string: String,
        font: SVGFont,
        positions: [CGPoint],
        rotations: [CGFloat]?,
        fontFaces: [SVGFontFace],
        fonts: [String: SVGFontDefinition]
    ) -> CGPath? {
        if let definition = resolveSVGFont(font: font, fontFaces: fontFaces, fonts: fonts) {
            return SVGFontTextLayout.glyphPathAtPositions(
                string: string,
                font: font,
                positions: positions,
                rotations: rotations,
                definition: definition
            )
        }
        return SystemTextLayout.glyphPathAtPositions(
            string: string,
            font: font,
            positions: positions,
            rotations: rotations
        )
    }

    private static func glyphPathUnanchored(
        string: String,
        font: SVGFont,
        origin: CGPoint,
        rotations: [CGFloat]?,
        fontFaces: [SVGFontFace],
        fonts: [String: SVGFontDefinition]
    ) -> CGPath? {
        if let definition = resolveSVGFont(font: font, fontFaces: fontFaces, fonts: fonts) {
            return SVGFontTextLayout.glyphPathUnanchored(
                string: string,
                font: font,
                origin: origin,
                rotations: rotations,
                definition: definition
            )
        }
        return SystemTextLayout.glyphPathUnanchored(
            string: string,
            font: font,
            origin: origin,
            rotations: rotations
        )
    }

    private static func applyAnchorShift(
        segments: [RunSegment],
        anchor: SVGTextAnchor,
        anchorX: CGFloat
    ) -> [RunSegment] {
        guard !segments.isEmpty else { return [] }
        var bounds = CGRect.null
        for segment in segments {
            bounds = bounds.union(segment.path.boundingBox)
        }
        guard !bounds.isNull else { return segments }

        let shift: CGFloat = {
            switch anchor {
            case .start: return anchorX - bounds.minX
            case .middle: return anchorX - bounds.midX
            case .end: return anchorX - bounds.maxX
            }
        }()
        guard shift != 0 else { return segments }

        return segments.map { segment in
            var transform = CGAffineTransform(translationX: shift, y: 0)
            let shifted = segment.path.copy(using: &transform) ?? segment.path
            return RunSegment(run: segment.run, path: shifted)
        }
    }

    private static func anchorOffset(anchor: SVGTextAnchor, width: CGFloat) -> CGFloat {
        switch anchor {
        case .start: return 0
        case .middle: return -width / 2
        case .end: return -width
        }
    }

    private static func resolveSVGFont(
        font: SVGFont,
        fontFaces: [SVGFontFace],
        fonts: [String: SVGFontDefinition]
    ) -> SVGFontDefinition? {
        for name in familyNames(from: font.family) {
            for face in fontFaces where face.family.caseInsensitiveCompare(name) == .orderedSame {
                guard faceMatches(face, font: font) else { continue }
                if let def = fonts[face.fontID] { return def }
            }
        }
        return nil
    }

    private static func faceMatches(_ face: SVGFontFace, font: SVGFont) -> Bool {
        if let weight = face.weight, weight.normalizedValue != font.weight.normalizedValue {
            return false
        }
        if let style = face.style {
            switch (style, font.style) {
            case (.normal, .normal): break
            case (.italic, .italic), (.italic, .oblique), (.oblique, .italic), (.oblique, .oblique): break
            default: return false
            }
        }
        return true
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

/// SVG `rotate` angles are clockwise; Core Graphics is counter-clockwise.
fileprivate func svgTextGlyphTransform(
    at position: CGPoint,
    rotationDegrees: CGFloat,
    scaleX: CGFloat = 1,
    scaleY: CGFloat = 1
) -> CGAffineTransform {
    var transform = CGAffineTransform(translationX: position.x, y: position.y)
    if rotationDegrees != 0 {
        transform = transform.rotated(by: -rotationDegrees * .pi / 180)
    }
    return transform.scaledBy(x: scaleX, y: scaleY)
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

    static func glyphPathAtPositions(
        string: String,
        font: SVGFont,
        positions: [CGPoint],
        rotations: [CGFloat]?,
        definition: SVGFontDefinition
    ) -> CGPath? {
        guard definition.unitsPerEm > 0 else { return nil }
        let scale = font.size / definition.unitsPerEm
        let fallback = definition.missingGlyph
            ?? SVGGlyph(commands: nil, advance: definition.defaultAdvance)
        let chars = Array(string)
        guard !chars.isEmpty else { return nil }

        let result = CGMutablePath()
        for (i, char) in chars.enumerated() {
            guard i < positions.count else { break }
            guard let scalar = char.unicodeScalars.first else { continue }
            if definition.glyphs[scalar] == nil, Character(scalar).isWhitespace {
                continue
            }
            let glyph = definition.glyphs[scalar] ?? fallback
            guard let commands = glyph.commands, !commands.isEmpty else { continue }
            let glyphPath = commands.makeCGPath()
            let pos = positions[i]
            let angle = rotations.flatMap { $0.indices.contains(i) ? $0[i] : nil } ?? 0
            let transform = svgTextGlyphTransform(
                at: pos,
                rotationDegrees: angle,
                scaleX: scale,
                scaleY: -scale
            )
            result.addPath(glyphPath, transform: transform)
        }
        return result.isEmpty ? nil : result
    }

    static func glyphPathUnanchored(
        string: String,
        font: SVGFont,
        origin: CGPoint,
        rotations: [CGFloat]?,
        definition: SVGFontDefinition
    ) -> CGPath? {
        guard definition.unitsPerEm > 0 else { return nil }
        let scale = font.size / definition.unitsPerEm
        let fallback = definition.missingGlyph
            ?? SVGGlyph(commands: nil, advance: definition.defaultAdvance)

        var penX: CGFloat = 0
        var placements: [(glyph: SVGGlyph, x: CGFloat, index: Int)] = []
        let chars = Array(string)

        for (i, char) in chars.enumerated() {
            guard let scalar = char.unicodeScalars.first else { continue }
            if definition.glyphs[scalar] == nil, Character(scalar).isWhitespace {
                continue
            }
            let glyph = definition.glyphs[scalar] ?? fallback
            placements.append((glyph, penX, i))
            penX += glyph.advance * scale
        }

        let result = CGMutablePath()
        for item in placements {
            guard let commands = item.glyph.commands, !commands.isEmpty else { continue }
            let glyphPath = commands.makeCGPath()
            let angle = rotations.flatMap { $0.indices.contains(item.index) ? $0[item.index] : nil } ?? 0
            let transform = svgTextGlyphTransform(
                at: CGPoint(x: origin.x + item.x, y: origin.y),
                rotationDegrees: angle,
                scaleX: scale,
                scaleY: -scale
            )
            result.addPath(glyphPath, transform: transform)
        }

        return result.isEmpty ? nil : result
    }
}
