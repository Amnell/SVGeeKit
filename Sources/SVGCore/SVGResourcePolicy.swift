import Foundation

/// Controls which `href` / `xlink:href` targets may be loaded during parse and render.
public enum SVGResourcePolicy: Sendable, Equatable {
    /// Production default. Same-document `#fragment` refs and `data:` URIs only.
    case restricted
    /// Conformance, Viewer, and local file workflows. Relative paths resolve under `baseURL`.
    /// Network schemes (`http:`, `https:`) are never allowed.
    case localFiles(baseURL: URL)
}

/// How recoverable parse problems are surfaced. Hard XML failures always throw.
public enum SVGFailurePolicy: Sendable, Equatable {
    /// Soft failures become `SVGParseWarning` entries; parsing continues.
    case warnAndContinue
    /// Unit tests only. The first soft failure also throws from `parseThrowing` helpers.
    case throwOnWarning
}

/// Bomb-protection limits applied during parse. Exceeding a limit is a soft failure unless
/// `failurePolicy` is `.throwOnWarning`.
public struct SVGParsingLimits: Sendable, Equatable {
    public var maxDocumentBytes: Int
    public var maxElementCount: Int
    public var maxPathCommands: Int
    public var maxNestingDepth: Int
    public var maxDataURIBytes: Int
    public var maxDefinitions: Int

    public init(
        maxDocumentBytes: Int = 4 * 1024 * 1024,
        maxElementCount: Int = 50_000,
        maxPathCommands: Int = 500_000,
        maxNestingDepth: Int = 256,
        maxDataURIBytes: Int = 2 * 1024 * 1024,
        maxDefinitions: Int = 10_000
    ) {
        self.maxDocumentBytes = maxDocumentBytes
        self.maxElementCount = maxElementCount
        self.maxPathCommands = maxPathCommands
        self.maxNestingDepth = maxNestingDepth
        self.maxDataURIBytes = maxDataURIBytes
        self.maxDefinitions = maxDefinitions
    }

    public static let `default` = SVGParsingLimits()

    /// Estimated decoded payload size for a `data:` URI (without fully decoding base64).
    public func estimatedDataURIPayloadByteCount(_ uri: String) -> Int? {
        guard uri.lowercased().hasPrefix("data:") else { return nil }
        let body = uri.dropFirst(5)
        guard let comma = body.firstIndex(of: ",") else { return nil }
        let metadata = body[..<comma].lowercased()
        let payload = body[body.index(after: comma)...]
        if metadata.hasSuffix(";base64") {
            let padding = payload.suffix(2).filter { $0 == "=" }.count
            return max(0, (payload.count * 3) / 4 - padding)
        }
        return payload.utf8.count
    }

    public func dataURIExceedsLimit(_ uri: String) -> Bool {
        guard let bytes = estimatedDataURIPayloadByteCount(uri) else { return true }
        return bytes > maxDataURIBytes
    }
}

/// Parser configuration. Defaults to production-safe resource loading.
public struct SVGParserOptions: Sendable, Equatable {
    public var resourcePolicy: SVGResourcePolicy
    public var failurePolicy: SVGFailurePolicy
    public var limits: SVGParsingLimits

    public init(
        resourcePolicy: SVGResourcePolicy = .restricted,
        failurePolicy: SVGFailurePolicy = .warnAndContinue,
        limits: SVGParsingLimits = .default
    ) {
        self.resourcePolicy = resourcePolicy
        self.failurePolicy = failurePolicy
        self.limits = limits
    }

    /// Untrusted input — network assets, user uploads, CMS content.
    public static let production = SVGParserOptions()

    /// W3C corpus, Viewer, benchmarks. Caller supplies the SVG file's parent directory.
    public static func localFiles(at baseURL: URL) -> SVGParserOptions {
        SVGParserOptions(
            resourcePolicy: .localFiles(baseURL: baseURL),
            failurePolicy: .warnAndContinue,
            limits: .default
        )
    }

    /// First soft warning throws — for unit tests only.
    public static let testingStrict = SVGParserOptions(
        resourcePolicy: .restricted,
        failurePolicy: .throwOnWarning,
        limits: .default
    )
}
