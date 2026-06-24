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

    public init(
        x: CGFloat = 0,
        y: CGFloat = 0,
        width: CGFloat = 0,
        height: CGFloat = 0,
        patternUnits: SVGPatternUnits = .objectBoundingBox,
        patternContentUnits: SVGPatternUnits = .userSpaceOnUse,
        transform: SVGTransform = .identity,
        viewBox: CGRect? = nil,
        children: [SVGElement] = []
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
    }
}

/// Pattern geometry resolved against a referencing element's bounding box.
/// Tile content (`children`) is lowered at render time.
public struct SVGResolvedPattern: Equatable, Sendable {
    public var children: [SVGElement]
    /// Maps pattern coordinate space to user space (`patternUnits` + `patternTransform`).
    public var patternToUser: SVGTransform
    /// Tile origin in pattern coordinate space.
    public var x: CGFloat
    public var y: CGFloat
    /// Tile size in pattern coordinate space.
    public var step: CGSize
    /// Maps pattern content coordinates into tile-local space.
    public var contentMatrix: SVGTransform
    /// When true, children are already in user space and each tile only clips.
    public var contentUsesUserSpace: Bool

    public init(
        children: [SVGElement],
        patternToUser: SVGTransform,
        x: CGFloat,
        y: CGFloat,
        step: CGSize,
        contentMatrix: SVGTransform,
        contentUsesUserSpace: Bool
    ) {
        self.children = children
        self.patternToUser = patternToUser
        self.x = x
        self.y = y
        self.step = step
        self.contentMatrix = contentMatrix
        self.contentUsesUserSpace = contentUsesUserSpace
    }
}
