import CoreGraphics
import Foundation

/// A parsed SVG document. Pure value type; no I/O, no rendering.
public struct SVGDocument: Equatable, Sendable {
    public var viewBox: CGRect?
    public var intrinsicSize: CGSize?
    public var root: SVGGroup

    public init(viewBox: CGRect? = nil, intrinsicSize: CGSize? = nil, root: SVGGroup = SVGGroup()) {
        self.viewBox = viewBox
        self.intrinsicSize = intrinsicSize
        self.root = root
    }
}

/// A grouping container. Used for the implicit root and for `<g>`.
public struct SVGGroup: Equatable, Sendable {
    public var transform: SVGTransform
    public var children: [SVGElement]

    public init(transform: SVGTransform = .identity, children: [SVGElement] = []) {
        self.transform = transform
        self.children = children
    }
}

/// Discriminated union of SVG elements supported by the model.
/// Add new cases here as features land in Phase 3.
public enum SVGElement: Equatable, Sendable {
    case group(SVGGroup)
    case rect(SVGRect)
    case circle(SVGCircle)
    case ellipse(SVGEllipse)
    case line(SVGLine)
    case polyline(SVGPolyline)
    case polygon(SVGPolygon)
}

public struct SVGRect: Equatable, Sendable {
    public var origin: CGPoint
    public var size: CGSize
    public var cornerRadii: CGSize
    public var paint: SVGPaintProperties
    public var transform: SVGTransform

    public init(
        origin: CGPoint,
        size: CGSize,
        cornerRadii: CGSize = .zero,
        paint: SVGPaintProperties = .init(),
        transform: SVGTransform = .identity
    ) {
        self.origin = origin
        self.size = size
        self.cornerRadii = cornerRadii
        self.paint = paint
        self.transform = transform
    }
}

public struct SVGCircle: Equatable, Sendable {
    public var center: CGPoint
    public var radius: CGFloat
    public var paint: SVGPaintProperties
    public var transform: SVGTransform

    public init(
        center: CGPoint,
        radius: CGFloat,
        paint: SVGPaintProperties = .init(),
        transform: SVGTransform = .identity
    ) {
        self.center = center
        self.radius = radius
        self.paint = paint
        self.transform = transform
    }
}

public struct SVGEllipse: Equatable, Sendable {
    public var center: CGPoint
    public var radii: CGSize
    public var paint: SVGPaintProperties
    public var transform: SVGTransform

    public init(
        center: CGPoint,
        radii: CGSize,
        paint: SVGPaintProperties = .init(),
        transform: SVGTransform = .identity
    ) {
        self.center = center
        self.radii = radii
        self.paint = paint
        self.transform = transform
    }
}

public struct SVGLine: Equatable, Sendable {
    public var start: CGPoint
    public var end: CGPoint
    public var paint: SVGPaintProperties
    public var transform: SVGTransform

    public init(
        start: CGPoint,
        end: CGPoint,
        paint: SVGPaintProperties = .init(),
        transform: SVGTransform = .identity
    ) {
        self.start = start
        self.end = end
        self.paint = paint
        self.transform = transform
    }
}

public struct SVGPolyline: Equatable, Sendable {
    public var points: [CGPoint]
    public var paint: SVGPaintProperties
    public var transform: SVGTransform

    public init(
        points: [CGPoint],
        paint: SVGPaintProperties = .init(),
        transform: SVGTransform = .identity
    ) {
        self.points = points
        self.paint = paint
        self.transform = transform
    }
}

public struct SVGPolygon: Equatable, Sendable {
    public var points: [CGPoint]
    public var paint: SVGPaintProperties
    public var transform: SVGTransform

    public init(
        points: [CGPoint],
        paint: SVGPaintProperties = .init(),
        transform: SVGTransform = .identity
    ) {
        self.points = points
        self.paint = paint
        self.transform = transform
    }
}
