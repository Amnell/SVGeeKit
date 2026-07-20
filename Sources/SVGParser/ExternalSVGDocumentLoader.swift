import Foundation
import SVGCore

/// Parsed SVG documents referenced by external `href`s (e.g. `<image href="…svg">`,
/// `<use xlink:href="other.svg#id">`), keyed by resolved file URL.
enum ExternalSVGDocumentLoader {
    private static let cache = Cache()

    static func document(
        at fileURL: URL,
        parseBaseURL: URL,
        parserOptions: SVGParserOptions,
        parseContext: SVGReferencedImageResolveContext
    ) -> SVGDocument? {
        cache.document(
            at: fileURL,
            parseBaseURL: parseBaseURL,
            parserOptions: parserOptions,
            parseContext: parseContext
        )
    }

    private final class Cache: @unchecked Sendable {
        private var storage: [URL: SVGDocument] = [:]
        private let lock = NSLock()

        func document(
            at fileURL: URL,
            parseBaseURL: URL,
            parserOptions: SVGParserOptions,
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
                  let extDoc = try? SVGParser(options: parserOptions).parse(
                    data: data,
                    options: .localFiles(at: parseBaseURL),
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
