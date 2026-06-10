import Foundation

/// Coarse feature tag for grouping conformance tests. Aligns with W3C SVG 1.1
/// chapter prefixes used in test filenames (e.g. `paths-data-01-t.svg`).
public enum SVGFeatureTag: String, CaseIterable, Sendable, Codable {
    case shapes
    case paths
    case painting
    case coords
    case pservers
    case `struct`
    case styling
    case masking
    case text
    case fonts
    case `extend`
    case filters
    case `interact`
    case linking
    case render
    case script
    case animate
    case color
    case metadata
    case other

    /// Derive a tag from the leading chapter prefix of a W3C 1.1 test filename.
    /// Returns `.other` if the prefix is unrecognized.
    public static func fromW3CFilename(_ filename: String) -> SVGFeatureTag {
        let stem = (filename as NSString).deletingPathExtension
        guard let firstDash = stem.firstIndex(of: "-") else { return .other }
        let prefix = String(stem[..<firstDash]).lowercased()
        return SVGFeatureTag(rawValue: prefix) ?? .other
    }
}
