import Foundation

/// Resolves `<image href="…">` to raw raster bytes without ImageIO.
enum SVGImageDataLoader {

    /// Load image bytes from a `data:` URI or a file URL resolved against `baseURL`.
    static func load(href: String, baseURL: URL?) -> Data? {
        if href.lowercased().hasPrefix("data:") {
            return dataFromDataURI(href)
        }
        guard let url = resolveFileURL(href, baseURL: baseURL) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Parses `data:[<mediatype>][;base64],<data>` into raw bytes.
    static func dataFromDataURI(_ uri: String) -> Data? {
        guard uri.lowercased().hasPrefix("data:") else { return nil }
        let body = uri.dropFirst(5)
        guard let comma = body.firstIndex(of: ",") else { return nil }
        let metadata = body[..<comma].lowercased()
        let payload = String(body[body.index(after: comma)...])
        if metadata.hasSuffix(";base64") {
            return Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
        }
        return Data(payload.utf8)
    }

    private static func resolveFileURL(_ href: String, baseURL: URL?) -> URL? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute.isFileURL ? absolute : nil
        }
        guard let baseURL else { return URL(fileURLWithPath: trimmed) }
        let (pathPart, fragment) = splitFragment(trimmed)
        guard var resolved = URL(string: pathPart, relativeTo: baseURL)?.standardizedFileURL else {
            return nil
        }
        if let fragment {
            var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false)
            components?.fragment = fragment
            resolved = components?.url ?? resolved
        }
        return resolved
    }

    private static func splitFragment(_ href: String) -> (String, String?) {
        guard let hash = href.firstIndex(of: "#") else { return (href, nil) }
        let pathPart = String(href[..<hash])
        let fragment = String(href[href.index(after: hash)...])
        return (pathPart, fragment.isEmpty ? nil : fragment)
    }
}
