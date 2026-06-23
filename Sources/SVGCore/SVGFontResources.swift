import CoreGraphics
import Foundation

/// CSS `@font-face` declaration (`<font-face>` in SVG `<defs>`).
public struct SVGFontFace: Equatable, Sendable {
    /// `font-family` value (unquoted).
    public var family: String
    /// `id` of the resolved `<font>` in `SVGDocument.fonts`.
    public var fontID: String

    public init(family: String, fontID: String) {
        self.family = family
        self.fontID = fontID
    }
}

/// One glyph outline from an SVG `<font>` definition.
public struct SVGGlyph: Equatable, Sendable {
    public var commands: [SVGPathCommand]?
    /// Horizontal advance in font units (`horiz-adv-x` on the glyph, or font default).
    public var advance: CGFloat

    public init(commands: [SVGPathCommand]? = nil, advance: CGFloat) {
        self.commands = commands
        self.advance = advance
    }
}

/// Parsed `<font>` element (SVG font table).
public struct SVGFontDefinition: Equatable, Sendable {
    public var unitsPerEm: CGFloat
    public var ascent: CGFloat
    public var descent: CGFloat
    /// `<font horiz-adv-x="…">` default glyph advance in font units.
    public var defaultAdvance: CGFloat
    public var glyphs: [Unicode.Scalar: SVGGlyph]
    public var missingGlyph: SVGGlyph?

    public init(
        unitsPerEm: CGFloat = 1000,
        ascent: CGFloat = 800,
        descent: CGFloat = -200,
        defaultAdvance: CGFloat = 0,
        glyphs: [Unicode.Scalar: SVGGlyph] = [:],
        missingGlyph: SVGGlyph? = nil
    ) {
        self.unitsPerEm = unitsPerEm
        self.ascent = ascent
        self.descent = descent
        self.defaultAdvance = defaultAdvance
        self.glyphs = glyphs
        self.missingGlyph = missingGlyph
    }
}

extension Array where Element == SVGPathCommand {

    /// Build a `CGPath` from normalized path commands.
    public func makeCGPath() -> CGPath {
        let cg = CGMutablePath()
        for cmd in self {
            switch cmd {
            case .moveTo(let p):
                cg.move(to: p)
            case .lineTo(let p):
                cg.addLine(to: p)
            case .quadTo(let c, let end):
                cg.addQuadCurve(to: end, control: c)
            case .cubicTo(let c1, let c2, let end):
                cg.addCurve(to: end, control1: c1, control2: c2)
            case .close:
                cg.closeSubpath()
            }
        }
        return cg
    }
}
