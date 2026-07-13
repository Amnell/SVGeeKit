import CoreGraphics
import Foundation

/// `<image>` element (SVG 1.1 §5.11). `href` may reference raster bytes or another SVG document.
public struct SVGImage: Equatable, Sendable {
    public var id: String?
    public var origin: CGPoint
    /// Viewport size; zero width or height means use intrinsic image dimensions.
    public var size: CGSize
    public var href: String
    /// Parsed SVG document when `href` references `.svg` content; `nil` for raster hrefs.
    public var referencedDocument: SVGDocument?
    public var preserveAspectRatio: SVGPreserveAspectRatio
    public var paint: SVGPaintProperties
    public var transform: SVGTransform

    public init(
        id: String? = nil,
        origin: CGPoint = .zero,
        size: CGSize = .zero,
        href: String,
        referencedDocument: SVGDocument? = nil,
        preserveAspectRatio: SVGPreserveAspectRatio = .default,
        paint: SVGPaintProperties = .init(),
        transform: SVGTransform = .identity
    ) {
        self.id = id
        self.origin = origin
        self.size = size
        self.href = href
        self.referencedDocument = referencedDocument
        self.preserveAspectRatio = preserveAspectRatio
        self.paint = paint
        self.transform = transform
    }
}
