import Foundation

/// Classifies `href` / `xlink:href` values against `SVGResourcePolicy`.
public enum SVGHrefResolver {

    public enum Resolution: Equatable, Sendable {
        case fragment(String)
        case dataURI(String)
        case localFile(URL)
        case rejected(SVGHrefRejectionReason)
    }

    public static func classify(href: String, policy: SVGResourcePolicy) -> Resolution {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .rejected(.emptyReference) }

        if let fragment = fragmentID(from: trimmed) {
            return .fragment(fragment)
        }

        let normalized = stripURLFunctionalNotation(trimmed)

        if normalized.lowercased().hasPrefix("data:") {
            return .dataURI(normalized)
        }

        if let fragment = fragmentID(from: normalized) {
            return .fragment(fragment)
        }

        if let scheme = URL(string: normalized)?.scheme?.lowercased() {
            switch scheme {
            case "http", "https":
                return .rejected(.networkScheme)
            case "file":
                guard case .localFiles(let baseURL) = policy else {
                    return .rejected(.restrictedPolicy)
                }
                guard let fileURL = URL(string: normalized)?.standardizedFileURL else {
                    return .rejected(.externalReference)
                }
                guard isContained(fileURL, in: baseURL) else {
                    return .rejected(.pathTraversal)
                }
                return .localFile(fileURL)
            default:
                return .rejected(.externalReference)
            }
        }

        guard case .localFiles(let baseURL) = policy else {
            return .rejected(.restrictedPolicy)
        }

        let (pathPart, fragmentPart) = splitFragment(normalized)
        guard !pathPart.isEmpty else {
            return fragmentPart.map { .fragment($0) } ?? .rejected(.emptyReference)
        }

        guard var resolved = URL(string: pathPart, relativeTo: baseURL)?.standardizedFileURL else {
            return .rejected(.externalReference)
        }

        if let fragmentPart {
            var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false)
            components?.fragment = fragmentPart
            resolved = components?.url ?? resolved
        }

        guard isContained(resolved, in: baseURL) else {
            return .rejected(.pathTraversal)
        }

        return .localFile(resolved)
    }

    /// Resolves a relative `href` against `effectiveBase`, then rewrites it as a
    /// path relative to `documentBase` (so later classification still uses the
    /// document resource policy). Absolute schemes (`data:`, `http:`, …) and
    /// same-document fragments are returned unchanged.
    public static func resolveHref(
        _ href: String,
        documentBase: URL,
        effectiveBase: URL
    ) -> String {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.hasPrefix("#") || trimmed.lowercased().hasPrefix("data:") {
            return trimmed
        }
        if let scheme = URL(string: trimmed)?.scheme, !scheme.isEmpty {
            return trimmed
        }
        guard let absolute = URL(string: trimmed, relativeTo: effectiveBase)?.standardizedFileURL else {
            return trimmed
        }
        return filePath(relativeTo: documentBase, from: absolute) ?? trimmed
    }

    /// XML Base (RFC 3986): resolve `xml:base` against the parent base URI.
    /// Trailing `/` is preserved as a directory base for subsequent relative hrefs.
    public static func resolveXMLBase(_ raw: String, relativeTo parent: URL) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let resolved = URL(string: trimmed, relativeTo: parent)?.absoluteURL.standardizedFileURL else {
            return nil
        }
        if trimmed.hasSuffix("/") || resolved.hasDirectoryPath {
            return URL(fileURLWithPath: resolved.path, isDirectory: true)
        }
        return resolved
    }

    /// File path of `target` relative to directory `base` (e.g. `../images/a.png`).
    public static func filePath(relativeTo base: URL, from target: URL) -> String? {
        let baseParts = base.standardizedFileURL.pathComponents
        let targetParts = target.standardizedFileURL.pathComponents
        var shared = 0
        while shared < baseParts.count,
              shared < targetParts.count,
              baseParts[shared] == targetParts[shared] {
            shared += 1
        }
        let ups = Array(repeating: "..", count: baseParts.count - shared)
        let downs = Array(targetParts[shared...])
        let parts = ups + downs
        return parts.isEmpty ? "." : parts.joined(separator: "/")
    }

    public static func parseWarning(
        href: String,
        reason: SVGHrefRejectionReason,
        line: Int? = nil
    ) -> SVGParseWarning {
        let detail: String = switch reason {
        case .emptyReference: "empty href"
        case .networkScheme: "network URLs are not allowed"
        case .externalReference: "external reference is not allowed under the active resource policy"
        case .pathTraversal: "resolved path escapes the allowed base directory"
        case .restrictedPolicy: "external file references are disabled in production mode"
        }
        return SVGParseWarning(
            kind: .rejectedExternalReference(href: href, reason: reason, line: line),
            message: "Rejected href \"\(href)\": \(detail)"
        )
    }

    // MARK: - Private

    private static func fragmentID(from href: String) -> String? {
        let trimmed = stripURLFunctionalNotation(href)
        guard trimmed.hasPrefix("#") else { return nil }
        let id = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }

    private static func stripURLFunctionalNotation(_ href: String) -> String {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("url("), trimmed.hasSuffix(")") else {
            return trimmed
        }
        var inner = trimmed.dropFirst(4).dropLast()
        if (inner.hasPrefix("\"") && inner.hasSuffix("\"")) || (inner.hasPrefix("'") && inner.hasSuffix("'")) {
            inner = inner.dropFirst().dropLast()
        }
        return String(inner).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitFragment(_ href: String) -> (String, String?) {
        guard let hash = href.firstIndex(of: "#") else { return (href, nil) }
        let pathPart = String(href[..<hash])
        let fragment = String(href[href.index(after: hash)...])
        return (pathPart, fragment.isEmpty ? nil : fragment)
    }

    /// Allows resolved files in `baseURL` or its parent directory (e.g. W3C `svg/`
    /// + `../resources/`). Rejects paths that escape that two-level sandbox.
    private static func isContained(_ url: URL, in baseURL: URL) -> Bool {
        let resolved = url.standardizedFileURL
        let base = baseURL.standardizedFileURL
        let sandbox = base.deletingLastPathComponent().standardizedFileURL

        for root in [base, sandbox] {
            if resolved.path == root.path { return true }
            let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
            if resolved.path.hasPrefix(rootPath) { return true }
        }
        return false
    }
}
