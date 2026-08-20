#if canImport(AppKit) || canImport(UIKit)

@preconcurrency import CoreGraphics
import Foundation
import SwiftUI
import SVGCore
import SVGParser

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// A bitmap rasterized from an SVG document, for use with `Image` / `UIImage` / `NSImage`.
///
/// Named separately from `SVGImage`, which is the SVG `<image>` element model.
public struct SVGRenderedImage: Sendable {
    public let cgImage: CGImage
    /// Pixels per point used when rasterizing. Match SwiftUI's `displayScale` for retina output.
    public let scale: CGFloat

    /// Logical point size (`cgImage` pixel dimensions divided by `scale`).
    public var size: CGSize {
        CGSize(
            width: CGFloat(cgImage.width) / scale,
            height: CGFloat(cgImage.height) / scale
        )
    }

    /// Fetch, parse, and rasterize the SVG at `url`.
    ///
    /// When `size` is `nil`, the document's width/height or `viewBox` is used. Pass a size to
    /// choose the output bitmap in points (`scale` multiplies pixel dimensions).
    ///
    /// Parsed documents and rasters are stored in `cache` (`.shared` by default), keyed by
    /// content hash and output size. Pass `cache: nil` to disable. HTTP byte caching remains
    /// `session`'s job.
    public init(
        url: URL,
        size: CGSize? = nil,
        scale: CGFloat = 1,
        parser: SVGParser = SVGParser(),
        session: URLSession = .shared,
        cache: SVGRenderedImageCache? = .shared
    ) async throws {
        try await self.init(
            urlRequest: URLRequest(url: url),
            size: size,
            scale: scale,
            parser: parser,
            session: session,
            cache: cache
        )
    }

    /// Fetch, parse, and rasterize the SVG using `urlRequest`.
    public init(
        urlRequest: URLRequest,
        size: CGSize? = nil,
        scale: CGFloat = 1,
        parser: SVGParser = SVGParser(),
        session: URLSession = .shared,
        cache: SVGRenderedImageCache? = .shared
    ) async throws {
        let data = try await SVGRemoteImageLoader.data(for: urlRequest, session: session)
        let options = parser.options
        let conditionalContext = parser.conditionalContext
        self = try await Task.detached(priority: .userInitiated) {
            try SVGRenderedImage(
                data: data,
                size: size,
                scale: scale,
                options: options,
                conditionalContext: conditionalContext,
                cache: cache
            )
        }.value
    }

    /// Parse and rasterize SVG bytes.
    public init(
        data: Data,
        size: CGSize? = nil,
        scale: CGFloat = 1,
        parser: SVGParser = SVGParser(),
        cache: SVGRenderedImageCache? = .shared
    ) throws {
        try self.init(
            data: data,
            size: size,
            scale: scale,
            options: parser.options,
            conditionalContext: parser.conditionalContext,
            cache: cache
        )
    }

    /// Rasterize an already-parsed document.
    public init(
        document: SVGDocument,
        size: CGSize? = nil,
        scale: CGFloat = 1
    ) throws {
        let pixelSize = try Self.resolvedPixelSize(document: document, size: size)
        self.cgImage = try SVGRasterizer.rasterize(document, pixelSize: pixelSize, scale: scale)
        self.scale = scale
    }

    private init(
        data: Data,
        size: CGSize?,
        scale: CGFloat,
        options: SVGParserOptions,
        conditionalContext: SVGConditionalProcessingContext,
        cache: SVGRenderedImageCache?
    ) throws {
        let document: SVGDocument
        if let cache {
            document = try cache.document(
                data: data,
                options: options,
                conditionalContext: conditionalContext
            )
        } else {
            document = try SVGParser(conditionalContext: conditionalContext, options: options).parse(data: data)
        }

        let pixelSize = try Self.resolvedPixelSize(document: document, size: size)
        if let cache,
           let cached = cache.cgImage(
            data: data,
            options: options,
            conditionalContext: conditionalContext,
            pixelSize: pixelSize,
            scale: scale
           ) {
            self.cgImage = cached
            self.scale = scale
            return
        }

        let image = try SVGRasterizer.rasterize(document, pixelSize: pixelSize, scale: scale)
        cache?.store(
            image,
            data: data,
            options: options,
            conditionalContext: conditionalContext,
            pixelSize: pixelSize,
            scale: scale
        )
        self.cgImage = image
        self.scale = scale
    }

    /// SwiftUI `Image` wrapping the rasterized bitmap.
    public var image: Image {
        #if canImport(UIKit)
        Image(uiImage: uiImage)
        #elseif canImport(AppKit)
        Image(nsImage: nsImage)
        #endif
    }

    #if canImport(UIKit)
    public var uiImage: UIImage {
        UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
    #endif

    #if canImport(AppKit)
    public var nsImage: NSImage {
        NSImage(cgImage: cgImage, size: size)
    }
    #endif

    private static func resolvedPixelSize(document: SVGDocument, size: CGSize?) throws -> CGSize {
        if let size {
            return size
        }
        if let intrinsic = document.intrinsicSize ?? document.viewBox?.size,
           intrinsic.width > 0,
           intrinsic.height > 0 {
            return intrinsic
        }
        throw SVGRenderedImageError.missingSize
    }
}

extension Image {
    public init(_ rendered: SVGRenderedImage) {
        self = rendered.image
    }
}

/// Failures specific to `SVGRenderedImage` rasterization (load and parse errors use
/// `SVGRemoteImageError` / `SVGParseError`).
public enum SVGRenderedImageError: Error, Equatable, Sendable {
    /// `size` was omitted and the document has no width/height or `viewBox`.
    case missingSize
}

extension SVGRenderedImageError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingSize:
            return "The SVG has no intrinsic size; pass an explicit size to rasterize."
        }
    }
}

#endif
