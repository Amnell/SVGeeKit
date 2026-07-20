import CoreGraphics
import Foundation
import ImageIO
import SVGCore
import SVGRenderer

#if canImport(AppKit) || canImport(UIKit)

/// Decodes raster bytes to `CGImage` with a simple in-memory cache.
enum SVGImageDecoder {

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [Data: CGImage] = [:]
    nonisolated(unsafe) private static var failed: Set<Data> = []

    static func cgImage(from data: Data, iccProfileData: Data? = nil) -> CGImage? {
        guard SVGImageDataLoader.isRasterData(data) else { return nil }

        lock.lock()
        if let cached = cache[data] {
            lock.unlock()
            return applyICCProfile(cached, iccProfileData: iccProfileData)
        }
        if failed.contains(data) {
            lock.unlock()
            return nil
        }
        lock.unlock()

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            lock.lock()
            failed.insert(data)
            lock.unlock()
            return nil
        }

        lock.lock()
        cache[data] = image
        lock.unlock()
        return applyICCProfile(image, iccProfileData: iccProfileData)
    }

    /// Reinterpret pixel values in `iccProfileData`'s color space (SVG `color-profile`
    /// on `<image>`). Drawing into an sRGB destination then converts via ColorSync.
    private static func applyICCProfile(_ image: CGImage, iccProfileData: Data?) -> CGImage {
        guard let iccProfileData,
              let space = CGColorSpace(iccData: iccProfileData as CFData),
              let provider = image.dataProvider,
              let tagged = CGImage(
                width: image.width,
                height: image.height,
                bitsPerComponent: image.bitsPerComponent,
                bitsPerPixel: image.bitsPerPixel,
                bytesPerRow: image.bytesPerRow,
                space: space,
                bitmapInfo: image.bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              )
        else {
            return image
        }
        return tagged
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
        // `a.concatenating(b)` applies `a` then `b`. Scale/align into local
        // viewport space first, then translate to `viewport.origin`.
        SVGPreserveAspectRatio.viewBoxTransform(
            viewBox: CGRect(origin: .zero, size: intrinsicSize),
            viewportSize: viewport.size,
            preserveAspectRatio: preserveAspectRatio
        ).concatenating(CGAffineTransform(translationX: viewport.minX, y: viewport.minY))
    }
}

#endif
