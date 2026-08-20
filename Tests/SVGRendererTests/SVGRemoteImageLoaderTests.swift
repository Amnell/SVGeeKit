import Foundation
import Testing
import SVGCore
import SVGParser
@testable import SVGRendererSwiftUI

@Suite("SVG remote image loading", .serialized)
struct SVGRemoteImageLoaderTests {
    private static let greenRectSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="20" height="10">
      <rect width="20" height="10" fill="lime"/>
    </svg>
    """

    @Test func loadsSVGFromFileURL() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("svgeekit-remote-\(UUID().uuidString).svg")
        try Data(Self.greenRectSVG.utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let document = try await SVGRemoteImageLoader.document(
            for: URLRequest(url: fileURL),
            session: .shared,
            options: .production,
            conditionalContext: .current()
        )
        #expect(document.root.children.count == 1)
    }

    @Test func loadsSVGFromHTTPStub() async throws {
        let url = URL(string: "https://svg-image-view.test/icon.svg")!
        let session = StubURLProtocol.session(
            url: url,
            statusCode: 200,
            data: Data(Self.greenRectSVG.utf8)
        )
        defer { session.finishTasksAndInvalidate() }

        let document = try await SVGRemoteImageLoader.document(
            for: URLRequest(url: url),
            session: session,
            options: .production,
            conditionalContext: .current()
        )
        #expect(document.root.children.count == 1)
    }

    @Test func forwardsURLRequestHeaders() async throws {
        let url = URL(string: "https://svg-image-view.test/auth.svg")!
        let session = StubURLProtocol.session(
            url: url,
            statusCode: 200,
            data: Data(Self.greenRectSVG.utf8)
        )
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url)
        request.setValue("Bearer test-token", forHTTPHeaderField: "Authorization")
        _ = try await SVGRemoteImageLoader.document(
            for: request,
            session: session,
            options: .production,
            conditionalContext: .current()
        )
        #expect(StubURLProtocol.authorizationHeader(for: url) == "Bearer test-token")
    }

    @Test func rejectsHTTPErrorStatus() async {
        let url = URL(string: "https://svg-image-view.test/missing.svg")!
        let session = StubURLProtocol.session(
            url: url,
            statusCode: 404,
            data: Data("not found".utf8)
        )
        defer { session.finishTasksAndInvalidate() }

        await #expect(throws: SVGRemoteImageError.httpStatus(404)) {
            _ = try await SVGRemoteImageLoader.document(
                for: URLRequest(url: url),
                session: session,
                options: .production,
            conditionalContext: .current()
            )
        }
    }

    @Test func rejectsInvalidSVGBytes() async {
        let url = URL(string: "https://svg-image-view.test/not-svg.svg")!
        let session = StubURLProtocol.session(
            url: url,
            statusCode: 200,
            data: Data("not svg".utf8)
        )
        defer { session.finishTasksAndInvalidate() }

        await #expect(throws: SVGParseError.self) {
            _ = try await SVGRemoteImageLoader.document(
                for: URLRequest(url: url),
                session: session,
                options: .production,
            conditionalContext: .current()
            )
        }
    }

    @Test func validateAcceptsNonHTTPResponses() throws {
        let response = URLResponse(
            url: URL(fileURLWithPath: "/tmp/icon.svg"),
            mimeType: "image/svg+xml",
            expectedContentLength: 8,
            textEncodingName: nil
        )
        try SVGRemoteImageLoader.validate(response)
    }

    @Test func validateAcceptsHTTPSuccess() throws {
        let url = URL(string: "https://svg-image-view.test/ok.svg")!
        let response = HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: nil)!
        try SVGRemoteImageLoader.validate(response)
    }

    @Test func validateRejectsHTTPFailure() {
        let url = URL(string: "https://svg-image-view.test/fail.svg")!
        let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
        #expect(throws: SVGRemoteImageError.httpStatus(500)) {
            try SVGRemoteImageLoader.validate(response)
        }
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private struct Stub: Sendable {
        var statusCode: Int
        var data: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs: [URL: Stub] = [:]
    nonisolated(unsafe) private static var authorizationHeaders: [URL: String] = [:]

    static func session(url: URL, statusCode: Int, data: Data) -> URLSession {
        lock.lock()
        stubs[url] = Stub(statusCode: statusCode, data: data)
        authorizationHeaders[url] = nil
        lock.unlock()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }

    static func authorizationHeader(for url: URL) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return authorizationHeaders[url]
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let url = request.url
        let authorization = request.value(forHTTPHeaderField: "Authorization")
        Self.lock.lock()
        if let url { Self.authorizationHeaders[url] = authorization }
        let stub = url.flatMap { Self.stubs[$0] }
        Self.lock.unlock()

        guard let url, let stub, let client else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/svg+xml"]
        )!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: stub.data)
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
