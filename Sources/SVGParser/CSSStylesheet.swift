import Foundation

enum CSSCombinator: Equatable {
    case descendant
    case child
    case adjacentSibling
}

enum CSSAttributeOperator: Equatable {
    case equals
    case includes
    case dashPrefix
}

enum CSSSimpleSelector: Equatable {
    case universal
    case type(String)
    case id(String)
    case `class`(String)
    case attribute(name: String, op: CSSAttributeOperator?, value: String?)
    case firstChild
}

struct CSSCompoundSelector: Equatable {
    let simpleSelectors: [CSSSimpleSelector]
}

/// Selector chain represented left-to-right and evaluated right-to-left.
struct CSSSelector: Equatable {
    let compounds: [CSSCompoundSelector]
    let combinators: [CSSCombinator]
}

struct CSSSpecificity: Equatable, Comparable {
    let a: Int  // ID selectors
    let b: Int  // class/attribute/pseudo-class selectors
    let c: Int  // type selectors

    static func < (lhs: CSSSpecificity, rhs: CSSSpecificity) -> Bool {
        if lhs.a != rhs.a { return lhs.a < rhs.a }
        if lhs.b != rhs.b { return lhs.b < rhs.b }
        return lhs.c < rhs.c
    }
}

/// Lightweight node context used for selector matching.
final class CSSNodeContext {
    let elementName: String
    let elementId: String?
    let attributes: [String: String]
    let classes: Set<String>
    let isFirstChild: Bool
    weak var parent: CSSNodeContext?
    var previousSibling: CSSNodeContext?

    init(
        elementName: String,
        elementId: String?,
        attributes: [String: String],
        classes: Set<String>,
        isFirstChild: Bool,
        parent: CSSNodeContext?,
        previousSibling: CSSNodeContext?
    ) {
        self.elementName = elementName
        self.elementId = elementId
        self.attributes = attributes
        self.classes = classes
        self.isFirstChild = isFirstChild
        self.parent = parent
        self.previousSibling = previousSibling
    }
}

/// A single declaration from an author stylesheet or inline style block.
struct CSSDeclaration: Equatable {
    let name: String
    let value: String
    let important: Bool
}

/// A single rule from an author `<style>` block.
struct CSSRule {
    let selector: CSSSelector
    let specificity: CSSSpecificity
    let declarations: [CSSDeclaration]
}

/// Accumulated author stylesheet rules from `<style>` elements.
struct CSSStylesheet {
    private(set) var rules: [CSSRule] = []

    /// Known SVG presentation attributes that may appear as XML attributes.
    static let paintPresentationAttributes: Set<String> = [
        "fill", "fill-opacity", "fill-rule", "stroke", "stroke-opacity", "stroke-width",
        "stroke-linecap", "stroke-linejoin", "stroke-miterlimit", "stroke-dasharray",
        "stroke-dashoffset", "opacity", "color", "visibility", "display", "clip-path", "mask",
        "stop-color", "stop-opacity",
    ]

    var isEmpty: Bool { rules.isEmpty }

    mutating func append(css text: String, importCSS: ((String) -> String?)? = nil) {
        let expanded = Self.expandImports(in: text, importCSS: importCSS)
        rules.append(contentsOf: CSSStylesheet.parseRules(from: expanded))
    }

    /// Declarations from all matching rules, in document order.
    func declarations(matching node: CSSNodeContext) -> [CSSDeclaration] {
        let matched = rules.enumerated()
            .filter { _, rule in matches(rule.selector, node: node) }
            .sorted { lhs, rhs in
                if lhs.element.specificity != rhs.element.specificity {
                    return lhs.element.specificity < rhs.element.specificity
                }
                // Same specificity: later source order wins, so apply earlier first.
                return lhs.offset < rhs.offset
            }

        var result: [CSSDeclaration] = []
        for (_, rule) in matched {
            result.append(contentsOf: rule.declarations)
        }
        return result
    }

    private func matches(_ selector: CSSSelector, node: CSSNodeContext) -> Bool {
        guard !selector.compounds.isEmpty,
              selector.combinators.count + 1 == selector.compounds.count else { return false }
        return matches(selector: selector, compoundIndex: selector.compounds.count - 1, node: node)
    }

    private func matches(selector: CSSSelector, compoundIndex index: Int, node: CSSNodeContext) -> Bool {
        guard matches(selector.compounds[index], node: node) else { return false }
        guard index > 0 else { return true }

        let combinator = selector.combinators[index - 1]
        switch combinator {
        case .child:
            guard let parent = node.parent else { return false }
            return matches(selector: selector, compoundIndex: index - 1, node: parent)
        case .adjacentSibling:
            guard let previous = node.previousSibling else { return false }
            return matches(selector: selector, compoundIndex: index - 1, node: previous)
        case .descendant:
            var ancestor = node.parent
            while let candidate = ancestor {
                if matches(selector: selector, compoundIndex: index - 1, node: candidate) {
                    return true
                }
                ancestor = candidate.parent
            }
            return false
        }
    }

    private func matches(_ compound: CSSCompoundSelector, node: CSSNodeContext) -> Bool {
        for simple in compound.simpleSelectors {
            switch simple {
            case .universal:
                continue
            case .type(let name):
                if node.elementName != name { return false }
            case .id(let id):
                if node.elementId != id { return false }
            case .class(let name):
                if !node.classes.contains(name) { return false }
            case .firstChild:
                if !node.isFirstChild { return false }
            case .attribute(let name, let op, let value):
                guard let attrValue = node.attributes[name] else { return false }
                guard let op else { continue }
                guard let value else { return false }
                switch op {
                case .equals:
                    if attrValue != value { return false }
                case .includes:
                    let tokens = attrValue.split(whereSeparator: \.isWhitespace).map(String.init)
                    if !tokens.contains(value) { return false }
                case .dashPrefix:
                    if attrValue != value && !attrValue.hasPrefix("\(value)-") { return false }
                }
            }
        }
        return true
    }

    private static func expandImports(in text: String, importCSS: ((String) -> String?)?) -> String {
        guard let importCSS else { return text }
        var imported = ""
        var body = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix("@import"),
               let href = parseImportURL(trimmed),
               let css = importCSS(href)
            {
                imported += expandImports(in: css, importCSS: importCSS)
                if !imported.isEmpty, !imported.hasSuffix("\n") { imported += "\n" }
                continue
            }
            body += line
            body += "\n"
        }
        return imported + body
    }

    private static func parseImportURL(_ raw: String) -> String? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("@import") else { return nil }
        trimmed = String(trimmed.dropFirst("@import".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(";") {
            trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed.lowercased().hasPrefix("url("), trimmed.hasSuffix(")") {
            var inner = String(trimmed.dropFirst(4).dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            if (inner.hasPrefix("\"") && inner.hasSuffix("\"")) || (inner.hasPrefix("'") && inner.hasSuffix("'")) {
                inner = String(inner.dropFirst().dropLast())
            }
            let href = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            return href.isEmpty ? nil : href
        }
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            trimmed = String(trimmed.dropFirst().dropLast())
        }
        let href = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        return href.isEmpty ? nil : href
    }

    private static func parseRules(from text: String) -> [CSSRule] {
        let stripped = removeComments(from: text)
        var rules: [CSSRule] = []

        for block in stripped.split(separator: "}", omittingEmptySubsequences: true) {
            guard let open = block.firstIndex(of: "{") else { continue }
            let selectorText = block[..<open]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let body = block[block.index(after: open)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let declarations = parseDeclarations(body)

            for part in selectorText.split(separator: ",", omittingEmptySubsequences: true) {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let selector = parseSelector(trimmed) else { continue }
                rules.append(
                    CSSRule(
                        selector: selector,
                        specificity: specificity(of: selector),
                        declarations: declarations
                    )
                )
            }
        }
        return rules
    }

    private static func parseSelector(_ raw: String) -> CSSSelector? {
        let tokens = tokenizeSelector(raw)
        guard !tokens.isEmpty else { return nil }

        var compounds: [CSSCompoundSelector] = []
        var combinators: [CSSCombinator] = []

        for token in tokens {
            switch token {
            case ">":
                combinators.append(.child)
            case "+":
                combinators.append(.adjacentSibling)
            case " ":
                combinators.append(.descendant)
            default:
                guard let compound = parseCompoundSelector(token) else { return nil }
                compounds.append(compound)
            }
        }
        guard !compounds.isEmpty, compounds.count == combinators.count + 1 else { return nil }
        return CSSSelector(compounds: compounds, combinators: combinators)
    }

    private static func parseCompoundSelector(_ raw: String) -> CSSCompoundSelector? {
        let selector = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selector.isEmpty else { return nil }
        var simple: [CSSSimpleSelector] = []
        var index = selector.startIndex

        while index < selector.endIndex {
            let ch = selector[index]
            if ch == "*" {
                simple.append(.universal)
                index = selector.index(after: index)
                continue
            }
            if ch == "#" {
                let start = selector.index(after: index)
                let end = readIdentifierEnd(selector, from: start)
                guard end > start else { return nil }
                simple.append(.id(String(selector[start..<end])))
                index = end
                continue
            }
            if ch == "." {
                let start = selector.index(after: index)
                let end = readIdentifierEnd(selector, from: start)
                guard end > start else { return nil }
                simple.append(.class(String(selector[start..<end])))
                index = end
                continue
            }
            if ch == ":" {
                let suffix = selector[index...]
                if suffix.hasPrefix(":first-child") {
                    simple.append(.firstChild)
                    index = selector.index(index, offsetBy: 12)
                    continue
                }
                return nil
            }
            if ch == "[" {
                guard let close = selector[index...].firstIndex(of: "]") else { return nil }
                let inner = String(selector[selector.index(after: index)..<close])
                guard let attr = parseAttributeSelector(inner) else { return nil }
                simple.append(attr)
                index = selector.index(after: close)
                continue
            }

            let end = readIdentifierEnd(selector, from: index)
            guard end > index else { return nil }
            simple.append(.type(String(selector[index..<end])))
            index = end
        }

        return simple.isEmpty ? nil : CSSCompoundSelector(simpleSelectors: simple)
    }

    private static func parseAttributeSelector(_ raw: String) -> CSSSimpleSelector? {
        let content = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = content.range(of: "~=") {
            let name = content[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let value = content[range.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !value.isEmpty else { return nil }
            return .attribute(name: String(name), op: .includes, value: unquote(value))
        }
        if let range = content.range(of: "|=") {
            let name = content[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let value = content[range.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !value.isEmpty else { return nil }
            return .attribute(name: String(name), op: .dashPrefix, value: unquote(value))
        }
        if let range = content.range(of: "=") {
            let name = content[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let value = content[range.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !value.isEmpty else { return nil }
            return .attribute(name: String(name), op: .equals, value: unquote(value))
        }
        return content.isEmpty ? nil : .attribute(name: content, op: nil, value: nil)
    }

    private static func tokenizeSelector(_ raw: String) -> [String] {
        var tokens: [String] = []
        var buffer = ""
        var i = raw.startIndex
        var inBrackets = false
        var quote: Character?

        func flushBuffer() {
            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { tokens.append(trimmed) }
            buffer = ""
        }

        while i < raw.endIndex {
            let ch = raw[i]
            if quote != nil {
                buffer.append(ch)
                if ch == quote { quote = nil }
                i = raw.index(after: i)
                continue
            }
            if inBrackets {
                buffer.append(ch)
                if ch == "\"" || ch == "'" {
                    quote = ch
                } else if ch == "]" {
                    inBrackets = false
                }
                i = raw.index(after: i)
                continue
            }
            if ch == "[" {
                inBrackets = true
                buffer.append(ch)
                i = raw.index(after: i)
                continue
            }
            if ch == ">" || ch == "+" {
                flushBuffer()
                tokens.append(String(ch))
                i = raw.index(after: i)
                while i < raw.endIndex, raw[i].isWhitespace {
                    i = raw.index(after: i)
                }
                continue
            }
            if ch.isWhitespace {
                flushBuffer()
                var j = raw.index(after: i)
                while j < raw.endIndex, raw[j].isWhitespace {
                    j = raw.index(after: j)
                }
                if j < raw.endIndex, raw[j] != ">", raw[j] != "+", !tokens.isEmpty,
                   tokens.last != " ", tokens.last != ">", tokens.last != "+"
                {
                    tokens.append(" ")
                }
                i = j
                continue
            }
            buffer.append(ch)
            i = raw.index(after: i)
        }
        flushBuffer()
        return tokens
    }

    private static func readIdentifierEnd(_ text: String, from start: String.Index) -> String.Index {
        var i = start
        while i < text.endIndex {
            let ch = text[i]
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" {
                i = text.index(after: i)
                continue
            }
            break
        }
        return i
    }

    private static func unquote(_ value: String) -> String {
        if (value.hasPrefix("\"") && value.hasSuffix("\""))
            || (value.hasPrefix("'") && value.hasSuffix("'"))
        {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func specificity(of selector: CSSSelector) -> CSSSpecificity {
        var a = 0
        var b = 0
        var c = 0
        for compound in selector.compounds {
            for simple in compound.simpleSelectors {
                switch simple {
                case .id:
                    a += 1
                case .class, .attribute, .firstChild:
                    b += 1
                case .type:
                    c += 1
                case .universal:
                    break
                }
            }
        }
        return CSSSpecificity(a: a, b: b, c: c)
    }

    private static func removeComments(from text: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "/", text.index(after: index) < text.endIndex,
                text[text.index(after: index)] == "*"
            {
                let searchStart = text.index(index, offsetBy: 2)
                if let close = text[searchStart...].range(of: "*/") {
                    index = close.upperBound
                    continue
                }
            }
            result.append(text[index])
            index = text.index(after: index)
        }
        return result
    }

    private static func parseDeclarations(_ body: String) -> [CSSDeclaration] {
        var result: [CSSDeclaration] = []
        for pair in body.split(separator: ";", omittingEmptySubsequences: false) {
            let parts = pair.split(separator: ":", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            guard let declaration = parseProperty(namePart: parts[0], valuePart: parts[1]) else { continue }
            result.append(declaration)
        }
        return result
    }

    static func parseInlineDeclaration(namePart: String, valuePart: String) -> CSSDeclaration? {
        parseProperty(namePart: namePart, valuePart: valuePart)
    }

    private static func parseProperty(namePart: String, valuePart: String) -> CSSDeclaration? {
        let trimmedValue = valuePart.trimmingCharacters(in: .whitespaces)
        guard !trimmedValue.isEmpty else { return nil }
        let lowerName = namePart.trimmingCharacters(in: .whitespaces).lowercased()
        guard !lowerName.isEmpty else { return nil }

        var value = trimmedValue
        var important = false
        if let range = value.range(of: "!important", options: [.caseInsensitive, .backwards]) {
            let suffix = value[range.upperBound...].trimmingCharacters(in: .whitespaces)
            guard suffix.isEmpty else {
                return CSSDeclaration(name: lowerName, value: trimmedValue, important: false)
            }
            important = true
            value = value[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        }
        guard !value.isEmpty else { return nil }
        return CSSDeclaration(name: lowerName, value: value, important: important)
    }
}

/// Pre-scans SVG XML for author `<style>` blocks so rules apply regardless of
/// document order relative to styled elements.
enum CSSStylesheetCollector {
    static func collect(from data: Data, importCSS: ((String) -> String?)? = nil) -> CSSStylesheet {
        let parser = XMLParser(data: data)
        let delegate = Delegate(importCSS: importCSS)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        _ = parser.parse()
        return delegate.stylesheet
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var stylesheet = CSSStylesheet()
        private let importCSS: ((String) -> String?)?
        private var styleTextBuffer: String?

        init(importCSS: ((String) -> String?)?) {
            self.importCSS = importCSS
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            guard elementName == "style" else { return }
            let type = attributeDict["type"]?.trimmingCharacters(in: .whitespaces).lowercased()
            if type == nil || type == "text/css" {
                styleTextBuffer = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if styleTextBuffer != nil {
                styleTextBuffer?.append(string)
            }
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if styleTextBuffer != nil,
               let string = String(data: CDATABlock, encoding: .utf8) {
                styleTextBuffer?.append(string)
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            guard elementName == "style", let buffer = styleTextBuffer else { return }
            stylesheet.append(css: buffer, importCSS: importCSS)
            styleTextBuffer = nil
        }

        func parser(
            _ parser: XMLParser,
            foundProcessingInstructionWithTarget target: String,
            data: String?
        ) {
            guard target == "xml-stylesheet", let data else { return }
            guard Self.isCSSStylesheetPI(data) else { return }
            guard let href = Self.hrefFromStylesheetPI(data) else { return }
            guard let css = importCSS?(href) else { return }
            stylesheet.append(css: css, importCSS: importCSS)
        }

        private static func isCSSStylesheetPI(_ data: String) -> Bool {
            guard let typeRange = data.range(of: "type=") else { return true }
            let afterType = data[typeRange.upperBound...]
            guard let quote = afterType.first, quote == "\"" || quote == "'" else { return true }
            let valueStart = afterType.index(afterType.startIndex, offsetBy: 1)
            guard let quoteEnd = afterType[valueStart...].firstIndex(of: quote) else { return true }
            let typeValue = afterType[valueStart..<quoteEnd].trimmingCharacters(in: .whitespacesAndNewlines)
            return typeValue.isEmpty || typeValue.lowercased() == "text/css"
        }

        private static func hrefFromStylesheetPI(_ data: String) -> String? {
            guard let hrefRange = data.range(of: "href=") else { return nil }
            let afterHref = data[hrefRange.upperBound...].trimmingCharacters(in: .whitespaces)
            guard let quote = afterHref.first, quote == "\"" || quote == "'" else { return nil }
            let valueStart = afterHref.index(afterHref.startIndex, offsetBy: 1)
            guard let quoteEnd = afterHref[valueStart...].firstIndex(of: quote) else { return nil }
            let href = String(afterHref[valueStart..<quoteEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            return href.isEmpty ? nil : href
        }
    }
}
