import Foundation
import SVGCore

// MARK: - Post-parse `<use xlink:href="…svg#id">` resolution

enum SVGExternalUseResolver {

    static func resolve(
        definitions: inout [String: SVGElement],
        root: SVGGroup,
        context: SVGReferencedImageResolveContext,
        policy: SVGResourcePolicy,
        parserOptions: SVGParserOptions,
        warnings: inout [SVGParseWarning]
    ) {
        var needed: [String: Set<String>] = [:]
        collectExternalFragmentRefs(in: .group(root), into: &needed)

        for (sourceHref, fragmentIDs) in needed {
            let trimmed = sourceHref.trimmingCharacters(in: .whitespacesAndNewlines)
            switch SVGHrefResolver.classify(href: trimmed, policy: policy) {
            case .localFile(let fileURL):
                guard let fragment = fileURL.fragment, !fragment.isEmpty else { continue }
                guard fragmentIDs.contains(fragment) else { continue }
                let docURL = fileURL.standardizedFileURL
                guard !SVGReferencedImageResolver.isBlockedReference(docURL, context: context) else {
                    continue
                }
                guard let extDoc = ExternalSVGDocumentLoader.document(
                    at: docURL,
                    parseBaseURL: docURL.deletingLastPathComponent(),
                    parserOptions: parserOptions,
                    parseContext: context.nestedLoad(of: docURL)
                ) else {
                    continue
                }
                for id in fragmentIDs {
                    if definitions[id] == nil, let element = extDoc.definitions[id] {
                        definitions[id] = element
                    }
                }
            case .dataURI(let uri):
                guard let extDoc = loadDataURI(uri, parserOptions: parserOptions, warnings: &warnings)
                else { continue }
                for id in fragmentIDs {
                    if definitions[id] == nil, let element = extDoc.definitions[id] {
                        definitions[id] = element
                    }
                }
            case .fragment, .rejected:
                break
            }
        }
    }

    private static func collectExternalFragmentRefs(
        in element: SVGElement,
        into needed: inout [String: Set<String>]
    ) {
        switch element {
        case .use(let use):
            recordExternalRef(use, into: &needed)
        case .group(let group):
            for child in group.children {
                collectExternalFragmentRefs(in: child, into: &needed)
            }
        case .svg(let svg):
            for child in svg.children {
                collectExternalFragmentRefs(in: child, into: &needed)
            }
        default:
            break
        }
    }

    private static func recordExternalRef(_ use: SVGUse, into needed: inout [String: Set<String>]) {
        let trimmed = use.sourceHref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("#") else { return }
        needed[trimmed, default: []].insert(use.href)
    }

    private static func loadDataURI(
        _ uri: String,
        parserOptions: SVGParserOptions,
        warnings: inout [SVGParseWarning]
    ) -> SVGDocument? {
        guard uri.lowercased().hasPrefix("data:") else { return nil }
        let body = uri.dropFirst(5)
        guard let comma = body.firstIndex(of: ",") else { return nil }
        let metadata = body[..<comma].lowercased()
        guard metadata.hasPrefix("image/svg") else { return nil }
        if parserOptions.limits.dataURIExceedsLimit(uri) {
            warnings.append(SVGParseWarning(
                kind: .limitExceeded(kind: "maxDataURIBytes", line: nil),
                message: "Parse limit exceeded: maxDataURIBytes"
            ))
            return nil
        }
        let payload = String(body[body.index(after: comma)...])
        let data: Data?
        if metadata.hasSuffix(";base64") {
            data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
        } else {
            data = Data(payload.utf8)
        }
        guard let data else { return nil }
        return try? SVGParser(options: parserOptions).parseWithReport(data: data).document
    }
}
