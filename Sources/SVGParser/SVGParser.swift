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

    public func parse(data: Data) throws -> SVGDocument {
        let parser = XMLParser(data: data)
        let delegate = SAXDelegate()
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
        guard let document = delegate.document else {
            throw SVGParseError(kind: .missingRoot, line: nil, column: nil)
        }
        return document
    }

    public func parse(string: String) throws -> SVGDocument {
        try parse(data: Data(string.utf8))
    }
}

private final class SAXDelegate: NSObject, XMLParserDelegate {

    enum Axis { case x, y, length }

    var document: SVGDocument?
    var error: SVGParseError?

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
            groupStack.append(SVGGroup(transform: transform))
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
        guard !groupStack.isEmpty else { return }
        groupStack[groupStack.count - 1].children.append(element)
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

        // Inline `style="key:value;..."` first so presentation attributes win.
        if let style = attributes["style"] {
            for pair in style.split(separator: ";") {
                let parts = pair.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }
                applyPaintProperty(name: parts[0], value: parts[1], into: &p, parser: parser)
            }
        }
        for (key, value) in attributes {
            applyPaintProperty(name: key, value: value, into: &p, parser: parser)
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
            if let paint = AttributeParsers.color(value) { p.fill = paint }
        case "fill-opacity":
            if let d = Double(value) { p.fillOpacity = CGFloat(d) }
        case "fill-rule":
            if let rule = SVGFillRule(rawValue: value.trimmingCharacters(in: .whitespaces)) {
                p.fillRule = rule
            }
        case "stroke":
            if let paint = AttributeParsers.color(value) { p.stroke = paint }
        case "stroke-opacity":
            if let d = Double(value) { p.strokeOpacity = CGFloat(d) }
        case "stroke-width":
            if let len = AttributeParsers.length(value) { p.strokeWidth = len.resolved() }
        case "stroke-linecap":
            if let cap = SVGLineCap(rawValue: value) { p.lineCap = cap }
        case "stroke-linejoin":
            if let join = SVGLineJoin(rawValue: value) { p.lineJoin = join }
        case "stroke-miterlimit":
            if let d = Double(value) { p.miterLimit = CGFloat(d) }
        case "opacity":
            if let d = Double(value) { p.opacity = CGFloat(d) }
        default:
            break
        }
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
}
