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
        context: SVGReferencedImageResolveContext,
        policy: SVGResourcePolicy,
        parserOptions: SVGParserOptions,
        warnings: inout [SVGParseWarning]
    ) {
        document.root = resolve(
            in: document.root,
            context: context,
            policy: policy,
            parserOptions: parserOptions,
            warnings: &warnings
        )
    }

    private static func resolve(
        in group: SVGGroup,
        context: SVGReferencedImageResolveContext,
        policy: SVGResourcePolicy,
        parserOptions: SVGParserOptions,
        warnings: inout [SVGParseWarning]
    ) -> SVGGroup {
        var updated = group
        updated.children = group.children.map {
            resolve(
                element: $0,
                context: context,
                policy: policy,
                parserOptions: parserOptions,
                warnings: &warnings
            )
        }
        return updated
    }

    private static func resolve(
        element: SVGElement,
        context: SVGReferencedImageResolveContext,
        policy: SVGResourcePolicy,
        parserOptions: SVGParserOptions,
        warnings: inout [SVGParseWarning]
    ) -> SVGElement {
        switch element {
        case .image(var image):
            image.referencedDocument = loadReferencedSVGDocument(
                href: image.href,
                context: context,
                policy: policy,
                parserOptions: parserOptions,
                warnings: &warnings
            )
            return .image(image)
        case .group(let group):
            return .group(resolve(
                in: group,
                context: context,
                policy: policy,
                parserOptions: parserOptions,
                warnings: &warnings
            ))
        case .svg(var svg):
            svg.children = svg.children.map {
                resolve(
                    element: $0,
                    context: context,
                    policy: policy,
                    parserOptions: parserOptions,
                    warnings: &warnings
                )
            }
            return .svg(svg)
        default:
            return element
        }
    }

    private static func loadReferencedSVGDocument(
        href: String,
        context: SVGReferencedImageResolveContext,
        policy: SVGResourcePolicy,
        parserOptions: SVGParserOptions,
        warnings: inout [SVGParseWarning]
    ) -> SVGDocument? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch SVGHrefResolver.classify(href: trimmed, policy: policy) {
        case .dataURI(let uri):
            if parserOptions.limits.dataURIExceedsLimit(uri) {
                warnings.append(SVGParseWarning(
                    kind: .limitExceeded(kind: "maxDataURIBytes", line: nil),
                    message: "Parse limit exceeded: maxDataURIBytes"
                ))
                return nil
            }
            guard isSVGDataURI(uri),
                  let data = dataFromSVGDataURI(uri) else {
                return nil
            }
            return try? SVGParser(options: parserOptions).parseWithReport(data: data).document
        case .localFile(let fileURL):
            guard isSVGFileURL(fileURL) else { return nil }
            let standardized = fileURL.standardizedFileURL
            guard !isBlockedReference(standardized, context: context) else { return nil }
            return ExternalSVGDocumentLoader.document(
                at: standardized,
                parseBaseURL: standardized.deletingLastPathComponent(),
                parserOptions: parserOptions,
                parseContext: context.nestedLoad(of: standardized)
            )
        case .fragment:
            return nil
        case .rejected(let reason):
            warnings.append(SVGHrefResolver.parseWarning(href: trimmed, reason: reason))
            return nil
        }
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

    private static func isSVGFileURL(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "svg"
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
}

