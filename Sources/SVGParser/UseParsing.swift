import Foundation
import SVGCore

// MARK: - Post-parse `<use xlink:href="…svg#id">` resolution

enum SVGExternalUseResolver {

    static func resolve(
        definitions: inout [String: SVGElement],
        externalPaintServers: inout [String: [String: SVGPaintServer]],
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
            let scopeKey = paintServerScopeKey(from: trimmed)
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
                if externalPaintServers[scopeKey] == nil {
                    externalPaintServers[scopeKey] = extDoc.paintServers
                }
                for id in fragmentIDs {
                    if definitions[id] == nil, let element = extDoc.definitions[id] {
                        definitions[id] = remapExternalPaintScope(element, scopeKey: scopeKey)
                    }
                }
            case .dataURI(let uri):
                guard let extDoc = loadDataURI(uri, parserOptions: parserOptions, warnings: &warnings)
                else { continue }
                if externalPaintServers[scopeKey] == nil {
                    externalPaintServers[scopeKey] = extDoc.paintServers
                }
                for id in fragmentIDs {
                    if definitions[id] == nil, let element = extDoc.definitions[id] {
                        definitions[id] = remapExternalPaintScope(element, scopeKey: scopeKey)
                    }
                }
            case .fragment, .rejected:
                break
            }
        }
    }

    /// External href without fragment — keys `SVGDocument.externalPaintServers`.
    static func paintServerScopeKey(from sourceHref: String) -> String {
        let trimmed = sourceHref.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hash = trimmed.firstIndex(of: "#") {
            return String(trimmed[..<hash])
        }
        return trimmed
    }

    private static func remapExternalPaintScope(_ element: SVGElement, scopeKey: String) -> SVGElement {
        switch element {
        case .rect(var r):
            r.paint = remapPaintProperties(r.paint, scopeKey: scopeKey)
            return .rect(r)
        case .circle(var c):
            c.paint = remapPaintProperties(c.paint, scopeKey: scopeKey)
            return .circle(c)
        case .ellipse(var e):
            e.paint = remapPaintProperties(e.paint, scopeKey: scopeKey)
            return .ellipse(e)
        case .line(var l):
            l.paint = remapPaintProperties(l.paint, scopeKey: scopeKey)
            return .line(l)
        case .polyline(var p):
            p.paint = remapPaintProperties(p.paint, scopeKey: scopeKey)
            return .polyline(p)
        case .polygon(var p):
            p.paint = remapPaintProperties(p.paint, scopeKey: scopeKey)
            return .polygon(p)
        case .path(var p):
            p.paint = remapPaintProperties(p.paint, scopeKey: scopeKey)
            return .path(p)
        case .text(var t):
            t.paint = remapPaintProperties(t.paint, scopeKey: scopeKey)
            t.runs = t.runs.map { run in
                var updated = run
                updated.paint = remapPaintProperties(run.paint, scopeKey: scopeKey)
                return updated
            }
            return .text(t)
        case .image(var img):
            img.paint = remapPaintProperties(img.paint, scopeKey: scopeKey)
            return .image(img)
        case .group(var g):
            g.children = g.children.map { remapExternalPaintScope($0, scopeKey: scopeKey) }
            return .group(g)
        case .svg(var svg):
            svg.children = svg.children.map { remapExternalPaintScope($0, scopeKey: scopeKey) }
            return .svg(svg)
        case .use:
            return element
        }
    }

    private static func remapPaintProperties(
        _ paint: SVGPaintProperties,
        scopeKey: String
    ) -> SVGPaintProperties {
        var updated = paint
        updated.fill = remapPaintScope(paint.fill, scopeKey: scopeKey)
        updated.stroke = remapPaintScope(paint.stroke, scopeKey: scopeKey)
        return updated
    }

    private static func remapPaintScope(_ paint: SVGPaint, scopeKey: String) -> SVGPaint {
        switch paint {
        case .paintServer(let id, let fallback, _):
            return .paintServer(id: id, fallback: fallback, scope: .external(sourceKey: scopeKey))
        default:
            return paint
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
