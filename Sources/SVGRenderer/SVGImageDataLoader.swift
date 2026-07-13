import Foundation
import SVGCore

/// Resolves `<image href="…">` to raw raster bytes without ImageIO.
public enum SVGImageDataLoader {

    private static let rasterExtensions: Set<String> = [
        "png", "jpg", "jpeg", "jpe", "gif", "webp", "bmp", "ico", "tif", "tiff"
    ]

    /// Load raster image bytes from a `data:` URI or a local file allowed by `policy`.
    /// Returns `nil` for non-raster hrefs (e.g. `.svg` files) without touching the filesystem.
    static func load(
        href: String,
        policy: SVGResourcePolicy,
        limits: SVGParsingLimits = .default
    ) -> Data? {
        switch SVGHrefResolver.classify(href: href, policy: policy) {
        case .dataURI(let uri):
            guard !limits.dataURIExceedsLimit(uri) else { return nil }
            guard isRasterDataURI(uri) else { return nil }
            return dataFromDataURI(uri)
        case .localFile(let url):
            guard isRasterFileURL(url) else { return nil }
            guard let data = try? Data(contentsOf: url), isRasterData(data) else { return nil }
            return data
        case .fragment, .rejected:
            return nil
        }
    }

    /// Parses `data:[<mediatype>][;base64],<data>` into raw bytes.
    static func dataFromDataURI(_ uri: String) -> Data? {
        guard uri.lowercased().hasPrefix("data:") else { return nil }
        let body = uri.dropFirst(5)
        guard let comma = body.firstIndex(of: ",") else { return nil }
        let metadata = body[..<comma].lowercased()
        let payload = String(body[body.index(after: comma)...])
        let data: Data?
        if metadata.hasSuffix(";base64") {
            data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
        } else {
            data = Data(payload.utf8)
        }
        guard let data, isRasterData(data) else { return nil }
        return data
    }

    static func isRasterDataURI(_ uri: String) -> Bool {
        guard uri.lowercased().hasPrefix("data:") else { return false }
        let body = uri.dropFirst(5)
        guard let comma = body.firstIndex(of: ",") else { return false }
        let metadata = body[..<comma].lowercased()
        guard metadata.hasPrefix("image/") else { return false }
        return !metadata.hasPrefix("image/svg")
    }

    static func isRasterFileHref(_ href: String) -> Bool {
        let path = href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? href
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return rasterExtensions.contains(ext)
    }

    private static func isRasterFileURL(_ url: URL) -> Bool {
        rasterExtensions.contains(url.pathExtension.lowercased())
    }

    /// Rejects XML/SVG payloads and accepts common raster magic numbers.
    public static func isRasterData(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return true } // PNG
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return true } // JPEG
        if data.starts(with: [0x47, 0x49, 0x46, 0x38]) { return true } // GIF
        if data.starts(with: [0x42, 0x4D]) { return true } // BMP
        if data.count >= 12,
           data.starts(with: [0x52, 0x49, 0x46, 0x46]),
           data[8...11].elementsEqual([0x57, 0x45, 0x42, 0x50]) { return true } // WebP
        if data.starts(with: [0x49, 0x49, 0x2A, 0x00]) { return true } // TIFF LE
        if data.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) { return true } // TIFF BE
        if looksLikeMarkup(data) { return false }
        return false
    }

    private static func looksLikeMarkup(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(64), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else { return false }
        return prefix.hasPrefix("<?xml")
            || prefix.hasPrefix("<svg")
            || prefix.hasPrefix("<!doctype")
    }
}
