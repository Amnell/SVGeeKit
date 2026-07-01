import Foundation

/// A CSS selector supported by the incremental stylesheet parser.
enum CSSSelector: Equatable {
    /// Element type selector (e.g. `rect { }`).
    case type(String)
    /// Class selector — all listed classes must be present (e.g. `.foo.bar { }`).
    case classes(Set<String>)
}

/// A single rule from an author `<style>` block.
struct CSSRule {
    let selector: CSSSelector
    let declarations: [(name: String, value: String)]
}

/// Accumulated author stylesheet rules from `<style>` elements.
struct CSSStylesheet {
    private(set) var rules: [CSSRule] = []

    mutating func append(css text: String) {
        rules.append(contentsOf: CSSStylesheet.parseRules(from: text))
    }

    /// Declarations from all matching rules, in document order.
    func declarations(matchingElement elementName: String, classes: Set<String>) -> [(name: String, value: String)] {
        var result: [(name: String, value: String)] = []
        for rule in rules {
            switch rule.selector {
            case .type(let name) where name == elementName:
                result.append(contentsOf: rule.declarations)
            case .classes(let required) where required.isSubset(of: classes):
                result.append(contentsOf: rule.declarations)
            default:
                break
            }
        }
        return result
    }

    private static func parseRules(from text: String) -> [CSSRule] {
        let stripped = removeComments(from: text)
        var rules: [CSSRule] = []

        for block in stripped.split(separator: "}", omittingEmptySubsequences: true) {
            guard let open = block.firstIndex(of: "{") else { continue }
            let selector = block[..<open]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let body = block[block.index(after: open)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if selector.hasPrefix(".") {
                let classNames = selector
                    .split(whereSeparator: { $0 == "." || $0.isWhitespace })
                    .map(String.init)
                    .filter { !$0.isEmpty }
                guard !classNames.isEmpty else { continue }
                rules.append(
                    CSSRule(
                        selector: .classes(Set(classNames)),
                        declarations: parseDeclarations(body)
                    )
                )
            } else if isSimpleTypeSelector(selector) {
                rules.append(
                    CSSRule(
                        selector: .type(String(selector)),
                        declarations: parseDeclarations(body)
                    )
                )
            }
        }
        return rules
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
