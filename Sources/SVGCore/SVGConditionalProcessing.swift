import Foundation

/// User-agent capabilities consulted when evaluating SVG conditional-processing
/// attributes on `<switch>` children.
public struct SVGConditionalProcessingContext: Equatable, Sendable {
    public var preferredLanguages: [String]
    public var supportedExtensions: Set<String>
    public var supportedFeatures: Set<String>
    public var supportedFormats: Set<String>

    public init(
        preferredLanguages: [String],
        supportedExtensions: Set<String> = [],
        supportedFeatures: Set<String> = Self.defaultSupportedFeatures,
        supportedFormats: Set<String> = []
    ) {
        self.preferredLanguages = preferredLanguages
        self.supportedExtensions = supportedExtensions
        self.supportedFeatures = supportedFeatures
        self.supportedFormats = supportedFormats
    }

    /// Snapshot of the host environment's language preferences and the static
    /// renderer's declared SVG 1.1 feature support.
    public static func current() -> SVGConditionalProcessingContext {
        SVGConditionalProcessingContext(preferredLanguages: Locale.preferredLanguages)
    }

    /// Features SVGeeKit's static renderer can satisfy for `requiredFeatures` tests.
    public static let defaultSupportedFeatures: Set<String> = [
        "http://www.w3.org/TR/SVG11/feature#BasicStructure",
        "http://www.w3.org/TR/SVG11/feature#BasicText",
        "http://www.w3.org/TR/SVG11/feature#BasicPaintAttribute",
        "http://www.w3.org/TR/SVG11/feature#BasicGraphicsAttribute",
        "http://www.w3.org/TR/SVG11/feature#BasicClip",
        "http://www.w3.org/TR/SVG11/feature#BasicFilter",
        "http://www.w3.org/TR/SVG11/feature#BasicFont",
        "http://www.w3.org/TR/SVG11/feature#Markup",
        "http://www.w3.org/TR/SVG11/feature#CSS",
        "http://www.w3.org/TR/SVG11/feature#BasicDataURI",
        "http://www.w3.org/TR/SVG11/feature#Shape",
        "http://www.w3.org/TR/SVG11/feature#Text",
        "http://www.w3.org/TR/SVG11/feature#Animation",
        "http://www.w3.org/TR/SVG11/feature#ConditionalProcessing",
    ]
}

public enum SVGConditionalProcessing {
    /// Returns whether all specified test attributes on an element evaluate to true.
    /// An element with no test attributes always evaluates to true.
    public static func evaluate(
        attributes: [String: String],
        context: SVGConditionalProcessingContext
    ) -> Bool {
        if let raw = attributes["requiredFeatures"],
           !evaluateRequiredList(raw, supported: context.supportedFeatures) {
            return false
        }
        if let raw = attributes["requiredExtensions"],
           !evaluateRequiredList(raw, supported: context.supportedExtensions) {
            return false
        }
        if let raw = attributes["requiredFormats"],
           !evaluateRequiredList(raw, supported: context.supportedFormats) {
            return false
        }
        if let raw = attributes["systemLanguage"],
           !evaluateSystemLanguage(raw, preferredLanguages: context.preferredLanguages) {
            return false
        }
        return true
    }

    private static func evaluateRequiredList(_ raw: String, supported: Set<String>) -> Bool {
        let items = raw.split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !items.isEmpty else { return true }
        return items.allSatisfy { supported.contains($0) }
    }

    /// SVG 1.1 §5.8.2 — `systemLanguage` is a comma-separated list of RFC 3066 tags.
    public static func evaluateSystemLanguage(
        _ raw: String,
        preferredLanguages: [String]
    ) -> Bool {
        let candidates = raw.split(separator: ",")
            .map { normalizeLanguageTag(String($0)) }
            .filter { !$0.isEmpty }
        guard !candidates.isEmpty else { return true }
        guard !preferredLanguages.isEmpty else { return false }

        for userLanguage in preferredLanguages {
            let normalizedUser = normalizeLanguageTag(userLanguage)
            for candidate in candidates where languageMatches(user: normalizedUser, candidate: candidate) {
                return true
            }
        }
        return false
    }

    private static func languageMatches(user: String, candidate: String) -> Bool {
        if user == candidate { return true }
        return user.hasPrefix(candidate + "-")
    }

    private static func normalizeLanguageTag(_ tag: String) -> String {
        var normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        let primary = normalized.split(separator: "-", maxSplits: 1).first.map(String.init) ?? normalized
        if primary == "iw" { normalized = "he" + normalized.dropFirst(2) }
        return normalized
    }
}
