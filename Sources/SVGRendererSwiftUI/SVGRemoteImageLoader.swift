import Foundation
import SVGCore
import SVGParser

/// Fetches SVG bytes for `SVGImageView`'s URL initializers and parses them with the
/// caller-supplied parser options (production policy by default — no in-document network `href`).
enum SVGRemoteImageLoader {
    static func data(
        for request: URLRequest,
        session: URLSession
    ) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return data
    }

    static func document(
        for request: URLRequest,
        session: URLSession,
        options: SVGParserOptions,
        conditionalContext: SVGConditionalProcessingContext
    ) async throws -> SVGDocument {
        let data = try await data(for: request, session: session)
        return try await Task.detached(priority: .userInitiated) {
            try SVGParser(conditionalContext: conditionalContext, options: options).parse(data: data)
        }.value
    }

    static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw SVGRemoteImageError.httpStatus(http.statusCode)
        }
    }
}
