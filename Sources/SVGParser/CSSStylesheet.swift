import Foundation

/// A CSS selector supported by the incremental stylesheet parser.
enum CSSSelector: Equatable {
    /// Element type selector (e.g. `rect { }`).
    case type(String)
    /// Class selector — all listed classes must be present (e.g. `.foo.bar { }`).
    case classes(Set<String>)
    /// ID selector (e.g. `#one { }`).
    case id(String)
    /// Attribute selector — `value` nil means presence only (e.g. `[points]` or `[transform="scale(2)"]`).
    case attribute(name: String, value: String?)
    /// Descendant combinator (e.g. `#x [points] { }`).
    indirect case descendant(ancestor: CSSSelector, descendant: CSSSelector)
}

/// A single rule from an author `<style>` block.
struct CSSRule {
    let selector: CSSSelector
    let declarations: [(name: String, value: String)]
}

/// Context used to match stylesheet rules against an element.
struct CSSElementContext: Equatable {
    var elementName: String
    var elementId: String?
    var attributes: [String: String]
    var classes: Set<String>
    /// `id` values from ancestor `<g>` / `<symbol>` elements, outermost first.
    var ancestorIds: [String]
}

/// Accumulated author stylesheet rules from `<style>` elements.
struct CSSStylesheet {
    private(set) var rules: [CSSRule] = []

    mutating func append(css text: String) {
        rules.append(contentsOf: CSSStylesheet.parseRules(from: text))
    }

    /// Declarations from all matching rules, in document order.
    func declarations(matching context: CSSElementContext) -> [(name: String, value: String)] {
        var result: [(name: String, value: String)] = []
        for rule in rules where matches(rule.selector, context: context) {
            result.append(contentsOf: rule.declarations)
        }
        return result
    }

    private func matches(_ selector: CSSSelector, context: CSSElementContext) -> Bool {
        switch selector {
        case .type(let name):
            return name == context.elementName
        case .classes(let required):
            return required.isSubset(of: context.classes)
        case .id(let id):
            return context.elementId == id
        case .attribute(let name, let value):
            guard let attrValue = context.attributes[name] else { return false }
            if let value { return attrValue == value }
            return true
        case .descendant(let ancestor, let descendant):
            guard matches(descendant, context: context) else { return false }
            return ancestorMatches(ancestor, context: context)
        }
    }

    private func ancestorMatches(_ selector: CSSSelector, context: CSSElementContext) -> Bool {
        switch selector {
        case .id(let id):
            return context.ancestorIds.contains(id)
        case .classes:
            // Ancestor class matching is not needed for styling-css-02-b; defer until a test requires it.
            return false
        case .type:
            // Ancestor type matching is not needed for styling-css-02-b; defer until a test requires it.
            return false
        case .attribute, .descendant:
            return false
        }
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
                rules.append(CSSRule(selector: selector, declarations: declarations))
            }
        }
        return rules
    }

    private static func parseSelector(_ raw: String) -> CSSSelector? {
        let parts = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        if parts.count == 2,
            let ancestor = parseSimpleSelector(parts[0]),
            let descendant = parseSimpleSelector(parts[1])
        {
            return .descendant(ancestor: ancestor, descendant: descendant)
        }
        return parseSimpleSelector(raw)
    }

    private static func parseSimpleSelector(_ raw: String) -> CSSSelector? {
        let selector = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if selector.hasPrefix("#") {
            let id = String(selector.dropFirst())
            guard !id.isEmpty, isSimpleIdentifier(id) else { return nil }
            return .id(id)
        }
        if selector.hasPrefix(".") {
            let classNames = selector
                .split(whereSeparator: { $0 == "." || $0.isWhitespace })
                .map(String.init)
                .filter { !$0.isEmpty }
            guard !classNames.isEmpty else { return nil }
            return .classes(Set(classNames))
        }
        if selector.hasPrefix("["), selector.hasSuffix("]") {
            return parseAttributeSelector(selector)
        }
        if isSimpleTypeSelector(selector) {
            return .type(selector)
        }
        return nil
    }

    private static func parseAttributeSelector(_ raw: String) -> CSSSelector? {
        let inner = raw.dropFirst().dropLast()
        if let eq = inner.firstIndex(of: "=") {
            let name = inner[..<eq].trimmingCharacters(in: .whitespaces)
            var value = String(inner[inner.index(after: eq)...])
                .trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("\"") && value.hasSuffix("\""))
                || (value.hasPrefix("'") && value.hasSuffix("'"))
            {
                value = String(value.dropFirst().dropLast())
            }
            guard !name.isEmpty else { return nil }
            return .attribute(name: String(name), value: value)
        }
        let name = inner.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return .attribute(name: String(name), value: nil)
    }

    /// True for a single identifier with no combinators or pseudo-classes.
    private static func isSimpleTypeSelector<S: StringProtocol>(_ selector: S) -> Bool {
        guard !selector.isEmpty else { return false }
        for ch in selector where ch == " " || ch == ">" || ch == "+" || ch == "~"
            || ch == ":" || ch == "#" || ch == "." || ch == "["
        {
            return false
        }
        return true
    }

    private static func isSimpleIdentifier(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        guard first.isLetter || first == "-" || first == "_" else { return false }
        for ch in text.dropFirst() where !ch.isLetter && !ch.isNumber && ch != "-" && ch != "_" {
            return false
        }
        return true
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

    private static func parseDeclarations(_ body: String) -> [(name: String, value: String)] {
        var result: [(name: String, value: String)] = []
        for pair in body.split(separator: ";", omittingEmptySubsequences: false) {
            let parts = pair.split(separator: ":", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            result.append((parts[0], parts[1]))
        }
        return result
    }
}
