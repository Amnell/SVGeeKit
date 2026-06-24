import CoreGraphics
import Foundation
import SVGCore

/// Dispatches text layout to SVG fonts when available, otherwise CoreText.
enum TextLayout {

    struct RunSegment {
        var run: SVGTextRun
        var path: CGPath
    }

    /// Per-character layout result for tests and diagnostics.
    struct CharacterPlacement: Sendable, Equatable {
        var character: Character
        var position: CGPoint
        var rotation: CGFloat
        var runIndex: Int
    }

    static func layoutCharacterPlacements(
        text: SVGText,
        fontFaces: [SVGFontFace],
        fonts: [String: SVGFontDefinition]
    ) -> [CharacterPlacement] {
        layoutRunLayouts(text: text, fontFaces: fontFaces, fonts: fonts).flatMap { batch in
            let chars = Array(batch.run.string)
            return batch.positions.enumerated().map { i, pos in
                CharacterPlacement(
                    character: chars[i],
                    position: pos,
                    rotation: rotationAngle(at: i, rotations: batch.run.rotations),
                    runIndex: batch.runIndex
                )
            }
        }
    }

    private struct RunLayout {
        var run: SVGTextRun
        var runIndex: Int
        var positions: [CGPoint]
    }

    private static func layoutRunLayouts(
        text: SVGText,
        fontFaces: [SVGFontFace],
        fonts: [String: SVGFontDefinition]
    ) -> [RunLayout] {
        guard !text.runs.isEmpty else { return [] }

        var penX = text.origin.x
        var penY = text.origin.y
        /// Rotated text without per-run `y` keeps the block baseline at the
        /// root `<text>` origin until an `explicitY` tspan resets it.
        let hasRotations = text.runs.contains { $0.rotations != nil }
        var activeLineY: CGFloat? = hasRotations ? text.origin.y : nil
        var batches: [RunLayout] = []

        for (runIndex, run) in text.runs.enumerated() {
            penX += run.dx
            penY += run.dy
            guard !run.string.isEmpty else { continue }

            if let explicitY = run.explicitY {
                penY = explicitY
                activeLineY = explicitY
            } else if let activeLineY {
                penY = activeLineY
            }

            let lineFixedY = run.explicitY == nil ? activeLineY : nil

            let (positions, endPen) = layoutCharacterPositions(
                string: run.string,
                font: run.font,
                explicitX: run.explicitX,
                explicitY: run.explicitY,
                lineFixedY: lineFixedY,
                startPen: CGPoint(x: penX, y: penY),
                rotations: run.rotations,
                fontFaces: fontFaces,
                fonts: fonts
            )
            batches.append(RunLayout(run: run, runIndex: runIndex, positions: positions))
            penX = endPen.x
            penY = endPen.y
        }

        return batches
    }

    private static func rotationAngle(at index: Int, rotations: [CGFloat]?) -> CGFloat {
        guard let rotations else { return 0 }
        if rotations.indices.contains(index) { return rotations[index] }
        return rotations.last ?? 0
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
        let batches = layoutRunLayouts(text: text, fontFaces: fontFaces, fonts: fonts)
        var segments: [RunSegment] = []

        for batch in batches {
            let path = glyphPathAtPositions(
                string: batch.run.string,
                font: batch.run.font,
                positions: batch.positions,
                rotations: batch.run.rotations,
                fontFaces: fontFaces,
                fonts: fonts
            )
            if let path, !path.isEmpty {
                segments.append(RunSegment(run: batch.run, path: path))
            }
        }

        // Per-glyph `x` on `<tspan>` are absolute coordinates; `text-anchor`
        // must not re-shift explicit or rotated glyph placement.
        if text.runs.contains(where: { $0.explicitX != nil || $0.rotations != nil }) {
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

    private static func layoutCharacterPositions(
        string: String,
        font: SVGFont,
        explicitX: [CGFloat]?,
        explicitY: CGFloat?,
        lineFixedY: CGFloat?,
        startPen: CGPoint,
        rotations: [CGFloat]?,
        fontFaces: [SVGFontFace],
        fonts: [String: SVGFontDefinition]
    ) -> (positions: [CGPoint], endPen: CGPoint) {
        let chars = Array(string)
        guard !chars.isEmpty else { return ([], startPen) }

        let fixedY = explicitY ?? lineFixedY
        var pen = startPen
        if let fixedY {
            pen.y = fixedY
        }
        var positions: [CGPoint] = []

        for i in 0..<chars.count {
            let angle: CGFloat = {
                guard let rotations else { return 0 }
                if rotations.indices.contains(i) { return rotations[i] }
                return rotations.last ?? 0
            }()
            let radians = angle * .pi / 180
            let y = fixedY ?? pen.y

            let pos: CGPoint
            if let xs = explicitX, i < xs.count {
                pos = CGPoint(x: xs[i], y: y)
            } else {
                pos = CGPoint(x: pen.x, y: y)
            }
            positions.append(pos)

            let advance = charAdvance(
                of: String(chars[i]),
                font: font,
                fontFaces: fontFaces,
                fonts: fonts
            )
            if fixedY != nil {
                // Block baseline: glyphs rotate at the anchor but inline
                // progression stays horizontal (matches W3C text-tspan-02-b).
                let xAdvance = rotations != nil ? advance : advance * cos(radians)
                pen = CGPoint(
                    x: pos.x + xAdvance,
                    y: fixedY!
                )
            } else {
                pen = CGPoint(
                    x: pos.x + advance * cos(radians),
                    y: pos.y + advance * sin(radians)
                )
            }
        }

        return (positions, pen)
    }

    private static func charAdvance(
        of string: String,
        font: SVGFont,
        fontFaces: [SVGFontFace],
        fonts: [String: SVGFontDefinition]
    ) -> CGFloat {
        if let definition = resolveSVGFont(font: font, fontFaces: fontFaces, fonts: fonts) {
            return SVGFontTextLayout.charAdvance(string: string, font: font, definition: definition)
        }
        return SystemTextLayout.charAdvance(string: string, font: font)
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

/// SVG and Core Graphics both use y-down user space where positive angles rotate clockwise.
fileprivate func svgTextGlyphTransform(
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

enum SVGFontTextLayout {

    static func charAdvance(
        string: String,
        font: SVGFont,
        definition: SVGFontDefinition
    ) -> CGFloat {
        guard definition.unitsPerEm > 0,
              let scalar = string.unicodeScalars.first else { return 0 }
        let scale = font.size / definition.unitsPerEm
        let fallback = definition.missingGlyph
            ?? SVGGlyph(commands: nil, advance: definition.defaultAdvance)
        let glyph = definition.glyphs[scalar] ?? fallback
        return glyph.advance * scale
    }

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
