import CoreGraphics
import Foundation

/// Raster `<image>` element (SVG 1.1 §5.11).
public struct SVGImage: Equatable, Sendable {
    public var id: String?
    public var origin: CGPoint
    /// Viewport size; zero width or height means use intrinsic image dimensions.
    public var size: CGSize
    public var href: String
    public var preserveAspectRatio: SVGPreserveAspectRatio
    public var paint: SVGPaintProperties
    public var transform: SVGTransform

    public init(
        id: String? = nil,
        origin: CGPoint = .zero,
        size: CGSize = .zero,
        href: String,
        preserveAspectRatio: SVGPreserveAspectRatio = .default,
        paint: SVGPaintProperties = .init(),
        transform: SVGTransform = .identity
    ) {
        self.id = id
        self.origin = origin
        self.size = size
        self.href = href
        self.preserveAspectRatio = preserveAspectRatio
        self.paint = paint
        self.transform = transform
    }
}
