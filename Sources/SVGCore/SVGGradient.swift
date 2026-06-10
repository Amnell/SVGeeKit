import CoreGraphics

public struct SVGGradientStop: Equatable, Sendable {
    public var offset: CGFloat
    public var color: SVGColor

    public init(offset: CGFloat, color: SVGColor) {
        self.offset = offset
        self.color = color
    }
}

public enum SVGGradientUnits: String, Sendable, Equatable {
    case userSpaceOnUse
    case objectBoundingBox
}

public enum SVGGradientSpread: String, Sendable, Equatable {
    case pad
    case reflect
    case `repeat`
}

public struct SVGLinearGradient: Equatable, Sendable {
    public var x1: CGFloat
    public var y1: CGFloat
    public var x2: CGFloat
    public var y2: CGFloat
    public var units: SVGGradientUnits
    public var spreadMethod: SVGGradientSpread
    public var stops: [SVGGradientStop]
    public var transform: SVGTransform

    public init(
        x1: CGFloat = 0,
        y1: CGFloat = 0,
        x2: CGFloat = 1,
        y2: CGFloat = 0,
        units: SVGGradientUnits = .objectBoundingBox,
        spreadMethod: SVGGradientSpread = .pad,
        stops: [SVGGradientStop] = [],
        transform: SVGTransform = .identity
    ) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
        self.units = units
        self.spreadMethod = spreadMethod
        self.stops = stops
        self.transform = transform
    }
}

/// A paint definition referenced by `fill="url(#id)"`. Lives on
/// `SVGDocument.paintServers`; resolved into concrete `SVGPaint` cases
/// during render-tree lowering.
public enum SVGPaintServer: Equatable, Sendable {
    case linearGradient(SVGLinearGradient)
}
