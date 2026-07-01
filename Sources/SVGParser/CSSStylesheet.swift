import Foundation

/// A single CSS class selector rule (e.g. `.foo.bar { fill: red; }`).
struct CSSClassRule {
    /// All listed classes must be present on the element.
    let requiredClasses: Set<String>
    let declarations: [(name: String, value: String)]
}

/// Accumulated author stylesheet rules from `<style>` elements.
struct CSSStylesheet {
    private(set) var classRules: [CSSClassRule] = []

    mutating func append(css text: String) {
        classRules.append(contentsOf: CSSStylesheet.parseClassRules(from: text))
    }

    /// Declarations from all matching class rules, in document order.
    func declarations(matchingClasses classes: Set<String>) -> [(name: String, value: String)] {
        var result: [(name: String, value: String)] = []
        for rule in classRules where rule.requiredClasses.isSubset(of: classes) {
            result.append(contentsOf: rule.declarations)
        }
        return result
    }

  private static func parseClassRules(from text: String) -> [CSSClassRule] {
        let stripped = removeComments(from: text)
        var rules: [CSSClassRule] = []

        for block in stripped.split(separator: "}", omittingEmptySubsequences: true) {
            guard let open = block.firstIndex(of: "{") else { continue }
            let selector = block[..<open]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let body = block[block.index(after: open)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard selector.hasPrefix(".") else { continue }

            let classNames = selector
                .split(whereSeparator: { $0 == "." || $0.isWhitespace })
                .map(String.init)
                .filter { !$0.isEmpty }
            guard !classNames.isEmpty else { continue }

            rules.append(
                CSSClassRule(
                    requiredClasses: Set(classNames),
                    declarations: parseDeclarations(body)
                )
            )
        }
        return rules
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
