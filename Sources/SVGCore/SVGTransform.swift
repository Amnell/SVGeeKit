import CoreGraphics

/// Affine transform wrapper that stays Equatable + Sendable across modules.
public struct SVGTransform: Equatable, Sendable {
    public var matrix: CGAffineTransform

    public init(_ matrix: CGAffineTransform) { self.matrix = matrix }

    public static let identity = SVGTransform(.identity)

    public func concatenating(_ other: SVGTransform) -> SVGTransform {
        SVGTransform(matrix.concatenating(other.matrix))
    }
}
