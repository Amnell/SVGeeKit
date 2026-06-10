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
