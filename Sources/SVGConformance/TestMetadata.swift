import Foundation

/// Descriptive metadata extracted from a vendored W3C SVG test file.
///
/// Mirrors what's useful to a human reviewer when comparing the SVGeeKit
/// render against the W3C reference image:
/// - `<title>` and `<desc>` from the SVG root,
/// - the W3C-specific `<SVGTestCase>` / `<OperatorScript>` block describing
///   what the test is verifying (owner, reviewer, status, paragraphs of
///   operator instructions).
///
/// Pure data, no I/O beyond the static `extract(from:)` factory.
public struct SVGTestMetadata: Sendable, Equatable {
    public var title: String?
    public var description: String?
    public var owner: String?
    public var reviewer: String?
    public var status: String?
    public var version: String?
    public var operatorParagraphs: [String]

    public static let empty = SVGTestMetadata(operatorParagraphs: [])

    public init(
        title: String? = nil,
        description: String? = nil,
        owner: String? = nil,
        reviewer: String? = nil,
        status: String? = nil,
        version: String? = nil,
        operatorParagraphs: [String] = []
    ) {
        self.title = title
        self.description = description
        self.owner = owner
        self.reviewer = reviewer
        self.status = status
        self.version = version
        self.operatorParagraphs = operatorParagraphs
    }

    public var isEmpty: Bool {
        title == nil && description == nil && owner == nil && reviewer == nil
            && status == nil && operatorParagraphs.isEmpty
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

    private var title: String?
    private var desc: String?
    private var owner: String?
    private var reviewer: String?
    private var status: String?
    private var version: String?
    private var paragraphs: [String] = []

    private enum Capture { case title, desc, paragraph }
    private var capture: Capture?
    private var buffer = ""

    func build() -> SVGTestMetadata {
        SVGTestMetadata(
            title: title?.normalizedWhitespace,
            description: desc?.normalizedWhitespace,
            owner: owner,
            reviewer: reviewer,
            status: status,
            version: version,
            operatorParagraphs: paragraphs.compactMap { $0.normalizedWhitespace }
        )
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
            startCapture(.title)
        case "desc":
            if desc == nil { startCapture(.desc) }
        case "SVGTestCase":
            // Some suites carry attributes on the wrapper itself.
            owner = owner ?? attributeDict["owner"]
            reviewer = reviewer ?? attributeDict["reviewer"]
            status = status ?? attributeDict["status"]
            version = version ?? attributeDict["version"]
            if let attrDesc = attributeDict["desc"], desc == nil {
                desc = attrDesc
            }
        case "OperatorScript":
            // Some files put the rich metadata on OperatorScript instead.
            owner = owner ?? attributeDict["owner"]
            reviewer = reviewer ?? attributeDict["reviewer"]
            status = status ?? attributeDict["status"]
            version = version ?? attributeDict["version"]
        case "Paragraph":
            startCapture(.paragraph)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard capture != nil else { return }
        buffer.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard let active = capture else { return }
        let local = localName(elementName)
        let matches: Bool = {
            switch active {
            case .title: return local == "title"
            case .desc: return local == "desc"
            case .paragraph: return local == "Paragraph"
            }
        }()
        guard matches else { return }

        let text = buffer
        buffer.removeAll(keepingCapacity: true)
        capture = nil

        switch active {
        case .title:
            if title == nil { title = text }
        case .desc:
            if desc == nil { desc = text }
        case .paragraph:
            paragraphs.append(text)
        }
    }

    private func startCapture(_ which: Capture) {
        capture = which
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
