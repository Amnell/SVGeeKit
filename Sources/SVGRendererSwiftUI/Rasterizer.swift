import CoreGraphics
import SwiftUI
import SVGCore
import SVGRenderer

#if canImport(AppKit) || canImport(UIKit)

/// Rasterizes an SVG document to a `CGImage` using SwiftUI `ImageRenderer`.
/// Required by the conformance harness to obtain pixel snapshots without a view hierarchy.
@MainActor
public enum SVGRasterizer {

    public struct Error: Swift.Error, CustomStringConvertible {
        public let message: String
        public var description: String { message }
    }

    /// Renders `document` at `pixelSize` (logical points; scale comes from the renderer).
    /// `scale` of 1 produces 1 pixel per point (matches W3C reference PNGs).
    public static func rasterize(
        _ document: SVGDocument,
        pixelSize: CGSize,
        scale: CGFloat = 1
    ) throws -> CGImage {
        let view = SVGImageView(document: document)
            .frame(width: pixelSize.width, height: pixelSize.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(pixelSize)

        guard let cgImage = renderer.cgImage else {
            throw Error(message: "ImageRenderer.cgImage returned nil")
        }
        return cgImage
    }
}

#endif
