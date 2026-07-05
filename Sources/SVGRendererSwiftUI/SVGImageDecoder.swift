import CoreGraphics
import Foundation
import ImageIO
import SVGCore

#if canImport(AppKit) || canImport(UIKit)

/// Decodes raster bytes to `CGImage` with a simple in-memory cache.
enum SVGImageDecoder {

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [Data: CGImage] = [:]

    static func cgImage(from data: Data) -> CGImage? {
        lock.lock()
        if let cached = cache[data] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        lock.lock()
        cache[data] = image
        lock.unlock()
        return image
    }

    /// Effective viewport after substituting intrinsic dimensions for zero width/height.
    static func effectiveViewport(_ viewport: CGRect, intrinsicSize: CGSize) -> CGRect {
        var rect = viewport
        if rect.width <= 0 { rect.size.width = intrinsicSize.width }
        if rect.height <= 0 { rect.size.height = intrinsicSize.height }
        return rect
    }

    /// Transform mapping intrinsic pixel coordinates into the viewport rectangle.
    static func fitTransform(
        intrinsicSize: CGSize,
        viewport: CGRect,
        preserveAspectRatio: SVGPreserveAspectRatio
    ) -> CGAffineTransform {
        CGAffineTransform(translationX: viewport.minX, y: viewport.minY)
            .concatenating(SVGPreserveAspectRatio.viewBoxTransform(
                viewBox: CGRect(origin: .zero, size: intrinsicSize),
                viewportSize: viewport.size,
                preserveAspectRatio: preserveAspectRatio
            ))
    }
}

#endif
