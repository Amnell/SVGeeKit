import Foundation

public struct SVGParseError: Error, CustomStringConvertible, Sendable {
    public enum Kind: Sendable, Equatable {
        case xml(String)
        case missingRoot
        case malformedAttribute(name: String, value: String, reason: String)
        case policyViolation(String)
    }

    public let kind: Kind
    public let line: Int?
    public let column: Int?

    public var description: String {
        let location = line.map { ":\($0):\(column ?? 0)" } ?? ""
        switch kind {
        case .xml(let message):
            return "SVG parse error\(location): \(message)"
        case .missingRoot:
            return "SVG parse error\(location): no <svg> root element found"
        case .malformedAttribute(let name, let value, let reason):
            return "SVG parse error\(location): malformed attribute \(name)=\"\(value)\" — \(reason)"
        case .policyViolation(let message):
            return "SVG parse error\(location): \(message)"
        }
    }
}
