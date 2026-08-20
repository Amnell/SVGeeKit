import Foundation

/// Failures that occur while `SVGImageView` fetches SVG bytes from a `URL` / `URLRequest`.
///
/// Parse failures still surface as `SVGParseError`. The view never throws — these values
/// are reported through the optional `parseError` binding.
public enum SVGRemoteImageError: Error, Equatable, Sendable {
    /// The HTTP response status was outside the 2xx success range.
    case httpStatus(Int)
}

extension SVGRemoteImageError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .httpStatus(let code):
            return "The server returned HTTP \(code)."
        }
    }
}
