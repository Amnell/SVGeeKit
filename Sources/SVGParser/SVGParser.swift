import CoreGraphics
import Foundation
import SVGCore

/// Parses SVG XML data into an `SVGDocument`.
///
/// Today's scope (Phase 1): `<svg>` root with `viewBox`/`width`/`height`,
/// nested `<g>` groups with `transform`, and `<rect>` shapes with basic painting.
/// New element handling lives in `SAXDelegate.didStartElement(...)`.
public struct SVGParser {
    public var options: SVGParserOptions
    public var conditionalContext: SVGConditionalProcessingContext

    public init(options: SVGParserOptions = .production) {
        self.options = options
        self.conditionalContext = .current()
    }

    public init(conditionalContext: SVGConditionalProcessingContext, options: SVGParserOptions = .production) {
        self.options = options
        self.conditionalContext = conditionalContext
    }

    public init(conditionalContext: SVGConditionalProcessingContext) {
        self.options = .production
        self.conditionalContext = conditionalContext
    }

    /// Parses SVG bytes and returns the document with any soft-failure warnings.
    public func parseWithReport(data: Data) throws -> SVGParseResult {
        try parseResult(data: data, resolvedOptions: options, sourceURL: nil, referencedImageContext: nil)
    }

    /// Parses with explicit options (overrides the parser's default `options`).
    public func parse(data: Data, options: SVGParserOptions) throws -> SVGParseResult {
        try parseResult(data: data, resolvedOptions: options, sourceURL: nil, referencedImageContext: nil)
    }

    /// Document-only parse with explicit options and optional `sourceURL` for cyclic `<image>` detection.
    public func parse(
        data: Data,
        options: SVGParserOptions,
        sourceURL: URL?
    ) throws -> SVGDocument {
        try parseResult(
            data: data,
            resolvedOptions: options,
            sourceURL: sourceURL,
            referencedImageContext: nil
        ).document
    }

    public func parseWithReport(string: String) throws -> SVGParseResult {
        try parseWithReport(data: Data(string.utf8))
    }

    /// Parses SVG bytes under the parser's configured `options` (`.production` by default).
    public func parse(data: Data) throws -> SVGDocument {
        try parseWithReport(data: data).document
    }

    /// Parses an SVG string under the parser's configured `options` (`.production` by default).
    public func parse(string: String) throws -> SVGDocument {
        try parse(data: Data(string.utf8))
    }

    func parse(
        data: Data,
        options: SVGParserOptions,
        sourceURL: URL?,
        referencedImageContext: SVGReferencedImageResolveContext?
    ) throws -> SVGDocument {
        try parseResult(
            data: data,
            resolvedOptions: options,
            sourceURL: sourceURL,
            referencedImageContext: referencedImageContext
        ).document
    }

    /// Reads `url` and parses with explicit `.localFiles` at the file's parent directory.
    ///
    /// Dev / test convenience for on-disk fixtures. Production callers should use
    /// `parse(data:)` with `.production` or `SVGConformanceFixtureParsing` for W3C files.
    public func parse(url: URL) throws -> SVGDocument {
        let data = try Data(contentsOf: url)
        let base = url.deletingLastPathComponent()
        let options = SVGParserOptions.localFiles(at: base)
        return try parse(
            data: data,
            options: options,
            sourceURL: url.standardizedFileURL,
            referencedImageContext: nil
        )
    }

    /// Async convenience: runs the synchronous `parse(data:)` on a detached task at
    /// `userInitiated` priority so callers on the main actor don't block on large SVG files.
    public static func parse(data: Data, options: SVGParserOptions = .production) async throws -> SVGDocument {
        try await Task.detached(priority: .userInitiated) {
            try SVGParser(options: options).parse(data: data)
        }.value
    }

    /// Async convenience that reads `url` and parses, both off the main actor.
    ///
    /// Uses explicit `.localFiles` at the file's parent directory (see `parse(url:)`).
    public static func parse(url: URL) async throws -> SVGDocument {
        try await Task.detached(priority: .userInitiated) {
            try SVGParser().parse(url: url)
        }.value
    }

    private func parseResult(
        data: Data,
        resolvedOptions: SVGParserOptions,
        sourceURL: URL?,
        referencedImageContext: SVGReferencedImageResolveContext?
    ) throws -> SVGParseResult {
        if data.count > resolvedOptions.limits.maxDocumentBytes {
            let warning = SVGParseWarning(
                kind: .limitExceeded(kind: "maxDocumentBytes", line: nil),
                message: "Parse limit exceeded: maxDocumentBytes"
            )
            if resolvedOptions.failurePolicy == .throwOnWarning {
                throw SVGParseError(kind: .policyViolation(warning.message), line: nil, column: nil)
            }
            let document = SVGDocument(
                resourcePolicy: resolvedOptions.resourcePolicy,
                parsingLimits: resolvedOptions.limits
            )
            return SVGParseResult(document: document, report: SVGParseReport(warnings: [warning]))
        }

        let importCSS = Self.cssImportLoader(for: resolvedOptions.resourcePolicy)
        let preloadedStylesheet = CSSStylesheetCollector.collect(from: data, importCSS: importCSS)
        let parser = XMLParser(data: data)
        let delegate = SAXDelegate(
            options: resolvedOptions,
            conditionalContext: conditionalContext,
            preloadedStylesheet: preloadedStylesheet,
            stylesPreloaded: !preloadedStylesheet.isEmpty
        )
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
        delegate.resolvePatternHrefs()
        try delegate.resolvePendingFontHrefs()
        document.resourcePolicy = resolvedOptions.resourcePolicy
        document.parsingLimits = resolvedOptions.limits
        document.baseURL = Self.baseURL(for: resolvedOptions.resourcePolicy)
        let resolveContext = referencedImageContext
            ?? SVGReferencedImageResolveContext.topLevel(sourceURL: sourceURL)
        var warnings = delegate.parseWarnings
        SVGReferencedImageResolver.resolve(
            in: &document,
            context: resolveContext,
            policy: resolvedOptions.resourcePolicy,
            parserOptions: resolvedOptions,
            warnings: &warnings
        )
        var definitions = delegate.definitions
        var externalPaintServers: [String: [String: SVGPaintServer]] = [:]
        SVGExternalUseResolver.resolve(
            definitions: &definitions,
            externalPaintServers: &externalPaintServers,
            root: document.root,
            context: resolveContext,
            policy: resolvedOptions.resourcePolicy,
            parserOptions: resolvedOptions,
            warnings: &warnings
        )
        document.paintServers = delegate.paintServers
        document.externalPaintServers = externalPaintServers
        document.clipPaths = delegate.clipPaths
        document.masks = delegate.masks
        document.colorProfiles = delegate.colorProfiles
        document.fonts = delegate.fonts
        document.fontFaces = delegate.fontFaces
        document.definitions = definitions
        document.scriptMetadata = delegate.scriptMetadata
        document.scriptMetadata.elementIndex = SVGDocument.buildElementIndex(root: document.root)
        document.animationMetadata = delegate.animationMetadata
        return SVGParseResult(document: document, report: SVGParseReport(warnings: warnings))
    }

    private static func cssImportLoader(for policy: SVGResourcePolicy) -> ((String) -> String?)? {
        guard case .localFiles = policy else { return nil }
        return { href in
            switch SVGHrefResolver.classify(href: href, policy: policy) {
            case .localFile(let url):
                return try? String(contentsOf: url, encoding: .utf8)
            default:
                return nil
            }
        }
    }

    private static func baseURL(for policy: SVGResourcePolicy) -> URL? {
        if case .localFiles(let baseURL) = policy { return baseURL }
        return nil
    }
}

struct PartialCSSFontFace {
    var family: String?
    var uris: [String] = []
    var names: [String] = []
    var weight: SVGFontWeight?
    var style: SVGFontStyle?
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

    let options: SVGParserOptions
    let conditionalContext: SVGConditionalProcessingContext

    var document: SVGDocument?
    var error: SVGParseError?
    var parseWarnings: [SVGParseWarning] = []

    private var resourcePolicy: SVGResourcePolicy { options.resourcePolicy }
    private var failurePolicy: SVGFailurePolicy { options.failurePolicy }
    private var baseURL: URL? {
        if case .localFiles(let url) = options.resourcePolicy { return url }
        return nil
    }

    struct SwitchCandidate {
        var attributes: [String: String]
        var element: SVGElement
    }

    struct PartialSwitch {
        var candidates: [SwitchCandidate] = []
        /// Nesting depth of the direct-child element currently being built.
        var childNestingDepth: Int = 0
        var pendingAttributes: [String: String] = [:]
    }

    /// Open `<switch>` elements collecting conditional children.
    private var switchStack: [PartialSwitch] = []

    private var elementCount = 0
    private var xmlNestingDepth = 0
    /// When > 0, elements are ignored until the subtree closes.
    private var skipSubtreeDepth = 0
    private var warnedElementCount = false
    private var warnedNestingDepth = false
    private var warnedDefinitionLimit = false

    init(
        options: SVGParserOptions = .production,
        conditionalContext: SVGConditionalProcessingContext = .current(),
        preloadedStylesheet: CSSStylesheet = CSSStylesheet(),
        stylesPreloaded: Bool = false
    ) {
        self.options = options
        self.conditionalContext = conditionalContext
        self.stylesheet = preloadedStylesheet
        self.stylesPreloaded = stylesPreloaded
    }

    func recordWarning(_ warning: SVGParseWarning) {
        parseWarnings.append(warning)
        if failurePolicy == .throwOnWarning, error == nil {
            error = SVGParseError(kind: .policyViolation(warning.message), line: nil, column: nil)
        }
    }

    private func recordLimitExceeded(_ kind: String, line: Int?) {
        recordWarning(SVGParseWarning(
            kind: .limitExceeded(kind: kind, line: line),
            message: "Parse limit exceeded: \(kind)"
        ))
    }

    private func beginParsingElement(_ parser: XMLParser) -> Bool {
        elementCount += 1
        xmlNestingDepth += 1

        if skipSubtreeDepth > 0 {
            skipSubtreeDepth += 1
            return false
        }

        let limits = options.limits
        if elementCount > limits.maxElementCount {
            if !warnedElementCount {
                warnedElementCount = true
                recordLimitExceeded("maxElementCount", line: parser.lineNumber)
            }
            skipSubtreeDepth = 1
            return false
        }
        if xmlNestingDepth > limits.maxNestingDepth {
            if !warnedNestingDepth {
                warnedNestingDepth = true
                recordLimitExceeded("maxNestingDepth", line: parser.lineNumber)
            }
            skipSubtreeDepth = 1
            return false
        }
        return true
    }

    /// Skip elements whose conditional-processing attributes fail — including
    /// entire subtrees when a parent fails (`struct-cond-overview-04-f`).
    /// `<switch>` children are still collected and evaluated in `finalizeSwitch`.
    private func shouldSkipForConditionalProcessing(
        elementName: String,
        attributes: [String: String]
    ) -> Bool {
        if elementName == "switch" { return false }
        if !switchStack.isEmpty { return false }
        let hasTest =
            attributes["requiredFeatures"] != nil
            || attributes["requiredExtensions"] != nil
            || attributes["requiredFormats"] != nil
            || attributes["systemLanguage"] != nil
        guard hasTest else { return false }
        return !SVGConditionalProcessing.evaluate(
            attributes: attributes,
            context: conditionalContext
        )
    }

    private func endParsingElement() {
        xmlNestingDepth -= 1
        if skipSubtreeDepth > 0 {
            skipSubtreeDepth -= 1
        }
    }

    /// Viewport (in user-space units) used to resolve `%` lengths. Set when
    /// the root `<svg>` is opened: prefers viewBox, then width/height.
    private var viewport: CGSize = .zero
    /// Saved parent viewports while a nested `<svg>` is open.
    private var viewportStack: [CGSize] = []
    /// Nesting depth of `<svg>` elements (1 = root).
    private var svgNestingDepth: Int = 0
    /// Partial nested `<svg>` elements currently open.
    private var svgStack: [PartialSVGElement] = []

    /// Stack of partially-built groups. Top of stack receives new children.
    private var groupStack: [SVGGroup] = []
    /// Inherited paint properties for cascading down the tree.
    private var paintStack: [SVGPaintProperties] = [SVGPaintProperties()]
    /// Paint property names set by presentation attributes, CSS, or inline `style` on the current element.
    private var specifiedPaintKeysStack: [Set<String>] = [[]]
    /// Inherited font / text-anchor properties (cascade through <g> and <text>).
    private var fontStack: [SVGFont] = [SVGFont()]
    /// Partially-built <text> elements. Character data is appended to the top
    /// while a text capture is active (including text inside nested <tspan>).
    private var textStack: [SVGText] = []
    private var activeTextRun: SVGTextRun?
    /// Font/paint stack for nested `<tspan>` inheritance.
    private var tspanStyleStack: [(SVGFont, SVGPaintProperties)] = []
    /// `rotate` list consumption stack; new frame when `<tspan rotate>` opens.
    private var rotateStack: [RotateCursor] = []
    private var rotatePushStack: [Bool] = []
    /// Per-segment metadata and root rotate list for deferred assignment at `</text>`.
    private var textRootRotate: [CGFloat] = []
    private var textSegmentMeta: [TextSegmentMeta] = []
    private var pendingRotateFrame: [CGFloat]?
    /// Inherited baseline `y` stack for nested `<tspan>` elements.
    private var tspanBaselineYStack: [CGFloat] = []
    /// `xml:space="preserve"` on the current `<text>` element.
    private var textPreserveSpaceStack: [Bool] = []

    /// Partial linearGradient definitions currently open. Top receives `<stop>`s.
    private var gradientStack: [PartialGradient] = []
    /// Completed paint servers keyed by id.
    fileprivate var paintServers: [String: SVGPaintServer] = [:]
    /// xlink:href deferrals: gradients that referenced another paint server.
    /// Resolved in a final pass once the whole document has been parsed.
    private var gradientHrefs: [(id: String, href: String)] = []
    /// Which gradient attributes were explicitly set (vs parser defaults) per id.
    private var gradientExplicitAttrs: [String: Set<String>] = [:]

    /// Partial `<pattern>` definitions currently open.
    private var patternStack: [PartialPattern] = []
    /// Patterns keyed by id, merged via xlink:href before materialization.
    private var pendingPatterns: [String: PartialPattern] = [:]
    private var patternHrefs: [(id: String, href: String)] = []

    /// Partial `<clipPath>` definitions currently open.
    private var clipPathStack: [PartialClipPath] = []
    /// Completed clip paths keyed by id.
    fileprivate var clipPaths: [String: SVGClipPath] = [:]

    /// Partial `<mask>` definitions currently open.
    private var maskStack: [PartialMask] = []
    /// Completed masks keyed by id.
    fileprivate var masks: [String: SVGMask] = [:]
    /// ICC color profiles keyed by `name` / `id`.
    fileprivate var colorProfiles: [String: SVGColorProfile] = [:]

    /// Nesting depth of `<defs>` — content here is not part of the render tree.
    private var defsDepth: Int = 0
    /// `<g>` / `<symbol>` opened inside `<defs>` — their children are kept for definitions.
    private var definitionContainerDepth: Int = 0

    /// `id` attributes for groups currently being parsed (legacy stack; id is stored on `SVGGroup`).
    private var groupIdStack: [String?] = []
    /// Open XML element metadata for CSS selector matching.
    private var cssElementStack: [CSSNodeContext] = []
    /// Completed direct children for each open XML element.
    private var cssChildStack: [[CSSNodeContext]] = []

    /// Elements with `id` inside `<defs>`, keyed for `<use>` resolution.
    fileprivate var definitions: [String: SVGElement] = [:]

    /// SVG `<font id="…">` tables and CSS `<font-face>` bindings.
    var fonts: [String: SVGFontDefinition] = [:]
    var fontFaces: [SVGFontFace] = []
    var cssFontFaceStack: [PartialCSSFontFace] = []
    var svgFontStack: [PartialSVGFont] = []
    var pendingFontHrefs: [String] = []

    /// Author stylesheet rules from `<style type="text/css">` elements.
    private var stylesheet = CSSStylesheet()
    /// When true, stylesheet was pre-scanned and inline `<style>` blocks are not re-appended.
    private let stylesPreloaded: Bool
    /// Character data buffer while a `<style>` element is open.
    private var styleTextBuffer: String?

    /// Inline `<script>` capture.
    private var scriptTextBuffer: String?
    private var scriptType: String?
    fileprivate var scriptMetadata = SVGScriptMetadata()
    fileprivate var animationMetadata = SVGAnimationMetadata()

    private struct PendingAnimatable {
        var element: SVGElement
        var animations: [SVGTimedAnimation]
        var definitionID: String?
    }

    private var pendingAnimatable: PendingAnimatable?
    private var groupAnimationStack: [[SVGTimedAnimation]] = []
    private var rootAnimationBuffer: [SVGTimedAnimation] = []

    private static let eventAttributeNames: [(String, String)] = [
        ("onload", "load"),
        ("onclick", "click"),
        ("onmousedown", "mousedown"),
        ("onmouseup", "mouseup"),
        ("onmouseover", "mouseover"),
        ("onmousemove", "mousemove"),
        ("onmouseout", "mouseout"),
        ("onfocusin", "focusin"),
        ("onfocusout", "focusout"),
        ("onactivate", "activate"),
    ]

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
        var colorInterpolation: SVGColorInterpolation?
        var transform: SVGTransform?
        var stops: [SVGGradientStop] = []
        var defaultStopColor: SVGColor = .black
        var defaultStopOpacity: CGFloat = 1
        var explicitAttrs: Set<String> = []
    }

    struct PartialClipPath {
        var id: String?
        var units: SVGClipPath.Units = .userSpaceOnUse
        var transform: SVGTransform = .identity
        var clipPathRef: String?
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

    struct PartialSVGElement {
        var id: String?
        var origin: CGPoint = .zero
        var size: CGSize = .zero
        var viewBox: CGRect?
        var preserveAspectRatio: SVGPreserveAspectRatio = .default
        var overflow: SVGOverflow = .hidden
        var groupStackDepth: Int = 0
        var children: [SVGElement] = []
    }

    struct PartialPattern: Equatable {
        var id: String?
        var href: String?
        var x: CGFloat?
        var y: CGFloat?
        var width: CGFloat?
        var height: CGFloat?
        var patternUnits: SVGPatternUnits?
        var patternContentUnits: SVGPatternUnits?
        var transform: SVGTransform?
        var viewBox: CGRect?
        var children: [SVGElement] = []

        func materialized(hasInvalidHref: Bool = false) -> SVGPattern {
            SVGPattern(
                x: x ?? 0,
                y: y ?? 0,
                width: width ?? 0,
                height: height ?? 0,
                patternUnits: patternUnits ?? .objectBoundingBox,
                patternContentUnits: patternContentUnits ?? .userSpaceOnUse,
                transform: transform ?? .identity,
                viewBox: viewBox,
                children: children,
                hasInvalidHref: hasInvalidHref
            )
        }

        /// SVG 1.1 §13.4.3: inherit attributes from the referenced pattern.
        /// Content children are inherited only when this pattern defines none of its own.
        func merged(with parent: PartialPattern) -> PartialPattern {
            var m = self
            if m.x == nil { m.x = parent.x }
            if m.y == nil { m.y = parent.y }
            if m.width == nil { m.width = parent.width }
            if m.height == nil { m.height = parent.height }
            if m.patternUnits == nil { m.patternUnits = parent.patternUnits }
            if m.patternContentUnits == nil { m.patternContentUnits = parent.patternContentUnits }
            if m.transform == nil { m.transform = parent.transform }
            if m.viewBox == nil { m.viewBox = parent.viewBox }
            if m.children.isEmpty { m.children = parent.children }
            return m
        }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard beginParsingElement(parser) else { return }

        if shouldSkipForConditionalProcessing(elementName: elementName, attributes: attributeDict) {
            skipSubtreeDepth = 1
            return
        }

        let inheritedPaint = paintStack.last ?? SVGPaintProperties()
        let mergedPaint = mergePaint(
            into: inheritedPaint,
            elementName: elementName,
            from: attributeDict,
            parser: parser
        )
        paintStack.append(resolveCurrentColorForInheritance(mergedPaint.paint))
        specifiedPaintKeysStack.append(mergedPaint.specifiedKeys)
        let elementPaint = mergedPaint.paint

        let inheritedFont = fontStack.last ?? SVGFont()
        let elementFont = mergeFont(into: inheritedFont, from: attributeDict)
        fontStack.append(elementFont)

        switch elementName {
        case "switch":
            switchStack.append(PartialSwitch())
        case "svg":
            if svgNestingDepth == 0 {
                handleSVGRoot(attributes: attributeDict, parser: parser)
            } else {
                handleNestedSVGStart(attributes: attributeDict)
            }
            svgNestingDepth += 1
        case "g", "symbol":
            beginSwitchChildIfNeeded(attributes: attributeDict)
            if defsDepth > 0 { definitionContainerDepth += 1 }
            let transform = transform(from: attributeDict, parser: parser) ?? .identity
            let clipRef = parseClipPathRef(attributeDict)
            let maskR = parseMaskRef(attributeDict)
            groupIdStack.append(attributeDict["id"])
            groupAnimationStack.append([])
            groupStack.append(SVGGroup(
                id: attributeDict["id"],
                transform: transform,
                opacity: elementPaint.opacity,
                visibility: elementPaint.visibility,
                clipPathRef: clipRef,
                maskRef: maskR,
                explicitPresentation: elementExplicitPresentation(from: attributeDict)
            ))
            captureEventHandlers(elementName: elementName, attributes: attributeDict)
        case "use":
            beginSwitchChildIfNeeded(attributes: attributeDict)
            handleUse(
                attributes: attributeDict, paint: elementPaint, font: elementFont, parser: parser
            )
        case "image":
            beginSwitchChildIfNeeded(attributes: attributeDict)
            handleImage(attributes: attributeDict, paint: elementPaint, parser: parser)
        case "rect":
            beginSwitchChildIfNeeded(attributes: attributeDict)
            handleRect(attributes: attributeDict, paint: elementPaint, parser: parser)
        case "circle":
            beginSwitchChildIfNeeded(attributes: attributeDict)
            handleCircle(attributes: attributeDict, paint: elementPaint, parser: parser)
        case "ellipse":
            beginSwitchChildIfNeeded(attributes: attributeDict)
            handleEllipse(attributes: attributeDict, paint: elementPaint, parser: parser)
        case "line":
            beginSwitchChildIfNeeded(attributes: attributeDict)
            handleLine(attributes: attributeDict, paint: elementPaint, parser: parser)
        case "polyline":
            beginSwitchChildIfNeeded(attributes: attributeDict)
            handlePolyline(attributes: attributeDict, paint: elementPaint, parser: parser)
        case "polygon":
            beginSwitchChildIfNeeded(attributes: attributeDict)
            handlePolygon(attributes: attributeDict, paint: elementPaint, parser: parser)
        case "path":
            beginSwitchChildIfNeeded(attributes: attributeDict)
            handlePath(attributes: attributeDict, paint: elementPaint, parser: parser)
        case "text":
            beginSwitchChildIfNeeded(attributes: attributeDict)
            handleTextStart(
                attributes: attributeDict, paint: elementPaint, font: elementFont, parser: parser
            )
        case "tspan":
            handleTspanStart(attributes: attributeDict, parser: parser)
        case "linearGradient":
            handleLinearGradientStart(attributes: attributeDict)
        case "radialGradient":
            handleRadialGradientStart(attributes: attributeDict)
        case "pattern":
            handlePatternStart(attributes: attributeDict, parser: parser)
        case "stop":
            handleStop(attributes: attributeDict, currentColor: elementPaint.color)
        case "clipPath":
            handleClipPathStart(attributes: attributeDict, parser: parser)
        case "mask":
            handleMaskStart(attributes: attributeDict)
        case "color-profile":
            handleColorProfile(attributes: attributeDict)
        case "defs":
            defsDepth += 1
        case "style":
            let type = attributeDict["type"]?.trimmingCharacters(in: .whitespaces).lowercased()
            if type == nil || type == "text/css" {
                styleTextBuffer = ""
            }
        case "script":
            scriptType = attributeDict["type"]
            scriptTextBuffer = ""
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
        case "animate", "set", "animateTransform", "animateMotion":
            if let timed = AnimationAttributeParser.timedAnimation(
                elementName: elementName,
                attributes: attributeDict
            ) {
                appendCapturedAnimation(timed)
            }
        default:
            break
        }

        let classes = Set((attributeDict["class"] ?? "").split(whereSeparator: \.isWhitespace).map(String.init))
        let node = CSSNodeContext(
            elementName: elementName,
            elementId: attributeDict["id"],
            attributes: attributeDict,
            classes: classes,
            isFirstChild: cssChildStack.last?.isEmpty ?? true,
            parent: cssElementStack.last,
            previousSibling: cssChildStack.last?.last
        )
        cssElementStack.append(node)
        cssChildStack.append([])
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if styleTextBuffer != nil {
            styleTextBuffer?.append(string)
            return
        }
        if scriptTextBuffer != nil {
            scriptTextBuffer?.append(string)
            return
        }
        guard activeTextRun != nil else { return }
        activeTextRun?.string.append(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if styleTextBuffer != nil,
           let string = String(data: CDATABlock, encoding: .utf8) {
            styleTextBuffer?.append(string)
            return
        }
        if scriptTextBuffer != nil,
           let string = String(data: CDATABlock, encoding: .utf8) {
            scriptTextBuffer?.append(string)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if skipSubtreeDepth > 0 {
            endParsingElement()
            return
        }
        defer { endParsingElement() }

        paintStack.removeLast()
        specifiedPaintKeysStack.removeLast()
        fontStack.removeLast()

        switch elementName {
        case "switch":
            finalizeSwitch()
        case "svg":
            svgNestingDepth -= 1
            if svgNestingDepth == 0 {
                animationMetadata.rootAnimations = rootAnimationBuffer
                guard let root = groupStack.popLast() else { return }
                document?.root = root
            } else {
                finalizeNestedSVG()
            }
        case "g", "symbol":
            _ = groupIdStack.popLast()
            guard var finished = groupStack.popLast() else { return }
            finished.animations = groupAnimationStack.popLast() ?? []
            registerDefinition(id: finished.id, element: .group(finished))
            if defsDepth == 0 {
                appendChild(.group(finished))
            }
            if defsDepth > 0 { definitionContainerDepth -= 1 }
        case "rect", "circle", "ellipse", "line", "polyline", "polygon", "path", "use":
            finalizeAnimatableShape()
        case "script":
            if let source = scriptTextBuffer {
                scriptMetadata.blocks.append(SVGScriptBlock(type: scriptType, source: source))
            }
            scriptTextBuffer = nil
            scriptType = nil
        case "text":
            flushActiveTextRun()
            guard var finished = textStack.popLast() else { return }
            finalizeTextRuns(
                &finished,
                rootRotate: textRootRotate,
                segmentMeta: textSegmentMeta
            )
            registerDefinition(id: finished.id, element: .text(finished))
            tspanStyleStack.removeAll()
            rotateStack.removeAll()
            rotatePushStack.removeAll()
            textRootRotate = []
            textSegmentMeta = []
            pendingRotateFrame = nil
            tspanBaselineYStack = []
            textPreserveSpaceStack.removeLast()
            activeTextRun = nil
            appendChild(.text(finished))
        case "tspan":
            flushActiveTextRun()
            if rotatePushStack.popLast() == true {
                rotateStack.removeLast()
                if !textSegmentMeta.isEmpty {
                    textSegmentMeta[textSegmentMeta.count - 1].closesRotate = true
                }
            }
            if tspanStyleStack.count > 1 {
                tspanStyleStack.removeLast()
            }
            if tspanBaselineYStack.count > 1 {
                tspanBaselineYStack.removeLast()
            }
            if let (font, paint) = tspanStyleStack.last {
                var next = SVGTextRun(string: "", font: font, paint: paint)
                next.baselineY = tspanBaselineYStack.last
                next.preserveSpace = textPreserveSpaceStack.last ?? false
                activeTextRun = next
            }
        case "linearGradient":
            finalizeLinearGradient()
        case "radialGradient":
            finalizeRadialGradient()
        case "pattern":
            finalizePattern()
        case "clipPath":
            finalizeClipPath()
        case "mask":
            finalizeMask()
        case "defs":
            if defsDepth > 0 { defsDepth -= 1 }
        case "style":
            if let buffer = styleTextBuffer {
                if !stylesPreloaded {
                    stylesheet.append(css: buffer, importCSS: Self.cssImportLoader(for: options.resourcePolicy))
                }
                styleTextBuffer = nil
            }
        case "font-face" where !svgFontStack.isEmpty:
            break
        case "font-face":
            finalizeCSSFontFace()
        case "font":
            finalizeSVGFont()
        default:
            break
        }

        endSwitchChildIfNeeded()

        guard let finished = cssElementStack.popLast() else { return }
        _ = cssChildStack.popLast()
        if !cssChildStack.isEmpty {
            cssChildStack[cssChildStack.count - 1].append(finished)
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
        let width = rootLength(attributes["width"])
        let height = rootLength(attributes["height"])

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
        groupStack.append(SVGGroup(id: attributes["id"]))
        scriptMetadata.contentScriptType = attributes["contentScriptType"]
        captureEventHandlers(elementName: "svg", attributes: attributes)
    }

    private func handleNestedSVGStart(attributes: [String: String]) {
        viewportStack.append(viewport)
        let x = resolveLength(attributes["x"], axis: .x)
        let y = resolveLength(attributes["y"], axis: .y)
        let width = resolveLength(attributes["width"], axis: .x, default: viewport.width)
        let height = resolveLength(attributes["height"], axis: .y, default: viewport.height)
        let viewBox = attributes["viewBox"].flatMap { AttributeParsers.viewBox($0) }
        let preserveAspectRatio = attributes["preserveAspectRatio"]
            .flatMap { AttributeParsers.preserveAspectRatio($0) } ?? .default
        let overflow = parseOverflow(attributes["overflow"])
        if let viewBox {
            viewport = viewBox.size
        } else {
            viewport = CGSize(width: width, height: height)
        }
        svgStack.append(PartialSVGElement(
            id: attributes["id"],
            origin: CGPoint(x: x, y: y),
            size: CGSize(width: width, height: height),
            viewBox: viewBox,
            preserveAspectRatio: preserveAspectRatio,
            overflow: overflow,
            groupStackDepth: groupStack.count
        ))
    }

    private func finalizeNestedSVG() {
        guard let partial = svgStack.popLast() else { return }
        if let parentViewport = viewportStack.popLast() {
            viewport = parentViewport
        }
        let svg = SVGSVGElement(
            id: partial.id,
            origin: partial.origin,
            size: partial.size,
            viewBox: partial.viewBox,
            preserveAspectRatio: partial.preserveAspectRatio,
            overflow: partial.overflow,
            children: partial.children
        )
        appendChild(.svg(svg))
    }

    private func parseOverflow(_ raw: String?) -> SVGOverflow {
        guard let raw else { return .hidden }
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "visible": return .visible
        default: return .hidden
        }
    }

    /// Root `width`/`height` for intrinsic sizing. Percentages are ignored because
    /// there is no viewport yet — `viewBox` supplies the fallback (W3C suite pattern).
    private func rootLength(_ raw: String?) -> CGFloat? {
        guard let raw, let len = AttributeParsers.length(raw) else { return nil }
        guard len.unit != .percent else { return nil }
        return len.resolved()
    }

    private func captureEventHandlers(elementName: String, attributes: [String: String]) {
        var handlers: [SVGEventHandler] = []
        for (attribute, event) in Self.eventAttributeNames {
            if let body = attributes[attribute], !body.isEmpty {
                handlers.append(SVGEventHandler(event: event, script: body))
            }
        }
        guard !handlers.isEmpty else { return }
        if elementName == "svg" {
            scriptMetadata.rootHandlers.append(contentsOf: handlers)
        } else if let id = attributes["id"], !id.isEmpty {
            scriptMetadata.handlersByElementID[id, default: []].append(contentsOf: handlers)
        }
    }
    /// Resolves a paint-server coordinate (`gradient` / `pattern` attributes).
    /// `objectBoundingBox` treats `%` as a bbox fraction (100% → 1.0);
    /// `userSpaceOnUse` resolves `%` against the viewport like shape geometry.
    private func resolvePaintServerLength(
        _ raw: String?,
        objectBoundingBox: Bool,
        axis: Axis
    ) -> CGFloat? {
        guard let raw, let len = AttributeParsers.length(raw) else { return nil }
        if objectBoundingBox {
            if len.unit == .percent { return len.value / 100 }
            return len.resolved()
        }
        return resolveLength(raw, axis: axis)
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

    private func handleImage(attributes: [String: String], paint: SVGPaintProperties, parser: XMLParser) {
        guard let href = attributes["xlink:href"] ?? attributes["href"] else { return }
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let x = attributes["x"].map { resolveLength($0, axis: .x) } ?? 0
        let y = attributes["y"].map { resolveLength($0, axis: .y) } ?? 0
        let width = attributes["width"].map { resolveLength($0, axis: .x) } ?? 0
        let height = attributes["height"].map { resolveLength($0, axis: .y) } ?? 0
        let preserveAspectRatio = attributes["preserveAspectRatio"]
            .flatMap { AttributeParsers.preserveAspectRatio($0) } ?? .default

        let image = SVGImage(
            id: attributes["id"],
            origin: CGPoint(x: x, y: y),
            size: CGSize(width: width, height: height),
            href: trimmed,
            preserveAspectRatio: preserveAspectRatio,
            paint: paint,
            transform: transform(from: attributes, parser: parser) ?? .identity,
            overflow: parseOverflow(attributes["overflow"]),
            clip: attributes["clip"].flatMap { AttributeParsers.cssClip($0) } ?? .auto,
            colorProfileName: Self.parseColorProfileName(attributes["color-profile"])
        )
        registerDefinition(id: attributes["id"], element: .image(image))
        appendChild(.image(image))
    }

    /// `auto` / `sRGB` mean no named profile override. Other values are profile names
    /// (or `#id` / `url(#id)` forms normalized to the id).
    static func parseColorProfileName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower == "auto" || lower == "srgb" { return nil }
        if lower.hasPrefix("url("), lower.hasSuffix(")") {
            var inner = trimmed.dropFirst(4).dropLast()
            if (inner.hasPrefix("\"") && inner.hasSuffix("\""))
                || (inner.hasPrefix("'") && inner.hasSuffix("'")) {
                inner = inner.dropFirst().dropLast()
            }
            return parseColorProfileName(String(inner))
        }
        if trimmed.hasPrefix("#") {
            let id = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty ? nil : id
        }
        return trimmed
    }

    func handleColorProfile(attributes: [String: String]) {
        let name = attributes["name"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let id = attributes["id"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let keyName = name.flatMap({ $0.isEmpty ? nil : $0 })
                ?? id.flatMap({ $0.isEmpty ? nil : $0 })
        else { return }

        let href = attributes["xlink:href"] ?? attributes["href"]
        var iccData: Data?
        if let href {
            let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
            switch SVGHrefResolver.classify(href: trimmed, policy: options.resourcePolicy) {
            case .localFile(let url):
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                components?.fragment = nil
                let fileURL = components?.url ?? url
                if let data = try? Data(contentsOf: fileURL), Self.isICCProfileData(data) {
                    iccData = data
                }
            case .dataURI(let uri):
                if let data = Self.dataFromDataURI(uri), Self.isICCProfileData(data) {
                    iccData = data
                }
            case .rejected(let reason):
                recordWarning(SVGHrefResolver.parseWarning(href: trimmed, reason: reason))
            case .fragment:
                break
            }
        }

        let profile = SVGColorProfile(name: keyName, href: href, iccData: iccData)
        colorProfiles[keyName] = profile
        if let id, !id.isEmpty, id != keyName {
            colorProfiles[id] = profile
        }
    }

    /// ICC profile files contain the ASCII tag `acsp` at byte offset 36.
    static func isICCProfileData(_ data: Data) -> Bool {
        guard data.count > 40 else { return false }
        return data[36..<40].elementsEqual([0x61, 0x63, 0x73, 0x70]) // "acsp"
    }

    /// Minimal `data:` URI decode for ICC payloads (not raster-gated).
    static func dataFromDataURI(_ uri: String) -> Data? {
        guard uri.lowercased().hasPrefix("data:") else { return nil }
        let body = uri.dropFirst(5)
        guard let comma = body.firstIndex(of: ",") else { return nil }
        let metadata = body[..<comma].lowercased()
        let payload = String(body[body.index(after: comma)...])
        if metadata.hasSuffix(";base64") {
            return Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
        }
        return Data(payload.utf8)
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
            id: attributes["id"],
            origin: CGPoint(x: x, y: y),
            size: CGSize(width: w, height: h),
            cornerRadii: radii,
            paint: paint,
            transform: transform(from: attributes, parser: parser) ?? .identity,
            explicitPresentation: elementExplicitPresentation(from: attributes)
        )
        registerDefinition(id: attributes["id"], element: .rect(rect))
        beginAnimatableShape(.rect(rect), definitionID: attributes["id"])
    }

    private func handleCircle(attributes: [String: String], paint: SVGPaintProperties, parser: XMLParser) {
        let cx = resolveLength(attributes["cx"], axis: .x)
        let cy = resolveLength(attributes["cy"], axis: .y)
        let r = resolveLength(attributes["r"], axis: .length)
        let circle = SVGCircle(
            center: CGPoint(x: cx, y: cy),
            radius: r,
            paint: paint,
            transform: transform(from: attributes, parser: parser) ?? .identity,
            explicitPresentation: elementExplicitPresentation(from: attributes)
        )
        registerDefinition(id: attributes["id"], element: .circle(circle))
        beginAnimatableShape(.circle(circle), definitionID: attributes["id"])
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
            transform: transform(from: attributes, parser: parser) ?? .identity,
            explicitPresentation: elementExplicitPresentation(from: attributes)
        )
        registerDefinition(id: attributes["id"], element: .ellipse(ellipse))
        beginAnimatableShape(.ellipse(ellipse), definitionID: attributes["id"])
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
            transform: transform(from: attributes, parser: parser) ?? .identity,
            explicitPresentation: elementExplicitPresentation(from: attributes)
        )
        registerDefinition(id: attributes["id"], element: .line(line))
        beginAnimatableShape(.line(line), definitionID: attributes["id"])
    }

    private func handlePolyline(attributes: [String: String], paint: SVGPaintProperties, parser: XMLParser) {
        let pts = attributes["points"].flatMap { AttributeParsers.points($0) } ?? []
        let polyline = SVGPolyline(
            points: pts,
            paint: paint,
            transform: transform(from: attributes, parser: parser) ?? .identity,
            explicitPresentation: elementExplicitPresentation(from: attributes)
        )
        registerDefinition(id: attributes["id"], element: .polyline(polyline))
        beginAnimatableShape(.polyline(polyline), definitionID: attributes["id"])
    }

    private func handlePolygon(attributes: [String: String], paint: SVGPaintProperties, parser: XMLParser) {
        let pts = attributes["points"].flatMap { AttributeParsers.points($0) } ?? []
        let polygon = SVGPolygon(
            points: pts,
            paint: paint,
            transform: transform(from: attributes, parser: parser) ?? .identity,
            explicitPresentation: elementExplicitPresentation(from: attributes)
        )
        registerDefinition(id: attributes["id"], element: .polygon(polygon))
        beginAnimatableShape(.polygon(polygon), definitionID: attributes["id"])
    }

    private func handlePath(attributes: [String: String], paint: SVGPaintProperties, parser: XMLParser) {
        guard let raw = attributes["d"],
              let parsed = PathDataParser.parse(raw, maxCommands: options.limits.maxPathCommands),
              !parsed.commands.isEmpty else { return }
        if parsed.truncated {
            recordLimitExceeded("maxPathCommands", line: parser.lineNumber)
        }
        let path = SVGPath(
            commands: parsed.commands,
            paint: paint,
            explicitPresentation: elementExplicitPresentation(from: attributes),
            transform: transform(from: attributes, parser: parser) ?? .identity
        )
        registerDefinition(id: attributes["id"], element: .path(path))
        beginAnimatableShape(.path(path), definitionID: attributes["id"])
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
            id: attributes["id"],
            origin: CGPoint(x: x, y: y),
            runs: [],
            font: font,
            paint: paint,
            transform: transform(from: attributes, parser: parser) ?? .identity,
            explicitPresentation: elementExplicitPresentation(from: attributes)
        )
        textStack.append(text)
        tspanStyleStack = [(font, paint)]
        activeTextRun = SVGTextRun(string: "", font: font, paint: paint, baselineY: y)
        textRootRotate = parseRotateList(attributes["rotate"]) ?? []
        textSegmentMeta = []
        pendingRotateFrame = nil
        tspanBaselineYStack = [y]
        rotateStack = [RotateCursor(values: textRootRotate)]
        rotatePushStack = []
        let preserve = attributes["xml:space"] == "preserve"
        textPreserveSpaceStack.append(preserve)
        if preserve {
            activeTextRun?.preserveSpace = true
        }
    }

    private func resolveLengthList(_ raw: String?, axis: Axis) -> [CGFloat]? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split { $0.isWhitespace || $0 == "," || $0 == "\t" || $0 == "\n" || $0 == "\r" }
        guard !parts.isEmpty else { return nil }
        return parts.map { resolveLength(String($0), axis: axis) }
    }

    private func parseRotateList(_ raw: String?) -> [CGFloat]? {
        resolveLengthList(raw, axis: .length)
    }

    private func applyTspanPositionAttributes(
        _ attributes: [String: String],
        to run: inout SVGTextRun
    ) {
        if let xs = resolveLengthList(attributes["x"], axis: .x) {
            run.explicitX = xs
        }
        if let raw = attributes["y"] {
            run.explicitY = resolveLength(raw, axis: .y)
        }
        if let raw = attributes["dx"] {
            run.dx = resolveLength(raw, axis: .length)
        }
        if let raw = attributes["dy"] {
            run.dy = resolveLength(raw, axis: .length)
        }
        if attributes["xml:space"] == "preserve" {
            run.preserveSpace = true
        }
    }

    private func handleTspanStart(attributes: [String: String], parser: XMLParser) {
        guard !textStack.isEmpty else { return }
        var leadingWhitespace = ""
        // Inter-`<tspan>` formatting whitespace is not painted when the next
        // tspan supplies an explicit anchor.
        if let run = activeTextRun,
           run.string.allSatisfy(\.isWhitespace),
           run.explicitX == nil, run.explicitY == nil {
            if attributes["x"] != nil || attributes["y"] != nil {
                activeTextRun?.string = ""
            } else if attributes["rotate"] != nil {
                // Whitespace before `<tspan rotate>` belongs in that frame
                // (e.g. the space before "specified" in text-tspan-02-b).
                leadingWhitespace = " "
                activeTextRun?.string = ""
            }
        }
        flushActiveTextRun()
        let (inheritedFont, inheritedPaint) = tspanStyleStack.last!
        let runFont = mergeFont(into: inheritedFont, from: attributes)
        let runPaint = mergePaint(
            into: inheritedPaint,
            elementName: "tspan",
            from: attributes,
            parser: parser
        ).paint
        var run = SVGTextRun(string: leadingWhitespace, font: runFont, paint: runPaint)
        applyTspanPositionAttributes(attributes, to: &run)
        if run.preserveSpace == false {
            run.preserveSpace = textPreserveSpaceStack.last ?? false
        }
        if let raw = attributes["y"] {
            let resolved = resolveLength(raw, axis: .y)
            tspanBaselineYStack.append(resolved)
        } else if let inherited = tspanBaselineYStack.last {
            tspanBaselineYStack.append(inherited)
        }
        run.baselineY = tspanBaselineYStack.last
        if let rotate = parseRotateList(attributes["rotate"]) {
            if !rotateStack.isEmpty {
                var parent = rotateStack[rotateStack.count - 1]
                parent.index = parent.values.count
                rotateStack[rotateStack.count - 1] = parent
            }
            rotateStack.append(RotateCursor(values: rotate))
            rotatePushStack.append(true)
            pendingRotateFrame = rotate
        } else {
            rotatePushStack.append(false)
        }
        tspanStyleStack.append((runFont, runPaint))
        activeTextRun = run
    }

    private func flushActiveTextRun() {
        guard !textStack.isEmpty, let run = activeTextRun else { return }
        let isEmpty = run.string.isEmpty
        let hasOffset = run.dx != 0 || run.dy != 0
            || run.explicitX != nil || run.explicitY != nil
        guard !isEmpty || hasOffset else { return }

        var flushed = run
        flushed.baselineY = tspanBaselineYStack.last ?? textStack[textStack.count - 1].origin.y
        var meta = TextSegmentMeta()
        if let frame = pendingRotateFrame {
            meta.opensRotate = frame
            pendingRotateFrame = nil
        }
        textStack[textStack.count - 1].runs.append(flushed)
        textSegmentMeta.append(meta)
        if let (font, paint) = tspanStyleStack.last {
            var next = SVGTextRun(string: "", font: font, paint: paint)
            next.baselineY = tspanBaselineYStack.last
            next.preserveSpace = textPreserveSpaceStack.last ?? false
            activeTextRun = next
        }
    }

    /// Normalize character stream (`xml:space`) then assign per-character `rotate`.
    private func finalizeTextRuns(
        _ text: inout SVGText,
        rootRotate: [CGFloat],
        segmentMeta: [TextSegmentMeta]
    ) {
        guard !text.runs.isEmpty else { return }

        var meta = segmentMeta
        if meta.count < text.runs.count {
            meta.append(contentsOf: repeatElement(TextSegmentMeta(), count: text.runs.count - meta.count))
        } else if meta.count > text.runs.count {
            meta = Array(meta.prefix(text.runs.count))
        }

        let segments = zip(text.runs, meta).map { run, runMeta in
            TextCharacterStream.RawSegment(run: run, raw: run.string, meta: runMeta)
        }
        var normalized = TextCharacterStream.normalize(segments)
        TextCharacterStream.assignRotations(
            runs: &normalized.runs,
            rootRotate: rootRotate,
            meta: normalized.meta
        )
        text.runs = normalized.runs

        guard !text.runs.isEmpty else { return }

        let hasLayout = text.runs.contains {
            $0.dx != 0 || $0.dy != 0 || $0.explicitX != nil || $0.explicitY != nil
        }
        let hasPreserve = text.runs.contains { $0.preserveSpace }
        let hasRotations = text.runs.contains { $0.rotations != nil }
        let uniformStyle = text.runs.allSatisfy {
            $0.font == text.runs[0].font && $0.paint == text.runs[0].paint
        }
        if !hasLayout && !hasPreserve && !hasRotations && uniformStyle {
            let merged = SAXDelegate.collapseTextWhitespace(text.runs.map(\.string).joined())
            text.runs = [SVGTextRun(string: merged, font: text.runs[0].font, paint: text.runs[0].paint)]
        }
    }

    // MARK: - Helpers

    private func beginAnimatableShape(_ element: SVGElement, definitionID: String?) {
        pendingAnimatable = PendingAnimatable(
            element: element,
            animations: [],
            definitionID: definitionID
        )
    }

    private func finalizeAnimatableShape() {
        guard let pending = pendingAnimatable else { return }
        pendingAnimatable = nil
        var element = pending.element
        element.setAnimations(pending.animations)
        if let id = pending.definitionID, !id.isEmpty {
            storeDefinition(id: id, element: element)
        }
        appendChild(element)
    }

    private func storeDefinition(id: String, element: SVGElement) {
        if definitions.count >= options.limits.maxDefinitions {
            if !warnedDefinitionLimit {
                warnedDefinitionLimit = true
                recordLimitExceeded("maxDefinitions", line: nil)
            }
            return
        }
        definitions[id] = element
    }

    private func appendCapturedAnimation(_ animation: SVGTimedAnimation) {
        if var pending = pendingAnimatable {
            pending.animations.append(animation)
            pendingAnimatable = pending
            return
        }
        if !groupAnimationStack.isEmpty {
            groupAnimationStack[groupAnimationStack.count - 1].append(animation)
            return
        }
        rootAnimationBuffer.append(animation)
        if let id = animation.id, !id.isEmpty {
            animationMetadata.index[id] = rootAnimationBuffer.count - 1
        }
    }

    /// Index an element by `id` so `<use href="#id">` can resolve it anywhere in
    /// the document, not only under `<defs>` (SVG 1.1 §5.4 / §5.6.2).
    private func registerDefinition(id: String?, element: SVGElement) {
        guard let id, !id.isEmpty else { return }
        storeDefinition(id: id, element: element)
    }

    private func handleUse(
        attributes: [String: String],
        paint: SVGPaintProperties,
        font: SVGFont,
        parser: XMLParser
    ) {
        guard let href = parseUseHref(attributes) else { return }
        let x = attributes["x"].map { resolveLength($0, axis: .x) } ?? 0
        let y = attributes["y"].map { resolveLength($0, axis: .y) } ?? 0
        let size: CGSize? = {
            guard let w = attributes["width"], let h = attributes["height"] else { return nil }
            return CGSize(width: resolveLength(w, axis: .x), height: resolveLength(h, axis: .y))
        }()
        let use = SVGUse(
            href: href.fragmentID,
            sourceHref: href.sourceHref,
            origin: CGPoint(x: x, y: y),
            size: size,
            paint: paint,
            font: font,
            explicitPresentation: elementExplicitPresentation(from: attributes),
            transform: transform(from: attributes, parser: parser) ?? .identity
        )
        registerDefinition(id: attributes["id"], element: .use(use))
        beginAnimatableShape(.use(use), definitionID: attributes["id"])
    }

    private static let fontPresentationAttributeNames: Set<String> = [
        "font-family", "font-size", "font-weight", "font-style", "text-anchor"
    ]

    private func elementExplicitPresentation(from attributes: [String: String]) -> Set<String> {
        presentationAttributeKeys(from: attributes)
            .union(specifiedPaintKeysStack.last ?? [])
    }

    private func presentationAttributeKeys(from attributes: [String: String]) -> Set<String> {
        var keys = Set(attributes.keys.filter {
            CSSStylesheet.paintPresentationAttributes.contains($0)
                || Self.fontPresentationAttributeNames.contains($0)
        })
        if let style = attributes["style"] {
            for pair in style.split(separator: ";") {
                let parts = pair.split(separator: ":", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                guard parts.count == 2 else { continue }
                keys.insert(parts[0])
            }
        }
        return keys
    }

    private struct ParsedUseHref: Equatable {
        let fragmentID: String
        let sourceHref: String
    }

    /// Fragment id from `xlink:href` / `href` (same-document `#id` or external `file.svg#id`).
    private func parseUseHref(_ attributes: [String: String]) -> ParsedUseHref? {
        guard let raw = attributes["xlink:href"] ?? attributes["href"] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        switch SVGHrefResolver.classify(href: trimmed, policy: options.resourcePolicy) {
        case .fragment(let id):
            return ParsedUseHref(fragmentID: id, sourceHref: trimmed)
        case .localFile(let url):
            guard let id = url.fragment, !id.isEmpty else { return nil }
            return ParsedUseHref(fragmentID: id, sourceHref: trimmed)
        case .dataURI:
            guard let hash = trimmed.firstIndex(of: "#") else { return nil }
            let id = String(trimmed[trimmed.index(after: hash)...])
            guard !id.isEmpty else { return nil }
            return ParsedUseHref(fragmentID: id, sourceHref: trimmed)
        case .rejected:
            return nil
        }
    }

    private func beginSwitchChildIfNeeded(attributes: [String: String]) {
        guard !switchStack.isEmpty else { return }
        let index = switchStack.count - 1
        if switchStack[index].childNestingDepth == 0 {
            switchStack[index].pendingAttributes = attributes
        }
        switchStack[index].childNestingDepth += 1
    }

    private func endSwitchChildIfNeeded() {
        guard !switchStack.isEmpty else { return }
        let index = switchStack.count - 1
        switchStack[index].childNestingDepth -= 1
        if switchStack[index].childNestingDepth == 0 {
            switchStack[index].pendingAttributes = [:]
        }
    }

    private func finalizeSwitch() {
        guard let finished = switchStack.popLast() else { return }
        let winner = finished.candidates.first { candidate in
            SVGConditionalProcessing.evaluate(
                attributes: candidate.attributes,
                context: conditionalContext
            )
        }
        if let winner {
            appendChild(winner.element)
        }
    }

    private func appendChild(_ element: SVGElement) {
        if !switchStack.isEmpty {
            let index = switchStack.count - 1
            if switchStack[index].childNestingDepth == 1 {
                switchStack[index].candidates.append(
                    SwitchCandidate(
                        attributes: switchStack[index].pendingAttributes,
                        element: element
                    )
                )
                return
            }
        }
        if !patternStack.isEmpty {
            patternStack[patternStack.count - 1].children.append(element)
        } else if !svgStack.isEmpty {
            let svgIndex = svgStack.count - 1
            if groupStack.count > svgStack[svgIndex].groupStackDepth {
                groupStack[groupStack.count - 1].children.append(element)
            } else {
                svgStack[svgIndex].children.append(element)
            }
        } else if !clipPathStack.isEmpty {
            clipPathStack[clipPathStack.count - 1].children.append(element)
        } else if !maskStack.isEmpty {
            maskStack[maskStack.count - 1].children.append(element)
        } else if !groupStack.isEmpty, defsDepth == 0 || definitionContainerDepth > 0 {
            groupStack[groupStack.count - 1].children.append(element)
        } else if defsDepth > 0 {
            return
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

    private func cssImportLoader() -> ((String) -> String?)? {
        Self.cssImportLoader(for: options.resourcePolicy)
    }

    private static func cssImportLoader(for policy: SVGResourcePolicy) -> ((String) -> String?)? {
        guard case .localFiles = policy else { return nil }
        return { href in
            switch SVGHrefResolver.classify(href: href, policy: policy) {
            case .localFile(let url):
                return try? String(contentsOf: url, encoding: .utf8)
            default:
                return nil
            }
        }
    }

    private func mergePaint(
        into inherited: SVGPaintProperties,
        elementName: String,
        from attributes: [String: String],
        parser: XMLParser
    ) -> (paint: SVGPaintProperties, specifiedKeys: Set<String>) {
        var p = inherited
        // SVG 1.1 §14.5: 'opacity' is not inherited. Group opacity is stored on
        // `SVGGroup.opacity` and applied via `groupLayer` at render time.
        p.opacity = 1
        // SVG 1.1 §14.3.5: a `clipPath` and its children do not inherit clipping
        // paths from ancestors of the `clipPath` element. Explicit `clip-path` on
        // the `clipPath` itself is re-applied below via authored declarations.
        if elementName == "clipPath" {
            p.clipPathRef = nil
        }
        var authored: [String: (value: String, important: Bool, priority: Int)] = [:]

        func applyAuthoredDeclarations(_ declarations: [CSSDeclaration], priority: Int) {
            for declaration in declarations {
                let incoming = (declaration.value, declaration.important, priority)
                if shouldApplyAuthoredDeclaration(existing: authored[declaration.name], incoming: incoming) {
                    authored[declaration.name] = incoming
                }
            }
        }

        func flushAuthoredDeclarations() {
            let ordered = authored.keys.sorted()
            for name in ordered where name == "color" {
                applyPaintProperty(name: name, value: authored[name]!.value, into: &p, parser: parser)
            }
            for name in ordered where name != "color" {
                applyPaintProperty(name: name, value: authored[name]!.value, into: &p, parser: parser)
            }
        }

        // 1) Presentation attributes (specificity 0, never !important; XML names are case-sensitive).
        let presentationDeclarations = attributes
            .filter { CSSStylesheet.paintPresentationAttributes.contains($0.key) }
            .map { CSSDeclaration(name: $0.key, value: $0.value, important: false) }
        applyAuthoredDeclarations(presentationDeclarations, priority: 0)

        if !stylesheet.isEmpty {
            let classes = Set((attributes["class"] ?? "").split(whereSeparator: \.isWhitespace).map(String.init))
            let cssNode = CSSNodeContext(
                elementName: elementName,
                elementId: attributes["id"],
                attributes: attributes,
                classes: classes,
                isFirstChild: cssChildStack.last?.isEmpty ?? true,
                parent: cssElementStack.last,
                previousSibling: cssChildStack.last?.last
            )
            // 2) Author stylesheet rules (specificity + source order).
            applyAuthoredDeclarations(stylesheet.declarations(matching: cssNode), priority: 1)
        }

        // 3) Inline `style` (highest author specificity).
        if let style = attributes["style"] {
            var inlineStyleDeclarations: [CSSDeclaration] = []
            for pair in style.split(separator: ";") {
                let parts = pair.split(separator: ":", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard parts.count == 2,
                      let declaration = CSSStylesheet.parseInlineDeclaration(namePart: parts[0], valuePart: parts[1])
                else { continue }
                inlineStyleDeclarations.append(declaration)
            }
            applyAuthoredDeclarations(inlineStyleDeclarations, priority: 2)
        }

        flushAuthoredDeclarations()
        return (p, Set(authored.keys))
    }

    private func shouldApplyAuthoredDeclaration(
        existing: (value: String, important: Bool, priority: Int)?,
        incoming: (value: String, important: Bool, priority: Int)
    ) -> Bool {
        guard let existing else { return true }
        if incoming.important && !existing.important { return true }
        if !incoming.important && existing.important { return false }
        return incoming.priority >= existing.priority
    }

    private func applyPaintProperty(
        name: String,
        value: String,
        into p: inout SVGPaintProperties,
        parser: XMLParser
    ) {
        switch name.lowercased() {
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
            if trimmed.lowercased() == "inherit" { return }
            if case .color(let c) = AttributeParsers.color(trimmed) ?? .none {
                p.color = c
            }
        case "stop-color":
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased() == "inherit" { return }
            if case .color(let c) = AttributeParsers.color(trimmed) ?? .none {
                p.stopColor = c
            }
        case "stop-opacity":
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased() == "inherit" { return }
            if let d = Double(trimmed) { p.stopOpacity = CGFloat(min(1, max(0, d))) }
        case "visibility":
            if let v = SVGVisibility(rawValue: value.trimmingCharacters(in: .whitespaces).lowercased()) {
                p.visibility = v
            }
        case "display":
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            p.visibility = trimmed == "none" ? .hidden : .visible
        case "clip-path":
            if let ref = parseClipPathRef(["clip-path": value]) {
                p.clipPathRef = ref
            }
        case "clip-rule":
            if let rule = SVGFillRule(rawValue: value.trimmingCharacters(in: .whitespaces)) {
                p.clipRule = rule
            }
        case "mask":
            if let ref = parseMaskRef(["mask": value]) {
                p.maskRef = ref
            }
        default:
            break
        }
    }

    /// Inherited presentation values use the computed color, not the
    /// `currentColor` keyword (which would re-resolve against the child's `color`).
    private func resolveCurrentColorForInheritance(_ paint: SVGPaintProperties) -> SVGPaintProperties {
        var p = paint
        if case .currentColor = p.fill {
            p.fill = .color(p.color)
        }
        if case .currentColor = p.stroke {
            p.stroke = .color(p.color)
        }
        return p
    }

    /// Resolves a paint value, expanding `currentColor` and `url(#id)`
    /// references (SVG 1.1 §13.2 / §12.2). Server lookup is deferred to
    /// render-tree lowering; here we just record the reference id.
    private func resolvePaint(_ raw: String, currentColor: SVGColor) -> SVGPaint? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.caseInsensitiveCompare("currentColor") == .orderedSame {
            return .currentColor
        }
        if trimmed.lowercased().hasPrefix("url(") {
            guard let openEnd = trimmed.index(trimmed.startIndex, offsetBy: 4, limitedBy: trimmed.endIndex) else {
                return nil
            }
            let afterOpen = trimmed[openEnd...]
            guard let close = afterOpen.firstIndex(of: ")") else { return nil }
            var ref = String(afterOpen[..<close]).trimmingCharacters(in: .whitespaces)
            ref = ref.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            if ref.hasPrefix("#") { ref = String(ref.dropFirst()) }
            guard !ref.isEmpty else { return nil }
            let afterClose = afterOpen.index(after: close)
            let remainder = afterClose < afterOpen.endIndex
                ? String(afterOpen[afterClose...]).trimmingCharacters(in: .whitespaces)
                : ""
            let fallback: SVGColor? = {
                guard !remainder.isEmpty else { return nil }
                if case .color(let c) = resolvePaint(remainder, currentColor: currentColor) ?? .none {
                    return c
                }
                return nil
            }()
            return .paintServer(id: ref, fallback: fallback)
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
        case "font-style":
            if let s = SVGFontStyle.parse(value) { f.style = s }
        case "text-anchor":
            if value == "inherit" { return }
            if let a = SVGTextAnchor(rawValue: value) { f.anchor = a }
        default:
            break
        }
    }

    /// SVG `xml:space="default"`: collapse runs of whitespace and trim leading/trailing.
    static func collapseTextWhitespace(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Strip newlines, carriage returns, and tabs from a text run. Does not
    /// collapse or trim spaces — edge trimming happens in `finalizeTextRuns`.
    static func stripFormattingWhitespace(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\r\n", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\t", with: "")
    }

    // MARK: - Patterns

    private func handlePatternStart(attributes: [String: String], parser: XMLParser) {
        var partial = PartialPattern()
        partial.id = attributes["id"]
        partial.href = attributes["xlink:href"] ?? attributes["href"]
        if let u = attributes["patternUnits"]?.trimmingCharacters(in: .whitespaces),
           let units = SVGPatternUnits(rawValue: u) {
            partial.patternUnits = units
        }
        let obb = (partial.patternUnits ?? .objectBoundingBox) == .objectBoundingBox
        partial.x = attributes["x"].flatMap { resolvePaintServerLength($0, objectBoundingBox: obb, axis: .x) }
        partial.y = attributes["y"].flatMap { resolvePaintServerLength($0, objectBoundingBox: obb, axis: .y) }
        partial.width = attributes["width"].flatMap { resolvePaintServerLength($0, objectBoundingBox: obb, axis: .x) }
        partial.height = attributes["height"].flatMap { resolvePaintServerLength($0, objectBoundingBox: obb, axis: .y) }
        if let u = attributes["patternContentUnits"]?.trimmingCharacters(in: .whitespaces),
           let units = SVGPatternUnits(rawValue: u) {
            partial.patternContentUnits = units
        }
        if let raw = attributes["patternTransform"],
           let t = AttributeParsers.transform(raw) {
            partial.transform = t
        }
        if let raw = attributes["viewBox"] {
            partial.viewBox = AttributeParsers.viewBox(raw)
        }
        patternStack.append(partial)
    }

    private func finalizePattern() {
        guard let partial = patternStack.popLast() else { return }
        guard let id = partial.id else { return }
        pendingPatterns[id] = partial
        if var href = partial.href {
            if href.hasPrefix("#") { href = String(href.dropFirst()) }
            patternHrefs.append((id: id, href: href))
        }
    }

    /// Resolve pattern `xlink:href` chains and merge attributes per SVG 1.1
    /// §13.4.3: child's own values win; parent supplies unset attributes.
    fileprivate func resolvePatternHrefs() {
        var changed = true
        var iterations = 0
        while changed && iterations < 16 {
            changed = false
            iterations += 1
            for (id, href) in patternHrefs {
                guard let child = pendingPatterns[id],
                      let parent = pendingPatterns[href] else { continue }
                let merged = child.merged(with: parent)
                if merged != child {
                    pendingPatterns[id] = merged
                    changed = true
                }
            }
        }
        for (id, partial) in pendingPatterns {
            let invalidHref = patternHrefs.contains { entry in
                entry.id == id && pendingPatterns[entry.href] == nil
            }
            paintServers[id] = .pattern(partial.materialized(hasInvalidHref: invalidHref))
        }
    }

    // MARK: - Paint servers (gradients)

    fileprivate func handleLinearGradientStart(attributes: [String: String]) {
        var p = PartialGradient()
        p.id = attributes["id"]
        p.href = attributes["xlink:href"] ?? attributes["href"]
        let inheritedPaint = paintStack.last ?? SVGPaintProperties()
        p.defaultStopColor = inheritedPaint.stopColor
        p.defaultStopOpacity = inheritedPaint.stopOpacity
        if let u = attributes["gradientUnits"]?.trimmingCharacters(in: .whitespaces),
           let units = SVGGradientUnits(rawValue: u) {
            p.units = units
            p.explicitAttrs.insert("gradientUnits")
        }
        let obb = (p.units ?? .objectBoundingBox) == .objectBoundingBox
        if let raw = attributes["x1"] {
            p.explicitAttrs.insert("x1")
            p.x1 = resolvePaintServerLength(raw, objectBoundingBox: obb, axis: .x)
        }
        if let raw = attributes["y1"] {
            p.explicitAttrs.insert("y1")
            p.y1 = resolvePaintServerLength(raw, objectBoundingBox: obb, axis: .y)
        }
        if let raw = attributes["x2"] {
            p.explicitAttrs.insert("x2")
            p.x2 = resolvePaintServerLength(raw, objectBoundingBox: obb, axis: .x)
        }
        if let raw = attributes["y2"] {
            p.explicitAttrs.insert("y2")
            p.y2 = resolvePaintServerLength(raw, objectBoundingBox: obb, axis: .y)
        }
        if let s = attributes["spreadMethod"]?.trimmingCharacters(in: .whitespaces),
           let spread = SVGGradientSpread(rawValue: s) {
            p.spreadMethod = spread
            p.explicitAttrs.insert("spreadMethod")
        }
        if let raw = attributes["gradientTransform"],
           let t = AttributeParsers.transform(raw) {
            p.transform = t
            p.explicitAttrs.insert("gradientTransform")
        }
        if let raw = attributes["color-interpolation"]?.trimmingCharacters(in: .whitespaces),
           let interpolation = SVGColorInterpolation(rawValue: raw) {
            p.colorInterpolation = interpolation
            p.explicitAttrs.insert("color-interpolation")
        }
        gradientStack.append(p)
    }

    fileprivate func handleStop(attributes: [String: String], currentColor: SVGColor) {
        guard !gradientStack.isEmpty else { return }
        let gradientIndex = gradientStack.count - 1
        let gradientDefaults = gradientStack[gradientIndex]

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
            } else if raw.caseInsensitiveCompare("inherit") == .orderedSame {
                color = gradientDefaults.defaultStopColor
            } else if case .color(let c) = AttributeParsers.color(raw) ?? .none {
                color = c
            }
        }
        if let raw = props["stop-opacity"]?.trimmingCharacters(in: .whitespaces) {
            if raw.caseInsensitiveCompare("inherit") == .orderedSame {
                color.alpha = gradientDefaults.defaultStopOpacity
            } else if let d = Double(raw) {
                color.alpha = CGFloat(min(1, max(0, d)))
            }
        }
        gradientStack[gradientIndex].stops.append(
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
        partial.clipPathRef = parseClipPathRef(attributes)
        clipPathStack.append(partial)
    }

    private func finalizeClipPath() {
        guard let partial = clipPathStack.popLast(), let id = partial.id else { return }
        let clipPath = SVGClipPath(
            units: partial.units,
            transform: partial.transform,
            children: partial.children,
            clipPathRef: partial.clipPathRef
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
        let inheritedPaint = paintStack.last ?? SVGPaintProperties()
        p.defaultStopColor = inheritedPaint.stopColor
        p.defaultStopOpacity = inheritedPaint.stopOpacity
        if let u = attributes["gradientUnits"]?.trimmingCharacters(in: .whitespaces),
           let units = SVGGradientUnits(rawValue: u) {
            p.units = units
            p.explicitAttrs.insert("gradientUnits")
        }
        let obb = (p.units ?? .objectBoundingBox) == .objectBoundingBox
        if let raw = attributes["cx"] {
            p.explicitAttrs.insert("cx")
            p.cx = resolvePaintServerLength(raw, objectBoundingBox: obb, axis: .x)
        }
        if let raw = attributes["cy"] {
            p.explicitAttrs.insert("cy")
            p.cy = resolvePaintServerLength(raw, objectBoundingBox: obb, axis: .y)
        }
        if let raw = attributes["fx"] {
            p.explicitAttrs.insert("fx")
            p.fx = resolvePaintServerLength(raw, objectBoundingBox: obb, axis: .x)
        }
        if let raw = attributes["fy"] {
            p.explicitAttrs.insert("fy")
            p.fy = resolvePaintServerLength(raw, objectBoundingBox: obb, axis: .y)
        }
        if let raw = attributes["r"] {
            p.explicitAttrs.insert("r")
            p.r = resolvePaintServerLength(raw, objectBoundingBox: obb, axis: .length)
        }
        if let s = attributes["spreadMethod"]?.trimmingCharacters(in: .whitespaces),
           let spread = SVGGradientSpread(rawValue: s) {
            p.spreadMethod = spread
            p.explicitAttrs.insert("spreadMethod")
        }
        if let raw = attributes["gradientTransform"],
           let t = AttributeParsers.transform(raw) {
            p.transform = t
            p.explicitAttrs.insert("gradientTransform")
        }
        if let raw = attributes["color-interpolation"]?.trimmingCharacters(in: .whitespaces),
           let interpolation = SVGColorInterpolation(rawValue: raw) {
            p.colorInterpolation = interpolation
            p.explicitAttrs.insert("color-interpolation")
        }
        gradientStack.append(p)
    }

    fileprivate func finalizeRadialGradient() {
        guard let p = gradientStack.popLast(), let id = p.id else { return }
        let gradient = SVGRadialGradient(
            cx: p.cx ?? 0.5,
            cy: p.cy ?? 0.5,
            fx: p.explicitAttrs.contains("fx") ? p.fx : nil,
            fy: p.explicitAttrs.contains("fy") ? p.fy : nil,
            r: p.r ?? 0.5,
            units: p.units ?? .objectBoundingBox,
            spreadMethod: p.spreadMethod ?? .pad,
            colorInterpolation: p.colorInterpolation ?? .sRGB,
            stops: Self.normalizeGradientStops(p.stops),
            transform: p.transform ?? .identity
        )
        paintServers[id] = .radialGradient(gradient)
        gradientExplicitAttrs[id] = p.explicitAttrs
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
            colorInterpolation: p.colorInterpolation ?? .sRGB,
            stops: Self.normalizeGradientStops(p.stops),
            transform: p.transform ?? .identity
        )
        paintServers[id] = .linearGradient(gradient)
        gradientExplicitAttrs[id] = p.explicitAttrs
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
                let childExplicit = gradientExplicitAttrs[id] ?? []
                let parentExplicit = gradientExplicitAttrs[href] ?? []
                switch (childServer, parentServer) {
                case (.linearGradient(let child), .linearGradient(let parent)):
                    let merged = SVGLinearGradient(
                        x1: Self.inheritedGradientValue("x1", child: child.x1, parent: parent.x1, childExplicit: childExplicit),
                        y1: Self.inheritedGradientValue("y1", child: child.y1, parent: parent.y1, childExplicit: childExplicit),
                        x2: Self.inheritedGradientValue("x2", child: child.x2, parent: parent.x2, childExplicit: childExplicit),
                        y2: Self.inheritedGradientValue("y2", child: child.y2, parent: parent.y2, childExplicit: childExplicit),
                        units: Self.inheritedGradientValue("gradientUnits", child: child.units, parent: parent.units, childExplicit: childExplicit),
                        spreadMethod: Self.inheritedGradientValue("spreadMethod", child: child.spreadMethod, parent: parent.spreadMethod, childExplicit: childExplicit),
                        colorInterpolation: Self.inheritedGradientValue("color-interpolation", child: child.colorInterpolation, parent: parent.colorInterpolation, childExplicit: childExplicit),
                        stops: child.stops.isEmpty ? parent.stops : child.stops,
                        transform: Self.inheritedGradientValue("gradientTransform", child: child.transform, parent: parent.transform, childExplicit: childExplicit)
                    )
                    if merged != child { paintServers[id] = .linearGradient(merged); changed = true }
                case (.radialGradient(let child), .radialGradient(let parent)):
                    let cx = Self.inheritedGradientValue("cx", child: child.cx, parent: parent.cx, childExplicit: childExplicit)
                    let cy = Self.inheritedGradientValue("cy", child: child.cy, parent: parent.cy, childExplicit: childExplicit)
                    let fx: CGFloat? = childExplicit.contains("fx")
                        ? child.fx
                        : (parentExplicit.contains("fx") ? parent.fx : nil)
                    let fy: CGFloat? = childExplicit.contains("fy")
                        ? child.fy
                        : (parentExplicit.contains("fy") ? parent.fy : nil)
                    let merged = SVGRadialGradient(
                        cx: cx,
                        cy: cy,
                        fx: fx,
                        fy: fy,
                        r: Self.inheritedGradientValue("r", child: child.r, parent: parent.r, childExplicit: childExplicit),
                        units: Self.inheritedGradientValue("gradientUnits", child: child.units, parent: parent.units, childExplicit: childExplicit),
                        spreadMethod: Self.inheritedGradientValue("spreadMethod", child: child.spreadMethod, parent: parent.spreadMethod, childExplicit: childExplicit),
                        colorInterpolation: Self.inheritedGradientValue("color-interpolation", child: child.colorInterpolation, parent: parent.colorInterpolation, childExplicit: childExplicit),
                        stops: child.stops.isEmpty ? parent.stops : child.stops,
                        transform: Self.inheritedGradientValue("gradientTransform", child: child.transform, parent: parent.transform, childExplicit: childExplicit)
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
                case (.pattern, _), (_, .pattern):
                    break
                }
            }
        }
    }

    /// SVG 1.1 §13.2.3: clamp out-of-order stop offsets; equal offsets keep the last stop
    /// at the overlap point but retain earlier stops for segment interpolation.
    private static func normalizeGradientStops(_ stops: [SVGGradientStop]) -> [SVGGradientStop] {
        guard !stops.isEmpty else { return [] }
        var normalized: [SVGGradientStop] = []
        var maxOffset: CGFloat = -1
        for stop in stops {
            var offset = stop.offset
            if offset < maxOffset {
                offset = maxOffset
            } else {
                maxOffset = offset
            }
            normalized.append(SVGGradientStop(offset: offset, color: stop.color))
        }
        return normalized
    }

    private static func inheritedGradientValue<T>(
        _ key: String,
        child: T,
        parent: T,
        childExplicit: Set<String>
    ) -> T {
        childExplicit.contains(key) ? child : parent
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
        // SVG 1.1: all-zero lists render as a solid stroke (same as "none").
        if out.allSatisfy({ $0 == 0 }) { return [] }
        return out
    }
}
