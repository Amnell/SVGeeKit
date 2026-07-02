import Foundation

/// Descriptive metadata extracted from a vendored W3C SVG test file.
///
/// Mirrors what's useful to a human reviewer when comparing the SVGeeKit
/// render against the W3C reference image:
/// - `<title>` and `<desc>` from the SVG root,
/// - the W3C-specific `<d:SVGTestCase>` wrapper carrying author / reviewer /
///   status attributes,
/// - the three xhtml-paragraph sections inside that wrapper:
///   `<d:testDescription>`, `<d:operatorScript>`, `<d:passCriteria>`.
///
/// Pure data, no I/O beyond the static `extract(from:)` factory.
public struct SVGTestMetadata: Sendable, Equatable {
    public var title: String?
    public var description: String?
    public var author: String?
    public var reviewer: String?
    public var status: String?
    public var version: String?
    public var testDescriptionParagraphs: [String]
    public var operatorScriptParagraphs: [String]
    public var passCriteriaParagraphs: [String]

    public static let empty = SVGTestMetadata()

    public init(
        title: String? = nil,
        description: String? = nil,
        author: String? = nil,
        reviewer: String? = nil,
        status: String? = nil,
        version: String? = nil,
        testDescriptionParagraphs: [String] = [],
        operatorScriptParagraphs: [String] = [],
        passCriteriaParagraphs: [String] = []
    ) {
        self.title = title
        self.description = description
        self.author = author
        self.reviewer = reviewer
        self.status = status
        self.version = version
        self.testDescriptionParagraphs = testDescriptionParagraphs
        self.operatorScriptParagraphs = operatorScriptParagraphs
        self.passCriteriaParagraphs = passCriteriaParagraphs
    }

    public var isEmpty: Bool {
        title == nil && description == nil && author == nil && reviewer == nil
            && status == nil && version == nil
            && testDescriptionParagraphs.isEmpty
            && operatorScriptParagraphs.isEmpty
            && passCriteriaParagraphs.isEmpty
    }
}

public extension SVGTestMetadata {

    static func extract(from url: URL) -> SVGTestMetadata {
        guard let data = try? Data(contentsOf: url) else { return .empty }
        return extract(from: data)
    }

    static func extract(from data: Data) -> SVGTestMetadata {
        let parser = XMLParser(data: data)
        let delegate = MetadataDelegate()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.parse()
        return delegate.build()
    }
}

private final class MetadataDelegate: NSObject, XMLParserDelegate {

    private enum Section { case testDescription, operatorScript, passCriteria }

    private var title: String?
    private var desc: String?
    private var author: String?
    private var reviewer: String?
    private var status: String?
    private var version: String?
    private var testDescriptionParagraphs: [String] = []
    private var operatorScriptParagraphs: [String] = []
    private var passCriteriaParagraphs: [String] = []

    /// Which W3C section we're currently inside (paragraphs are routed here).
    private var currentSection: Section?
    /// Depth inside the current `<p>` / `<li>` element. Treat nested text as
    /// belonging to the outermost one (no W3C test uses nesting in practice).
    private var paragraphDepth = 0
    /// Whether the currently-buffered paragraph originated from a `<li>`, so it
    /// can be rendered with a bullet prefix.
    private var isListItem = false
    /// Generic root-level capture for `<title>` / `<desc>`.
    private var rootCapture: RootCapture?
    private var buffer = ""

    private enum RootCapture { case title, desc }

    func build() -> SVGTestMetadata {
        SVGTestMetadata(
            title: title?.normalizedWhitespace.flatMap(Self.cleanedRCSKeyword),
            description: desc?.normalizedWhitespace,
            author: author?.normalizedWhitespace,
            reviewer: reviewer?.normalizedWhitespace,
            status: status?.normalizedWhitespace,
            version: version?.normalizedWhitespace.flatMap(Self.cleanedRCSKeyword),
            testDescriptionParagraphs: testDescriptionParagraphs.compactMap(\.normalizedWhitespace),
            operatorScriptParagraphs: operatorScriptParagraphs.compactMap(\.normalizedWhitespace),
            passCriteriaParagraphs: passCriteriaParagraphs.compactMap(\.normalizedWhitespace)
        )
    }

    /// Strip CVS/RCS keyword wrappers like `$RCSfile: foo.svg,v $` or
    /// `$Revision: 1.7 $`. Returns `nil` when the value reduces to nothing useful.
    private static func cleanedRCSKeyword(_ value: String) -> String? {
        // Match `$Keyword: actual value $` and pull the inner value.
        if value.hasPrefix("$"), value.hasSuffix("$"),
           let colon = value.firstIndex(of: ":") {
            let inner = value[value.index(after: colon)..<value.index(before: value.endIndex)]
            let trimmed = inner.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        return value
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        // Match on the local name so default-namespaced documents work.
        let local = localName(elementName)
        switch local {
        case "title":
            if rootCapture == nil && currentSection == nil { startRootCapture(.title) }
        case "desc":
            if desc == nil && currentSection == nil { startRootCapture(.desc) }
        case "SVGTestCase":
            // W3C uses `author`; some legacy in-house variants used `owner`.
            author = author ?? attributeDict["author"] ?? attributeDict["owner"]
            reviewer = reviewer ?? attributeDict["reviewer"]
            status = status ?? attributeDict["status"]
            version = version ?? attributeDict["version"]
        case "testDescription":
            currentSection = .testDescription
        case "operatorScript", "OperatorScript":
            currentSection = .operatorScript
            // Some legacy files carry attrs here instead of on SVGTestCase.
            author = author ?? attributeDict["author"] ?? attributeDict["owner"]
            reviewer = reviewer ?? attributeDict["reviewer"]
            status = status ?? attributeDict["status"]
            version = version ?? attributeDict["version"]
        case "passCriteria":
            currentSection = .passCriteria
        case "p", "Paragraph", "li":
            // Capture list items (`<li>`) as standalone paragraphs so pass
            // criteria expressed as `<ul>` bullet lists aren't dropped. They
            // never nest inside a `<p>` in practice, but guard anyway.
            if currentSection != nil {
                if paragraphDepth == 0 {
                    buffer.removeAll(keepingCapacity: true)
                    isListItem = (local == "li")
                }
                paragraphDepth += 1
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if rootCapture != nil || paragraphDepth > 0 {
            buffer.append(string)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let local = localName(elementName)

        // Root-level title / desc.
        if let active = rootCapture {
            let matches = (active == .title && local == "title")
                || (active == .desc && local == "desc")
            if matches {
                let text = buffer
                buffer.removeAll(keepingCapacity: true)
                rootCapture = nil
                switch active {
                case .title: if title == nil { title = text }
                case .desc: if desc == nil { desc = text }
                }
                return
            }
        }

        switch local {
        case "p", "Paragraph", "li":
            guard paragraphDepth > 0 else { return }
            paragraphDepth -= 1
            guard paragraphDepth == 0, let section = currentSection else { return }
            // Prefix list items with a bullet so they read as a list.
            let text = isListItem ? "• " + buffer : buffer
            buffer.removeAll(keepingCapacity: true)
            isListItem = false
            switch section {
            case .testDescription: testDescriptionParagraphs.append(text)
            case .operatorScript: operatorScriptParagraphs.append(text)
            case .passCriteria: passCriteriaParagraphs.append(text)
            }
        case "testDescription", "operatorScript", "OperatorScript", "passCriteria":
            currentSection = nil
            paragraphDepth = 0
        default:
            break
        }
    }

    private func startRootCapture(_ which: RootCapture) {
        rootCapture = which
        buffer.removeAll(keepingCapacity: true)
    }

    private func localName(_ qName: String) -> String {
        guard let colon = qName.firstIndex(of: ":") else { return qName }
        return String(qName[qName.index(after: colon)...])
    }
}

private extension String {
    /// Collapse runs of whitespace and trim. Returns `nil` if the result is empty.
    var normalizedWhitespace: String? {
        let collapsed = split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }
}
