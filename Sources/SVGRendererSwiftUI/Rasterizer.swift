import CoreGraphics
import SVGCore
import SVGRenderer

#if canImport(AppKit) || canImport(UIKit)

/// Rasterizes an SVG document to a `CGImage` via Core Graphics.
/// Used by the conformance harness for snapshot-quality output with SVG-correct gradients.
public enum SVGRasterizer {

    public struct Error: Swift.Error, CustomStringConvertible {
        public let message: String
        public var description: String { message }
    }

    /// Renders `document` at `pixelSize` (logical points; `scale` multiplies output pixels).
    /// A `scale` of 1 produces 1 pixel per point (matches W3C reference PNGs).
    public static func rasterize(
        _ document: SVGDocument,
        pixelSize: CGSize,
        scale: CGFloat = 1
    ) throws -> CGImage {
        var doc = document
        if doc.intrinsicSize == nil {
            doc.intrinsicSize = document.viewBox?.size
        }
        let commands = SVGRenderTree.lower(doc)

        let pixelWidth = Int(ceil(pixelSize.width * scale))
        let pixelHeight = Int(ceil(pixelSize.height * scale))
        guard pixelWidth > 0, pixelHeight > 0 else {
            throw Error(message: "Invalid raster size \(pixelWidth)×\(pixelHeight)")
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw Error(message: "Failed to create CGContext")
        }

        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 0, y: pixelSize.height)
        ctx.scaleBy(x: 1, y: -1)

        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high

        ctx.clear(CGRect(origin: .zero, size: pixelSize))

        if let intrinsic = doc.intrinsicSize,
           intrinsic.width > 0, intrinsic.height > 0,
           pixelSize != intrinsic
        {
            let sx = pixelSize.width / intrinsic.width
            let sy = pixelSize.height / intrinsic.height
            ctx.scaleBy(x: sx, y: sy)
        }

        CGContextRenderer().execute(commands, in: ctx)

        guard let cgImage = ctx.makeImage() else {
            throw Error(message: "CGContext.makeImage() returned nil")
        }
        return cgImage
    }
}

#endif
