import CoreGraphics
import Foundation
import SVGCore

// MARK: - External font file cache

/// Parsed `<font>` tables from external SVG files, keyed by resolved file URL.
/// Conformance runs hundreds of tests in parallel that all reference
/// `SVGFreeSans.svg`; caching avoids re-parsing that file on every test.
private enum ExternalFontCache {
    private static let cache = Cache()

    static func fonts(at fileURL: URL, parseBaseURL: URL) -> [String: SVGFontDefinition]? {
        cache.fonts(at: fileURL, parseBaseURL: parseBaseURL)
    }

    private final class Cache: @unchecked Sendable {
        private var storage: [URL: [String: SVGFontDefinition]] = [:]
        private let lock = NSLock()

        func fonts(at fileURL: URL, parseBaseURL: URL) -> [String: SVGFontDefinition]? {
            let key = fileURL.standardizedFileURL
            lock.lock()
            if let cached = storage[key] {
                lock.unlock()
                return cached
            }
            lock.unlock()

            guard let data = try? Data(contentsOf: key),
                  let extDoc = try? SVGParser().parse(data: data, baseURL: parseBaseURL) else {
                return nil
            }

            let fonts = extDoc.fonts
            lock.lock()
            storage[key] = fonts
            lock.unlock()
            return fonts
        }
    }
}

// MARK: - Font parsing (SVG 1.1 `<font>` / CSS `<font-face>`)

extension SAXDelegate {

    func handleCSSFontFaceStart(attributes: [String: String]) {
        var partial = PartialCSSFontFace()
        if let raw = attributes["font-family"] {
            partial.family = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        }
        cssFontFaceStack.append(partial)
    }

    func handleFontFaceURI(attributes: [String: String]) {
        guard let href = attributes["xlink:href"] ?? attributes["href"] else { return }
        guard !cssFontFaceStack.isEmpty else { return }
        cssFontFaceStack[cssFontFaceStack.count - 1].uris.append(href)
    }

    func handleFontFaceName(attributes: [String: String]) {
        guard let raw = attributes["name"] else { return }
        guard !cssFontFaceStack.isEmpty else { return }
        cssFontFaceStack[cssFontFaceStack.count - 1].names.append(raw)
    }

    func finalizeCSSFontFace() {
        guard let partial = cssFontFaceStack.popLast(),
              let family = partial.family else { return }

        for uri in partial.uris {
            pendingFontHrefs.append(uri)
        }

        let fontID: String? = {
            for uri in partial.uris {
                if let id = Self.fontID(fromHref: uri) { return id }
            }
            return partial.names.first
        }()
        guard let fontID else { return }
        fontFaces.append(SVGFontFace(family: family, fontID: fontID))
    }

    func handleSVGFontStart(attributes: [String: String]) {
        var partial = PartialSVGFont()
        partial.id = attributes["id"]
        if let raw = attributes["horiz-adv-x"], let n = Double(raw) {
            partial.defaultAdvance = CGFloat(n)
        }
        svgFontStack.append(partial)
    }

    func handleSVGFontFaceMetrics(attributes: [String: String]) {
        guard !svgFontStack.isEmpty else { return }
        var partial = svgFontStack.removeLast()
        if let raw = attributes["units-per-em"], let n = Double(raw) {
            partial.unitsPerEm = CGFloat(n)
        }
        if let raw = attributes["ascent"], let n = Double(raw) {
            partial.ascent = CGFloat(n)
        }
        if let raw = attributes["descent"], let n = Double(raw) {
            partial.descent = CGFloat(n)
        }
        svgFontStack.append(partial)
    }

    func handleGlyph(attributes: [String: String], missing: Bool) {
        guard !svgFontStack.isEmpty else { return }
        let defaultAdvance = svgFontStack[svgFontStack.count - 1].defaultAdvance
        let advance: CGFloat = attributes["horiz-adv-x"]
            .flatMap { Double($0) }
            .map { CGFloat($0) }
            ?? defaultAdvance
        let commands = attributes["d"].flatMap { PathDataParser.parse($0) }
        let glyph = SVGGlyph(commands: commands, advance: advance)

        if missing {
            svgFontStack[svgFontStack.count - 1].missingGlyph = glyph
            return
        }

        guard let raw = attributes["unicode"],
              let scalar = AttributeParsers.glyphUnicode(raw) else { return }
        svgFontStack[svgFontStack.count - 1].glyphs[scalar] = glyph
    }

    func finalizeSVGFont() {
        guard let partial = svgFontStack.popLast(), let id = partial.id else { return }
        fonts[id] = SVGFontDefinition(
            unitsPerEm: partial.unitsPerEm,
            ascent: partial.ascent,
            descent: partial.descent,
            defaultAdvance: partial.defaultAdvance,
            glyphs: partial.glyphs,
            missingGlyph: partial.missingGlyph
        )
    }

    func resolvePendingFontHrefs() {
        for href in pendingFontHrefs {
            loadExternalFont(href: href)
        }
        pendingFontHrefs.removeAll()
    }

    func loadExternalFont(href: String) {
        guard let fontID = Self.fontID(fromHref: href) else { return }
        guard fonts[fontID] == nil else { return }

        let resolver = SVGDocument(baseURL: baseURL)
        guard let resolved = resolver.resolveURL(href) else { return }
        let (fileURL, fragment) = Self.splitFragment(resolved)

        let parseBase = fileURL.deletingLastPathComponent()
        guard let extFonts = ExternalFontCache.fonts(at: fileURL, parseBaseURL: parseBase) else {
            return
        }

        for (id, def) in extFonts where fonts[id] == nil {
            fonts[id] = def
        }
        if let fragment, fonts[fontID] == nil, let def = extFonts[fragment] {
            fonts[fontID] = def
        }
    }

    static func fontID(fromHref href: String) -> String? {
        let trimmed = href.trimmingCharacters(in: .whitespaces)
        guard let hash = trimmed.firstIndex(of: "#") else { return nil }
        let id = String(trimmed[trimmed.index(after: hash)...])
            .trimmingCharacters(in: .whitespaces)
        return id.isEmpty ? nil : id
    }

    static func splitFragment(_ url: URL) -> (URL, String?) {
        guard let fragment = url.fragment, !fragment.isEmpty else {
            return (url, nil)
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        let base = components?.url ?? url
        return (base, fragment)
    }
}
