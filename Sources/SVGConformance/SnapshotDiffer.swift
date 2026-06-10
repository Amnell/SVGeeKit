import CoreGraphics
import Foundation
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// Pixel-level snapshot diffing with per-channel tolerance.
public enum SVGSnapshotDiffer {

    public struct DiffResult: Sendable {
        public let pixelsCompared: Int
        public let mismatchedPixels: Int
        public let maxChannelDelta: UInt8
        public let mismatchedFraction: Double
        public var matches: Bool { mismatchedFraction == 0 }
    }

    public struct Tolerance: Sendable {
        /// 0...255. Channel deltas at or below this count as a match.
        public let perChannel: UInt8
        /// 0.0...1.0. Fraction of pixels allowed to exceed perChannel.
        public let pixelFraction: Double

        public init(perChannel: UInt8 = 0, pixelFraction: Double = 0) {
            self.perChannel = perChannel
            self.pixelFraction = pixelFraction
        }

        public static let exact = Tolerance()
    }

    public enum DiffError: Error, CustomStringConvertible {
        case sizeMismatch(expected: CGSize, actual: CGSize)
        case unableToReadPixels

        public var description: String {
            switch self {
            case .sizeMismatch(let e, let a):
                return "image size mismatch: expected \(e), got \(a)"
            case .unableToReadPixels:
                return "unable to read pixel data from CGImage"
            }
        }
    }

    /// Compare two images. Both are coerced to premultiplied 8-bit RGBA before diffing.
    public static func diff(
        _ lhs: CGImage,
        _ rhs: CGImage,
        tolerance: Tolerance = .exact
    ) throws -> DiffResult {
        guard lhs.width == rhs.width, lhs.height == rhs.height else {
            throw DiffError.sizeMismatch(
                expected: CGSize(width: lhs.width, height: lhs.height),
                actual: CGSize(width: rhs.width, height: rhs.height)
            )
        }
        let lhsPixels = try readRGBA(from: lhs)
        let rhsPixels = try readRGBA(from: rhs)

        var mismatched = 0
        var maxDelta: UInt8 = 0
        let count = lhsPixels.count / 4
        for i in 0..<count {
            let off = i * 4
            var pixelExceeds = false
            for c in 0..<4 {
                let a = lhsPixels[off + c]
                let b = rhsPixels[off + c]
                let d: UInt8 = a > b ? a - b : b - a
                if d > maxDelta { maxDelta = d }
                if d > tolerance.perChannel { pixelExceeds = true }
            }
            if pixelExceeds { mismatched += 1 }
        }
        let fraction = count == 0 ? 0 : Double(mismatched) / Double(count)
        return DiffResult(
            pixelsCompared: count,
            mismatchedPixels: mismatched,
            maxChannelDelta: maxDelta,
            mismatchedFraction: fraction
        )
    }

    /// Write a PNG to disk, creating parent directories as needed.
    public static func writePNG(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let type: CFString = {
            #if canImport(UniformTypeIdentifiers)
            return UTType.png.identifier as CFString
            #else
            return "public.png" as CFString
            #endif
        }()
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            throw DiffError.unableToReadPixels
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw DiffError.unableToReadPixels
        }
    }

    public static func loadPNG(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private static func readRGBA(from image: CGImage) throws -> [UInt8] {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
                      | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = pixels.withUnsafeMutableBytes({ buffer -> CGContext? in
            guard let base = buffer.baseAddress else { return nil }
            return CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        }) else {
            throw DiffError.unableToReadPixels
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }
}
