import CoreGraphics
import Foundation
import SVGCore

/// Parses SVG XML data into an `SVGDocument`.
///
/// Today's scope (Phase 1): `<svg>` root with `viewBox`/`width`/`height`,
/// nested `<g>` groups with `transform`, and `<rect>` shapes with basic painting.
/// New element handling lives in `SAXDelegate.didStartElement(...)`.
public struct SVGParser {

    public init() {}

    public func parse(data: Data, baseURL: URL? = nil) throws -> SVGDocument {
        let parser = XMLParser(data: data)
        let delegate = SAXDelegate(baseURL: baseURL)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false

        if !parser.parse() {
            if let error = delegate.error { throw error }
            if let xmlErr = parser.parserError {
                throw SVGParseError(
                    kind: .xml(xmlErr.localizedDescription),
                    line: parser.lineNumber,
                    column: parser.columnNumber
                )
            }
        }
        if let error = delegate.error { throw error }
        guard var document = delegate.document else {
            throw SVGParseError(kind: .missingRoot, line: nil, column: nil)
        }
        delegate.resolveGradientHrefs()
        delegate.resolvePendingFontHrefs()
        document.baseURL = baseURL
        document.paintServers = delegate.paintServers
        document.clipPaths = delegate.clipPaths
        document.masks = delegate.masks
        document.fonts = delegate.fonts
        document.fontFaces = delegate.fontFaces
        return document
    }

    public func parse(string: String, baseURL: URL? = nil) throws -> SVGDocument {
        try parse(data: Data(string.utf8), baseURL: baseURL)
    }

    /// Reads `url` and parses with `baseURL` set to the file's parent directory.
    public func parse(url: URL) throws -> SVGDocument {
        let data = try Data(contentsOf: url)
        return try parse(data: data, baseURL: url.deletingLastPathComponent())
    }

    /// Async convenience: runs the synchronous `parse(data:baseURL:)` on a detached
    /// task at `userInitiated` priority so callers on the main actor don't
    /// block their thread on large SVG files.
    public static func parse(data: Data, baseURL: URL? = nil) async throws -> SVGDocument {
        try await Task.detached(priority: .userInitiated) {
            try SVGParser().parse(data: data, baseURL: baseURL)
        }.value
    }

    /// Async convenience that reads `url` and parses, both off the main actor.
    public static func parse(url: URL) async throws -> SVGDocument {
        try await Task.detached(priority: .userInitiated) {
            try SVGParser().parse(url: url)
        }.value
    }
}

struct PartialCSSFontFace {
    var family: String?
    var uris: [String] = []
    var names: [String] = []
}

struct PartialSVGFont {
    var id: String?
    var defaultAdvance: CGFloat = 0
    var unitsPerEm: CGFloat = 1000
    var ascent: CGFloat = 800
    var descent: CGFloat = -200
    var glyphs: [Unicode.Scalar: SVGGlyph] = [:]
    var missingGlyph: SVGGlyph?
}

final class SAXDelegate: NSObject, XMLParserDelegate {

    enum Axis { case x, y, length }

    let baseURL: URL?

    var document: SVGDocument?
    var error: SVGParseError?

    init(baseURL: URL? = nil) {
        self.baseURL = baseURL
    }

    /// Viewport (in user-space units) used to resolve `%` lengths. Set when
    /// the root `<svg>` is opened: prefers viewBox, then width/height.
    private var viewport: CGSize = .zero

    /// Stack of partially-built groups. Top of stack receives new children.
    private var groupStack: [SVGGroup] = []
    /// Inherited paint properties for cascading down the tree.
    private var paintStack: [SVGPaintProperties] = [SVGPaintProperties()]
    /// Inherited font / text-anchor properties (cascade through <g> and <text>).
    private var fontStack: [SVGFont] = [SVGFont()]
    /// Partially-built <text> elements. Character data is appended to the top
    /// while a text capture is active (including text inside nested <tspan>).
    private var textStack: [SVGText] = []

    /// Partial linearGradient definitions currently open. Top receives `<stop>`s.
    private var gradientStack: [PartialGradient] = []
    /// Completed paint servers keyed by id.
    fileprivate var paintServers: [String: SVGPaintServer] = [:]
    /// xlink:href deferrals: gradients that referenced another paint server.
    /// Resolved in a final pass once the whole document has been parsed.
    private var gradientHrefs: [(id: String, href: String)] = []

    /// Partial `<clipPath>` definitions currently open.
    private var clipPathStack: [PartialClipPath] = []
    /// Completed clip paths keyed by id.
    fileprivate var clipPaths: [String: SVGClipPath] = [:]

    /// Partial `<mask>` definitions currently open.
    private var maskStack: [PartialMask] = []
    /// Completed masks keyed by id.
    fileprivate var masks: [String: SVGMask] = [:]

    /// SVG `<font id="…">` tables and CSS `<font-face>` bindings.
    var fonts: [String: SVGFontDefinition] = [:]
    var fontFaces: [SVGFontFace] = []
    var cssFontFaceStack: [PartialCSSFontFace] = []
    var svgFontStack: [PartialSVGFont] = []
    var pendingFontHrefs: [String] = []

    struct PartialGradient {
        enum Kind { case linear, radial }
        var kind: Kind = .linear
        var id: String?
        var href: String?
        // linear
        var x1: CGFloat?
        var y1: CGFloat?
        var x2: CGFloat?
        var y2: CGFloat?
        // radial
        var cx: CGFloat?
        var cy: CGFloat?
        var fx: CGFloat?
        var fy: CGFloat?
        var r: CGFloat?
        var units: SVGGradientUnits?
        var spreadMethod: SVGGradientSpread?
        var transform: SVGTransform?
        var stops: [SVGGradientStop] = []
    }

    struct PartialClipPath {
        var id: String?
        var units: SVGClipPath.Units = .userSpaceOnUse
        var transform: SVGTransform = .identity
        var children: [SVGElement] = []
    }

    struct PartialMask {
        var id: String?
        var maskUnits: SVGMask.Units = .objectBoundingBox
        var maskContentUnits: SVGMask.Units = .userSpaceOnUse
        var x: CGFloat?
        var y: CGFloat?
        var width: CGFloat?
        var height: CGFloat?
        var children: [SVGElement] = []
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let inheritedPaint = paintStack.last ?? SVGPaintProperties()
        let elementPaint = mergePaint(into: inheritedPaint, from: attributeDict, parser: parser)
        paintStack.append(elementPaint)

        let inheritedFont = fontStack.last ?? SVGFont()
        let elementFont = mergeFont(into: inheritedFont, from: attributeDict)
        fontStack.append(elementFont)

        switch elementName {
        case "svg":
            handleSVGRoot(attributes: attributeDict, parser: parser)
        case "g":
            let transform = transform(from: attributeDict, parser: parser) ?? .identity
            let clipRef = parseClipPathRef(attributeDict)
            let maskR = parseMaskRef(attributeDict)
            groupStack.append(SVGGroup(transform: transform, opacity: elementPaint.opacity, clipPathRef: clipRef, maskRef: maskR))
        case "rect":
            handleRect(attributes: attributeDict, paint: elementPaint, parser: parser)
        case "circle":
            handleCircle(attributes: attributeDict, paint: elementPaint, parser: parser)
        case "ellipse":
            handleEllipse(attributes: attributeDict, paint: elementPaint, parser: parser)
        case "line":
            handleLine(attributes: attributeDict, paint: elementPaint, parser: parser)
        case "polyline":
            handlePolyline(attributes: attributeDict, paint: elementPaint, parser: parser)
        case "polygon":
            handlePolygon(attributes: attributeDict, paint: elementPaint, parser: parser)
        case "path":
            handlePath(attributes: attributeDict, paint: elementPaint, parser: parser)
        case "text":
            handleTextStart(
                attributes: attributeDict, paint: elementPaint, font: elementFont, parser: parser
            )
        case "tspan":
            // No standalone positioning today: tspan content is appended to the
            // active <text> via foundCharacters. Drop the call here so the
            // tspan's character data isn't double-counted in didEnd handling.
            break
        case "linearGradient":
            handleLinearGradientStart(attributes: attributeDict)
        case "radialGradient":
            handleRadialGradientStart(attributes: attributeDict)
        case "stop":
            handleStop(attributes: attributeDict, currentColor: elementPaint.color)
        case "clipPath":
            handleClipPathStart(attributes: attributeDict, parser: parser)
        case "mask":
            handleMaskStart(attributes: attributeDict)
        case "font-face" where !svgFontStack.isEmpty:
            handleSVGFontFaceMetrics(attributes: attributeDict)
        case "font-face":
            handleCSSFontFaceStart(attributes: attributeDict)
        case "font-face-uri":
            handleFontFaceURI(attributes: attributeDict)
        case "font-face-name":
            handleFontFaceName(attributes: attributeDict)
        case "font":
            handleSVGFontStart(attributes: attributeDict)
        case "glyph":
            handleGlyph(attributes: attributeDict, missing: false)
        case "missing-glyph":
            handleGlyph(attributes: attributeDict, missing: true)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !textStack.isEmpty else { return }
        textStack[textStack.count - 1].string.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        paintStack.removeLast()
        fontStack.removeLast()

        switch elementName {
        case "svg":
            guard let root = groupStack.popLast() else { return }
            document?.root = root
        case "g":
            guard let finished = groupStack.popLast() else { return }
            appendChild(.group(finished))
        case "text":
            guard var finished = textStack.popLast() else { return }
            finished.string = SAXDelegate.collapseTextWhitespace(finished.string)
            appendChild(.text(finished))
        case "linearGradient":
            finalizeLinearGradient()
        case "radialGradient":
            finalizeRadialGradient()
        case "clipPath":
            finalizeClipPath()
        case "mask":
            finalizeMask()
        case "font-face" where !svgFontStack.isEmpty:
            break
        case "font-face":
            finalizeCSSFontFace()
        case "font":
            finalizeSVGFont()
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if error == nil {
            error = SVGParseError(
                kind: .xml(parseError.localizedDescription),
                line: parser.lineNumber,
                column: parser.columnNumber
            )
        }
    }

    // MARK: - Element handlers

    private func handleSVGRoot(attributes: [String: String], parser: XMLParser) {
        let viewBox = attributes["viewBox"].flatMap { AttributeParsers.viewBox($0) }
        let width = attributes["width"].flatMap { AttributeParsers.length($0)?.resolved() }
        let height = attributes["height"].flatMap { AttributeParsers.length($0)?.resolved() }

        let intrinsic: CGSize? = {
            if let w = width, let h = height { return CGSize(width: w, height: h) }
            if let vb = viewBox { return vb.size }
            return nil
        }()

        if let vb = viewBox {
            viewport = vb.size
        } else if let w = width, let h = height {
            viewport = CGSize(width: w, height: h)
        }

        document = SVGDocument(viewBox: viewBox, intrinsicSize: intrinsic, root: SVGGroup())
        groupStack.append(SVGGroup())
    }
    /// Resolves a length attribute against the current viewport. Percentages on
    /// the x/y axes use the viewport's width/height; "length" axis percentages
    /// use the SVG 1.1 normalized diagonal sqrt((w² + h²) / 2). em/ex resolve
    /// against the current font-size (ex ≈ 0.5em per SVG 1.1 fallback).
    private func resolveLength(_ raw: String?, axis: Axis, default fallback: CGFloat = 0) -> CGFloat {
        guard let raw, let len = AttributeParsers.length(raw) else { return fallback }
        switch len.unit {
        case .percent:
            let basis: CGFloat
            switch axis {
            case .x: basis = viewport.width
            case .y: basis = viewport.height
            case .length:
                let w = viewport.width, h = viewport.height
                basis = (w == 0 && h == 0) ? 0 : sqrt((w * w + h * h) / 2)
            }
            return len.value * basis / 100
        case .em:
            return len.value * (fontStack.last?.size ?? 16)
        case .ex:
            return len.value * (fontStack.last?.size ?? 16) * 0.5
        default:
            return len.resolved()
        }
    }

    private func handleRect(attributes: [String: String], paint: SVGPaintProperties, parser: XMLParser) {
        let x = resolveLength(attributes["x"], axis: .x)
        let y = resolveLength(attributes["y"], axis: .y)
        let w = resolveLength(attributes["width"], axis: .x)
        let h = resolveLength(attributes["height"], axis: .y)
        let rx = attributes["rx"].map { resolveLength($0, axis: .x) }
        let ry = attributes["ry"].map { resolveLength($0, axis: .y) }

        let radii: CGSize
        switch (rx, ry) {
        case (nil, nil): radii = .zero
        case (let v?, nil): radii = CGSize(width: v, height: v)
        case (nil, let v?): radii = CGSize(width: v, height: v)
        case (let a?, let b?): radii = CGSize(width: a, height: b)
        }

        let rect = SVGRect(
            origin: CGPoint(x: x, y: y),
            size: CGSize(width: w, height: h),
            cornerRadii: radii,
            paint: paint,
            transform: transform(from: attributes, parser: parser) ?? .identity
        )
        appendChild(.rect(rect))
    }

    private func handleCircle(attributes: [String: String], paint: SVGPaintProperties, parser: XMLParser) {
        let cx = resolveLength(attributes["cx"], axis: .x)
        let cy = resolveLength(attributes["cy"], axis: .y)
        let r = resolveLength(attributes["r"], axis: .length)
        let circle = SVGCircle(
            center: CGPoint(x: cx, y: cy),
            radius: r,
            paint: paint,
            transform: transform(from: attributes, parser: parser) ?? .identity
        )
        appendChild(.circle(circle))
    }

    private func handleEllipse(attributes: [String: String], paint: SVGPaintProperties, parser: XMLParser) {
        let cx = resolveLength(attributes["cx"], axis: .x)
        let cy = resolveLength(attributes["cy"], axis: .y)
        let rx = resolveLength(attributes["rx"], axis: .x)
        let ry = resolveLength(attributes["ry"], axis: .y)
        let ellipse = SVGEllipse(
            center: CGPoint(x: cx, y: cy),
            radii: CGSize(width: rx, height: ry),
            paint: paint,
            transform: transform(from: attributes, parser: parser) ?? .identity
        )
        appendChild(.ellipse(ellipse))
    }

    private func handleLine(attributes: [String: String], paint: SVGPaintProperties, parser: XMLParser) {
        let x1 = resolveLength(attributes["x1"], axis: .x)
        let y1 = resolveLength(attributes["y1"], axis: .y)
        let x2 = resolveLength(attributes["x2"], axis: .x)
        let y2 = resolveLength(attributes["y2"], axis: .y)
        let line = SVGLine(
            start: CGPoint(x: x1, y: y1),
            end: CGPoint(x: x2, y: y2),
            paint: paint,
            transform: transform(from: attributes, parser: parser) ?? .identity
        )
        appendChild(.line(line))
    }

    private func handlePolyline(attributes: [String: String], paint: SVGPaintProperties, parser: XMLParser) {
        let pts = attributes["points"].flatMap { AttributeParsers.points($0) } ?? []
        let polyline = SVGPolyline(
            points: pts,
            paint: paint,
            transform: transform(from: attributes, parser: parser) ?? .identity
        )
        appendChild(.polyline(polyline))
    }

    private func handlePolygon(attributes: [String: String], paint: SVGPaintProperties, parser: XMLParser) {
        let pts = attributes["points"].flatMap { AttributeParsers.points($0) } ?? []
        let polygon = SVGPolygon(
            points: pts,
            paint: paint,
            transform: transform(from: attributes, parser: parser) ?? .identity
        )
        appendChild(.polygon(polygon))
    }

    private func handlePath(attributes: [String: String], paint: SVGPaintProperties, parser: XMLParser) {
        guard let raw = attributes["d"],
              let commands = PathDataParser.parse(raw),
              !commands.isEmpty else { return }
        let path = SVGPath(
            commands: commands,
            paint: paint,
            transform: transform(from: attributes, parser: parser) ?? .identity
        )
        appendChild(.path(path))
    }

    private func handleTextStart(
        attributes: [String: String],
        paint: SVGPaintProperties,
        font: SVGFont,
        parser: XMLParser
    ) {
        let x = resolveLength(attributes["x"], axis: .x)
        let y = resolveLength(attributes["y"], axis: .y)
        let text = SVGText(
            origin: CGPoint(x: x, y: y),
            string: "",
            font: font,
            paint: paint,
            transform: transform(from: attributes, parser: parser) ?? .identity
        )
        textStack.append(text)
    }

    // MARK: - Helpers

    private func appendChild(_ element: SVGElement) {
        if !clipPathStack.isEmpty {
            clipPathStack[clipPathStack.count - 1].children.append(element)
        } else if !maskStack.isEmpty {
            maskStack[maskStack.count - 1].children.append(element)
        } else {
            guard !groupStack.isEmpty else { return }
            groupStack[groupStack.count - 1].children.append(element)
        }
    }

    private func transform(from attributes: [String: String], parser: XMLParser) -> SVGTransform? {
        guard let raw = attributes["transform"] else { return nil }
        if let parsed = AttributeParsers.transform(raw) { return parsed }
        if error == nil {
            error = SVGParseError(
                kind: .malformedAttribute(name: "transform", value: raw, reason: "could not parse"),
                line: parser.lineNumber,
                column: parser.columnNumber
            )
        }
        return nil
    }

    private func mergePaint(
        into inherited: SVGPaintProperties,
        from attributes: [String: String],
        parser: XMLParser
    ) -> SVGPaintProperties {
        var p = inherited

        // Collect (name, value) declarations from `style="..."` first then
        // attributes, so style is the lower-priority source like SVG 1.1
        // presentation attributes.
        var declarations: [(String, String)] = []
        if let style = attributes["style"] {
            for pair in style.split(separator: ";") {
                let parts = pair.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }
                declarations.append((parts[0], parts[1]))
            }
        }
        for (key, value) in attributes where key != "style" {
            declarations.append((key, value))
        }

        // Two passes: `color` first (so `fill="currentColor"` can resolve
        // against it on the same element), then everything else.
        for (name, value) in declarations where name == "color" {
            applyPaintProperty(name: name, value: value, into: &p, parser: parser)
        }
        for (name, value) in declarations where name != "color" {
            applyPaintProperty(name: name, value: value, into: &p, parser: parser)
        }
        return p
    }

    private func applyPaintProperty(
        name: String,
        value: String,
        into p: inout SVGPaintProperties,
        parser: XMLParser
    ) {
        switch name {
        case "fill":
            if let paint = resolvePaint(value, currentColor: p.color) { p.fill = paint }
        case "fill-opacity":
            if let d = Double(value) { p.fillOpacity = CGFloat(min(1, max(0, d))) }
        case "fill-rule":
            if let rule = SVGFillRule(rawValue: value.trimmingCharacters(in: .whitespaces)) {
                p.fillRule = rule
            }
        case "stroke":
            if let paint = resolvePaint(value, currentColor: p.color) { p.stroke = paint }
        case "stroke-opacity":
            if let d = Double(value) { p.strokeOpacity = CGFloat(min(1, max(0, d))) }
        case "stroke-width":
            if let len = AttributeParsers.length(value) { p.strokeWidth = len.resolved() }
        case "stroke-linecap":
            if let cap = SVGLineCap(rawValue: value) { p.lineCap = cap }
        case "stroke-linejoin":
            if let join = SVGLineJoin(rawValue: value) { p.lineJoin = join }
        case "stroke-miterlimit":
            if let d = Double(value) { p.miterLimit = CGFloat(d) }
        case "stroke-dasharray":
            p.strokeDashArray = parseDashArray(value)
        case "stroke-dashoffset":
            if let len = AttributeParsers.length(value) { p.strokeDashOffset = len.resolved() }
        case "opacity":
            if let d = Double(value) { p.opacity = CGFloat(min(1, max(0, d))) }
        case "color":
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased() == "currentcolor" { return } // no-op
            if case .color(let c) = AttributeParsers.color(trimmed) ?? .none {
                p.color = c
            }
        case "visibility":
            if let v = SVGVisibility(rawValue: value.trimmingCharacters(in: .whitespaces).lowercased()) {
                p.visibility = v
            }
        case "clip-path":
            if let ref = parseClipPathRef(["clip-path": value]) {
                p.clipPathRef = ref
            }
        case "mask":
            if let ref = parseMaskRef(["mask": value]) {
                p.maskRef = ref
            }
        default:
            break
        }
    }

    /// Resolves a paint value, expanding `currentColor` and `url(#id)`
    /// references (SVG 1.1 §13.2 / §12.2). Server lookup is deferred to
    /// render-tree lowering; here we just record the reference id.
    private func resolvePaint(_ raw: String, currentColor: SVGColor) -> SVGPaint? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.caseInsensitiveCompare("currentColor") == .orderedSame {
            return .color(currentColor)
        }
        if trimmed.lowercased().hasPrefix("url(") {
            let body = trimmed.dropFirst(4)
            guard let close = body.firstIndex(of: ")") else { return nil }
            var ref = String(body[..<close]).trimmingCharacters(in: .whitespaces)
            ref = ref.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            if ref.hasPrefix("#") { ref = String(ref.dropFirst()) }
            guard !ref.isEmpty else { return nil }
            return .paintServer(id: ref)
        }
        return AttributeParsers.color(trimmed)
    }

    private func mergeFont(into inherited: SVGFont, from attributes: [String: String]) -> SVGFont {
        var f = inherited
        if let style = attributes["style"] {
            for pair in style.split(separator: ";") {
                let parts = pair.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }
                applyFontProperty(name: parts[0], value: parts[1], into: &f)
            }
        }
        for (key, value) in attributes {
            applyFontProperty(name: key, value: value, into: &f)
        }
        return f
    }

    private func applyFontProperty(name: String, value: String, into f: inout SVGFont) {
        switch name {
        case "font-family":
            f.family = value.trimmingCharacters(in: .whitespaces)
        case "font-size":
            if let len = AttributeParsers.length(value) { f.size = len.resolved() }
        case "font-weight":
            if let w = SVGFontWeight.parse(value) { f.weight = w }
        case "text-anchor":
            if value == "inherit" { return }
            if let a = SVGTextAnchor(rawValue: value) { f.anchor = a }
        default:
            break
        }
    }

    /// SVG's xml:space="default" behaviour: collapse runs of whitespace and
    /// trim leading/trailing. We don't implement xml:space="preserve" yet.
    static func collapseTextWhitespace(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    // MARK: - Paint servers

    fileprivate func handleLinearGradientStart(attributes: [String: String]) {
        var p = PartialGradient()
        p.id = attributes["id"]
        p.href = attributes["xlink:href"] ?? attributes["href"]
        p.x1 = attributes["x1"].flatMap { AttributeParsers.length($0)?.resolved() }
        p.y1 = attributes["y1"].flatMap { AttributeParsers.length($0)?.resolved() }
        p.x2 = attributes["x2"].flatMap { AttributeParsers.length($0)?.resolved() }
        p.y2 = attributes["y2"].flatMap { AttributeParsers.length($0)?.resolved() }
        if let u = attributes["gradientUnits"]?.trimmingCharacters(in: .whitespaces),
           let units = SVGGradientUnits(rawValue: u) {
            p.units = units
        }
        if let s = attributes["spreadMethod"]?.trimmingCharacters(in: .whitespaces),
           let spread = SVGGradientSpread(rawValue: s) {
            p.spreadMethod = spread
        }
        if let raw = attributes["gradientTransform"],
           let t = AttributeParsers.transform(raw) {
            p.transform = t
        }
        gradientStack.append(p)
    }

    fileprivate func handleStop(attributes: [String: String], currentColor: SVGColor) {
        guard !gradientStack.isEmpty else { return }

        // style="..." wins over presentation attributes (CSS specificity).
        var props: [String: String] = attributes
        if let style = attributes["style"] {
            for pair in style.split(separator: ";") {
                let parts = pair.split(separator: ":", maxSplits: 1)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }
                props[parts[0]] = parts[1]
            }
        }

        let offset: CGFloat = {
            guard let raw = props["offset"]?.trimmingCharacters(in: .whitespaces) else { return 0 }
            if raw.hasSuffix("%"), let d = Double(raw.dropLast()) { return CGFloat(d / 100) }
            return CGFloat(Double(raw) ?? 0)
        }()
        var color = SVGColor(red: 0, green: 0, blue: 0)
        if let raw = props["stop-color"]?.trimmingCharacters(in: .whitespaces) {
            if raw.caseInsensitiveCompare("currentColor") == .orderedSame {
                color = currentColor
            } else if case .color(let c) = AttributeParsers.color(raw) ?? .none {
                color = c
            }
        }
        if let raw = props["stop-opacity"], let d = Double(raw) {
            color.alpha *= CGFloat(min(1, max(0, d)))
        }
        gradientStack[gradientStack.count - 1].stops.append(
            SVGGradientStop(offset: max(0, min(1, offset)), color: color)
        )
    }

    // MARK: - Masks

    private func handleMaskStart(attributes: [String: String]) {
        var partial = PartialMask()
        partial.id = attributes["id"]
        if let raw = attributes["maskUnits"], let u = SVGMask.Units(rawValue: raw) {
            partial.maskUnits = u
        }
        if let raw = attributes["maskContentUnits"], let u = SVGMask.Units(rawValue: raw) {
            partial.maskContentUnits = u
        }
        let axis: Axis = partial.maskUnits == .objectBoundingBox ? .length : .x
        partial.x = attributes["x"].map { resolveLength($0, axis: axis) }
        partial.y = attributes["y"].map { resolveLength($0, axis: axis) }
        partial.width = attributes["width"].map { resolveLength($0, axis: axis) }
        partial.height = attributes["height"].map { resolveLength($0, axis: axis) }
        maskStack.append(partial)
    }

    private func finalizeMask() {
        guard let partial = maskStack.popLast(), let id = partial.id else { return }
        masks[id] = SVGMask(
            maskUnits: partial.maskUnits,
            maskContentUnits: partial.maskContentUnits,
            x: partial.x,
            y: partial.y,
            width: partial.width,
            height: partial.height,
            children: partial.children
        )
    }

    /// Parses a `mask="url(#id)"` attribute and returns the bare id, or `nil`.
    private func parseMaskRef(_ attributes: [String: String]) -> String? {
        guard let raw = attributes["mask"] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("url(") else { return nil }
        let body = trimmed.dropFirst(4)
        guard let close = body.firstIndex(of: ")") else { return nil }
        var ref = String(body[..<close]).trimmingCharacters(in: .whitespaces)
        ref = ref.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        if ref.hasPrefix("#") { ref = String(ref.dropFirst()) }
        return ref.isEmpty ? nil : ref
    }

    // MARK: - Clip paths

    private func handleClipPathStart(attributes: [String: String], parser: XMLParser) {
        var partial = PartialClipPath()
        partial.id = attributes["id"]
        if let u = attributes["clipPathUnits"]?.trimmingCharacters(in: .whitespaces),
           let units = SVGClipPath.Units(rawValue: u) {
            partial.units = units
        }
        if let t = transform(from: attributes, parser: parser) {
            partial.transform = t
        }
        clipPathStack.append(partial)
    }

    private func finalizeClipPath() {
        guard let partial = clipPathStack.popLast(), let id = partial.id else { return }
        let clipPath = SVGClipPath(
            units: partial.units,
            transform: partial.transform,
            children: partial.children
        )
        clipPaths[id] = clipPath
    }

    /// Parses a `clip-path="url(#id)"` attribute and returns the bare id, or `nil`.
    private func parseClipPathRef(_ attributes: [String: String]) -> String? {
        guard let raw = attributes["clip-path"] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("url(") else { return nil }
        let body = trimmed.dropFirst(4)
        guard let close = body.firstIndex(of: ")") else { return nil }
        var ref = String(body[..<close]).trimmingCharacters(in: .whitespaces)
        ref = ref.trimmingCharacters(in: CharacterSet(charactersIn: "'\"" ))
        if ref.hasPrefix("#") { ref = String(ref.dropFirst()) }
        return ref.isEmpty ? nil : ref
    }

    fileprivate func handleRadialGradientStart(attributes: [String: String]) {
        var p = PartialGradient()
        p.kind = .radial
        p.id = attributes["id"]
        p.href = attributes["xlink:href"] ?? attributes["href"]
        p.cx = attributes["cx"].flatMap { AttributeParsers.length($0)?.resolved() }
        p.cy = attributes["cy"].flatMap { AttributeParsers.length($0)?.resolved() }
        p.fx = attributes["fx"].flatMap { AttributeParsers.length($0)?.resolved() }
        p.fy = attributes["fy"].flatMap { AttributeParsers.length($0)?.resolved() }
        p.r  = attributes["r"].flatMap  { AttributeParsers.length($0)?.resolved() }
        if let u = attributes["gradientUnits"]?.trimmingCharacters(in: .whitespaces),
           let units = SVGGradientUnits(rawValue: u) {
            p.units = units
        }
        if let s = attributes["spreadMethod"]?.trimmingCharacters(in: .whitespaces),
           let spread = SVGGradientSpread(rawValue: s) {
            p.spreadMethod = spread
        }
        if let raw = attributes["gradientTransform"],
           let t = AttributeParsers.transform(raw) {
            p.transform = t
        }
        gradientStack.append(p)
    }

    fileprivate func finalizeRadialGradient() {
        guard let p = gradientStack.popLast(), let id = p.id else { return }
        let gradient = SVGRadialGradient(
            cx: p.cx ?? 0.5,
            cy: p.cy ?? 0.5,
            fx: p.fx,
            fy: p.fy,
            r: p.r ?? 0.5,
            units: p.units ?? .objectBoundingBox,
            spreadMethod: p.spreadMethod ?? .pad,
            stops: p.stops,
            transform: p.transform ?? .identity
        )
        paintServers[id] = .radialGradient(gradient)
        if var href = p.href {
            if href.hasPrefix("#") { href = String(href.dropFirst()) }
            gradientHrefs.append((id: id, href: href))
        }
    }

    fileprivate func finalizeLinearGradient() {
        guard let p = gradientStack.popLast(), let id = p.id else { return }
        let gradient = SVGLinearGradient(
            x1: p.x1 ?? 0,
            y1: p.y1 ?? 0,
            x2: p.x2 ?? 1,
            y2: p.y2 ?? 0,
            units: p.units ?? .objectBoundingBox,
            spreadMethod: p.spreadMethod ?? .pad,
            stops: p.stops,
            transform: p.transform ?? .identity
        )
        paintServers[id] = .linearGradient(gradient)
        if var href = p.href {
            if href.hasPrefix("#") { href = String(href.dropFirst()) }
            gradientHrefs.append((id: id, href: href))
        }
    }

    /// Resolve gradient `xlink:href` chains and merge attributes / stops
    /// per SVG 1.1 §13.2.2: child's own values win; parent supplies the rest.
    fileprivate func resolveGradientHrefs() {
        // Repeat-until-stable to handle chains parent←child←grandchild.
        var changed = true
        var iterations = 0
        while changed && iterations < 16 {
            changed = false
            iterations += 1
            for (id, href) in gradientHrefs {
                guard let childServer = paintServers[id],
                      let parentServer = paintServers[href] else { continue }
                switch (childServer, parentServer) {
                case (.linearGradient(let child), .linearGradient(let parent)):
                    let merged = SVGLinearGradient(
                        x1: child.x1, y1: child.y1, x2: child.x2, y2: child.y2,
                        units: child.units, spreadMethod: child.spreadMethod,
                        stops: child.stops.isEmpty ? parent.stops : child.stops,
                        transform: child.transform
                    )
                    if merged != child { paintServers[id] = .linearGradient(merged); changed = true }
                case (.radialGradient(let child), .radialGradient(let parent)):
                    let merged = SVGRadialGradient(
                        cx: child.cx, cy: child.cy, fx: child.fx, fy: child.fy, r: child.r,
                        units: child.units, spreadMethod: child.spreadMethod,
                        stops: child.stops.isEmpty ? parent.stops : child.stops,
                        transform: child.transform
                    )
                    if merged != child { paintServers[id] = .radialGradient(merged); changed = true }
                case (.radialGradient(let child), .linearGradient(let parent)):
                    // Inherit stops from linear parent into radial child.
                    if child.stops.isEmpty {
                        var merged = child; merged.stops = parent.stops
                        paintServers[id] = .radialGradient(merged); changed = true
                    }
                case (.linearGradient(let child), .radialGradient(let parent)):
                    // Inherit stops from radial parent into linear child.
                    if child.stops.isEmpty {
                        var merged = child; merged.stops = parent.stops
                        paintServers[id] = .linearGradient(merged); changed = true
                    }
                }
            }
        }
    }

    /// Parse `stroke-dasharray` per SVG 1.1: "none" → empty; comma/whitespace
    /// list of lengths. Odd-length lists are repeated by the renderer per spec
    /// (CG already cycles whatever pattern we hand it, so we mirror once).
    private func parseDashArray(_ raw: String) -> [CGFloat] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "none" { return [] }
        let parts = trimmed.split { $0 == " " || $0 == "," || $0 == "\t" || $0 == "\n" }
        var out: [CGFloat] = []
        out.reserveCapacity(parts.count)
        for p in parts {
            guard let len = AttributeParsers.length(String(p)) else { return [] }
            let v = len.resolved()
            if v < 0 { return [] }
            out.append(v)
        }
        if out.count % 2 == 1 { out.append(contentsOf: out) }
        return out
    }
}
