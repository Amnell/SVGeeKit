#if canImport(AppKit) || canImport(UIKit)

@preconcurrency import CoreGraphics
import CryptoKit
import Foundation
import SVGCore
import SVGParser

/// In-memory cache of parsed documents and rasterized bitmaps for `SVGRenderedImage`.
///
/// URLSession still owns HTTP byte caching. This layer keys by SVG content hash (not URL),
/// so a revalidated response with new bytes is rasterized again, and the same SVG at 24pt
/// vs 48pt keeps separate bitmaps.
///
/// `NSCache` evicts under memory pressure. Pass `cache: nil` to `SVGRenderedImage` to skip.
public final class SVGRenderedImageCache: @unchecked Sendable {
    public static let shared = SVGRenderedImageCache()

    private let rasters = NSCache<NSString, ImageBox>()
    private let documents = NSCache<NSString, DocumentBox>()

    public init(
        rasterCountLimit: Int = 64,
        rasterCostLimit: Int = 32 * 1024 * 1024,
        documentCountLimit: Int = 32
    ) {
        rasters.countLimit = rasterCountLimit
        rasters.totalCostLimit = rasterCostLimit
        documents.countLimit = documentCountLimit
    }

    public func removeAll() {
        rasters.removeAllObjects()
        documents.removeAllObjects()
    }

    func document(
        data: Data,
        options: SVGParserOptions,
        conditionalContext: SVGConditionalProcessingContext
    ) throws -> SVGDocument {
        let key = documentKey(data: data, options: options, conditionalContext: conditionalContext)
        if let cached = documents.object(forKey: key as NSString)?.document {
            return cached
        }
        let parsed = try SVGParser(conditionalContext: conditionalContext, options: options).parse(data: data)
        documents.setObject(DocumentBox(parsed), forKey: key as NSString)
        return parsed
    }

    func cgImage(
        data: Data,
        options: SVGParserOptions,
        conditionalContext: SVGConditionalProcessingContext,
        pixelSize: CGSize,
        scale: CGFloat
    ) -> CGImage? {
        let key = rasterKey(
            data: data,
            options: options,
            conditionalContext: conditionalContext,
            pixelSize: pixelSize,
            scale: scale
        )
        return rasters.object(forKey: key as NSString)?.image
    }

    func store(
        _ image: CGImage,
        data: Data,
        options: SVGParserOptions,
        conditionalContext: SVGConditionalProcessingContext,
        pixelSize: CGSize,
        scale: CGFloat
    ) {
        let key = rasterKey(
            data: data,
            options: options,
            conditionalContext: conditionalContext,
            pixelSize: pixelSize,
            scale: scale
        )
        let cost = image.bytesPerRow * image.height
        rasters.setObject(ImageBox(image), forKey: key as NSString, cost: cost)
    }

    private func documentKey(
        data: Data,
        options: SVGParserOptions,
        conditionalContext: SVGConditionalProcessingContext
    ) -> String {
        "doc|\(Self.digest(data))|\(Self.configurationToken(options: options, conditionalContext: conditionalContext))"
    }

    private func rasterKey(
        data: Data,
        options: SVGParserOptions,
        conditionalContext: SVGConditionalProcessingContext,
        pixelSize: CGSize,
        scale: CGFloat
    ) -> String {
        let sizeToken = "\(pixelSize.width)x\(pixelSize.height)@\(scale)"
        return "img|\(Self.digest(data))|\(Self.configurationToken(options: options, conditionalContext: conditionalContext))|\(sizeToken)"
    }

    private static func digest(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).base64EncodedString()
    }

    private static func configurationToken(
        options: SVGParserOptions,
        conditionalContext: SVGConditionalProcessingContext
    ) -> String {
        let policy: String = switch options.resourcePolicy {
        case .restricted:
            "restricted"
        case .localFiles(let baseURL):
            "local:\(baseURL.absoluteString)"
        }
        let limits = options.limits
        let languages = conditionalContext.preferredLanguages.joined(separator: ",")
        return [
            policy,
            String(describing: options.failurePolicy),
            "\(limits.maxDocumentBytes),\(limits.maxElementCount),\(limits.maxPathCommands),\(limits.maxNestingDepth),\(limits.maxDataURIBytes),\(limits.maxDefinitions)",
            languages
        ].joined(separator: "|")
    }
}

private final class ImageBox {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

private final class DocumentBox {
    let document: SVGDocument
    init(_ document: SVGDocument) { self.document = document }
}

#endif
