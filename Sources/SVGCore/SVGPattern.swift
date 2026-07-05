import CoreGraphics

public enum SVGPatternUnits: String, Sendable, Equatable {
    case userSpaceOnUse
    case objectBoundingBox
}

/// Parsed `<pattern>` definition. Lives on `SVGDocument.paintServers` and is
/// resolved into `SVGResolvedPattern` during render-tree lowering.
public struct SVGPattern: Equatable, Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public var width: CGFloat
    public var height: CGFloat
    public var patternUnits: SVGPatternUnits
    public var patternContentUnits: SVGPatternUnits
    public var transform: SVGTransform
    public var viewBox: CGRect?
    public var children: [SVGElement]
    /// True when the pattern declared an `xlink:href` that did not resolve
    /// to another pattern in the document (SVG 1.1 §13.4.3). Referencing
    /// such a pattern with an ICC fallback colour uses the fallback; a valid
    /// pattern with zero tile size simply paints nothing.
    public var hasInvalidHref: Bool

    public init(
        x: CGFloat = 0,
        y: CGFloat = 0,
        width: CGFloat = 0,
        height: CGFloat = 0,
        patternUnits: SVGPatternUnits = .objectBoundingBox,
        patternContentUnits: SVGPatternUnits = .userSpaceOnUse,
        transform: SVGTransform = .identity,
        viewBox: CGRect? = nil,
        children: [SVGElement] = [],
        hasInvalidHref: Bool = false
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.patternUnits = patternUnits
        self.patternContentUnits = patternContentUnits
        self.transform = transform
        self.viewBox = viewBox
        self.children = children
        self.hasInvalidHref = hasInvalidHref
    }
}

/// Pattern geometry resolved against a referencing element's bounding box.
/// Tile content (`children`) is lowered at render time.
public struct SVGResolvedPattern: Equatable, Sendable {
    public var children: [SVGElement]
    /// Maps pattern coordinate space to user space (`patternUnits` + `patternTransform`).
    public var patternToUser: SVGTransform
    /// Tile origin. User space when `tileLocalContent`; otherwise pattern space.
    public var x: CGFloat
    public var y: CGFloat
    /// Tile size. User space when `tileLocalContent`; otherwise pattern space.
    public var step: CGSize
    /// Maps pattern content coordinates into tile-local space.
    public var contentMatrix: SVGTransform
    /// When true, pattern children use tile-local coordinates `(0,0)…(step)`
    /// and repeat identically in each cell (`patternContentUnits="userSpaceOnUse"`
    /// without `viewBox`).
    public var tileLocalContent: Bool
    /// When true, pattern content uses the referencing element's bounding box
    /// (`patternContentUnits="objectBoundingBox"` without `viewBox`). The OBB
    /// content matrix is applied inside each translated tile cell.
    public var boundingBoxContent: Bool

    public init(
        children: [SVGElement],
        patternToUser: SVGTransform,
        x: CGFloat,
        y: CGFloat,
        step: CGSize,
        contentMatrix: SVGTransform,
        tileLocalContent: Bool,
        boundingBoxContent: Bool = false
    ) {
        self.children = children
        self.patternToUser = patternToUser
        self.x = x
        self.y = y
        self.step = step
        self.contentMatrix = contentMatrix
        self.tileLocalContent = tileLocalContent
        self.boundingBoxContent = boundingBoxContent
    }
}
