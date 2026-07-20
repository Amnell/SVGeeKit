import Foundation

/// Parsed `<color-profile>` (SVG 1.1 §12.3). ICC bytes are loaded at parse time
/// when the active `SVGResourcePolicy` allows the `href`.
public struct SVGColorProfile: Equatable, Sendable {
    public var name: String
    public var href: String?
    /// Raw ICC profile bytes (`acsp`); `nil` when the href was rejected or unloadable.
    public var iccData: Data?

    public init(name: String, href: String? = nil, iccData: Data? = nil) {
        self.name = name
        self.href = href
        self.iccData = iccData
    }
}
