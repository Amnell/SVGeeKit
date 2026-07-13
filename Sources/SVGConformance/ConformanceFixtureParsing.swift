import Foundation
import SVGCore
import SVGParser

/// Parse helpers for trusted on-disk fixtures (W3C corpus, Viewer, benchmarks).
public enum SVGConformanceFixtureParsing {

    /// Directory containing the SVG file — used for `../resources/` resolution.
    public static func localFilesBaseURL(for svgURL: URL) -> URL {
        svgURL.deletingLastPathComponent()
    }

    public static func localFilesOptions(for svgURL: URL) -> SVGParserOptions {
        .localFiles(at: localFilesBaseURL(for: svgURL))
    }

    public static func parser(for svgURL: URL) -> SVGParser {
        SVGParser(options: localFilesOptions(for: svgURL))
    }

    /// Parse a W3C (or other on-disk) fixture with explicit `.localFiles` policy.
    public static func parse(data: Data, svgURL: URL) throws -> SVGDocument {
        try parse(data: data, svgURL: svgURL, sourceURL: svgURL.standardizedFileURL)
    }

    /// Like `parse(data:svgURL:)` but supplies `sourceURL` for cyclic `<image>` detection.
    public static func parse(data: Data, svgURL: URL, sourceURL: URL) throws -> SVGDocument {
        let options = localFilesOptions(for: svgURL)
        return try SVGParser(options: options).parse(
            data: data,
            options: options,
            sourceURL: sourceURL
        )
    }

    /// Parse a file from disk with explicit `.localFiles` at its parent directory.
    public static func parse(url: URL) throws -> SVGDocument {
        let data = try Data(contentsOf: url)
        return try parse(data: data, svgURL: url, sourceURL: url.standardizedFileURL)
    }
}
