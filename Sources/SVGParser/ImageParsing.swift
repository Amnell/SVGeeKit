import Foundation
import SVGCore

// MARK: - Post-parse `<image href="…svg">` resolution

/// Context for resolving nested `<image href="…svg">` documents.
struct SVGReferencedImageResolveContext: Sendable {
    /// Files currently being parsed along this branch.
    var loading: Set<URL>
    /// File URL of the SVG document whose element tree is being walked.
    var ownerFileURL: URL?
    /// File URL of the top-level parse (detects cycle-back-to-root).
    var rootFileURL: URL?

    static func topLevel(loading: Set<URL> = [], sourceURL: URL?) -> Self {
        let file = sourceURL?.standardizedFileURL
        return SVGReferencedImageResolveContext(
            loading: loading,
            ownerFileURL: file,
            rootFileURL: file
        )
    }

    func nestedLoad(of fileURL: URL) -> Self {
        var next = self
        next.loading.insert(fileURL)
        next.ownerFileURL = fileURL
        return next
    }
}

/// Resolves external SVG documents for `<image>` elements after the main parse
/// completes. NSXMLParser does not support reentrant parsing, so resolution is
/// deferred until SAX finishes. Loading chains detect cyclic href graphs
/// (e.g. `struct-image-12-b` ↔ `struct-image-12-b-cycle`) and break them.
enum SVGReferencedImageResolver {

    static func resolve(
        in document: inout SVGDocument,
        context: SVGReferencedImageResolveContext
    ) {
        document.root = resolve(
            in: document.root,
            baseURL: document.baseURL,
            context: context
        )
    }

    private static func resolve(
        in group: SVGGroup,
        baseURL: URL?,
        context: SVGReferencedImageResolveContext
    ) -> SVGGroup {
        var updated = group
        updated.children = group.children.map {
            resolve(element: $0, baseURL: baseURL, context: context)
        }
        return updated
    }

    private static func resolve(
        element: SVGElement,
        baseURL: URL?,
        context: SVGReferencedImageResolveContext
    ) -> SVGElement {
        switch element {
        case .image(var image):
            image.referencedDocument = loadReferencedSVGDocument(
                href: image.href,
                baseURL: baseURL,
                context: context
            )
            return .image(image)
        case .group(let group):
            return .group(resolve(in: group, baseURL: baseURL, context: context))
        case .svg(var svg):
            svg.children = svg.children.map {
                resolve(element: $0, baseURL: baseURL, context: context)
            }
            return .svg(svg)
        default:
            return element
        }
    }

    private static func loadReferencedSVGDocument(
        href: String,
        baseURL: URL?,
        context: SVGReferencedImageResolveContext
    ) -> SVGDocument? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().hasPrefix("data:") {
            guard isSVGDataURI(trimmed),
                  let data = dataFromSVGDataURI(trimmed),
                  let doc = try? SVGParser().parse(
                    data: data,
                    baseURL: baseURL,
                    sourceURL: nil,
                    referencedImageContext: context
                  ) else {
                return nil
            }
            return doc
        }

        guard isSVGFileHref(trimmed) else { return nil }
        guard let resolved = resolveImageHref(trimmed, baseURL: baseURL) else { return nil }
        let fileURL = resolved.standardizedFileURL
        guard !isBlockedReference(fileURL, context: context) else { return nil }
        return ExternalSVGImageCache.document(
            at: fileURL,
            parseBaseURL: fileURL.deletingLastPathComponent(),
            parseContext: context.nestedLoad(of: fileURL)
        )
    }

    /// Returns `true` when an href must not be loaded (self-reference or cycle).
    static func isBlockedReference(
        _ fileURL: URL,
        context: SVGReferencedImageResolveContext
    ) -> Bool {
        if context.loading.contains(fileURL) { return true }
        if context.ownerFileURL == fileURL { return true }
        if let root = context.rootFileURL, root == fileURL, !context.loading.isEmpty {
            return true
        }
        return false
    }

    private static func isSVGFileHref(_ href: String) -> Bool {
        let path = hrefPathComponent(href)
        guard !path.isEmpty else { return false }
        return URL(fileURLWithPath: path).pathExtension.lowercased() == "svg"
    }

    private static func isSVGDataURI(_ uri: String) -> Bool {
        guard uri.lowercased().hasPrefix("data:") else { return false }
        let body = uri.dropFirst(5)
        guard let comma = body.firstIndex(of: ",") else { return false }
        let metadata = body[..<comma].lowercased()
        return metadata.hasPrefix("image/svg")
    }

    private static func dataFromSVGDataURI(_ uri: String) -> Data? {
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

    private static func hrefPathComponent(_ href: String) -> String {
        href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? href
    }

    private static func resolveImageHref(_ href: String, baseURL: URL?) -> URL? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute.isFileURL ? absolute : nil
        }
        guard let baseURL else { return URL(fileURLWithPath: trimmed) }
        let pathPart = hrefPathComponent(trimmed)
        let fragment = hrefFragment(trimmed)
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

    private static func hrefFragment(_ href: String) -> String? {
        guard let hash = href.firstIndex(of: "#") else { return nil }
        let fragment = String(href[href.index(after: hash)...])
        return fragment.isEmpty ? nil : fragment
    }
}

// MARK: - External SVG image cache

/// Parsed SVG documents referenced by `<image href="…svg">`, keyed by resolved file URL.
private enum ExternalSVGImageCache {
    private static let cache = Cache()

    static func document(
        at fileURL: URL,
        parseBaseURL: URL,
        parseContext: SVGReferencedImageResolveContext
    ) -> SVGDocument? {
        cache.document(at: fileURL, parseBaseURL: parseBaseURL, parseContext: parseContext)
    }

    private final class Cache: @unchecked Sendable {
        private var storage: [URL: SVGDocument] = [:]
        private let lock = NSLock()

        func document(
            at fileURL: URL,
            parseBaseURL: URL,
            parseContext: SVGReferencedImageResolveContext
        ) -> SVGDocument? {
            let key = fileURL.standardizedFileURL
            lock.lock()
            if let cached = storage[key] {
                lock.unlock()
                return cached
            }
            lock.unlock()

            guard let data = try? Data(contentsOf: key),
                  let extDoc = try? SVGParser().parse(
                    data: data,
                    baseURL: parseBaseURL,
                    sourceURL: key,
                    referencedImageContext: parseContext
                  ) else {
                return nil
            }

            lock.lock()
            storage[key] = extDoc
            lock.unlock()
            return extDoc
        }
    }
}
