import Foundation

/// Why an `href` was not resolved under the active `SVGResourcePolicy`.
public enum SVGHrefRejectionReason: String, Sendable, Equatable {
    case emptyReference
    case networkScheme
    case externalReference
    case pathTraversal
    case restrictedPolicy
}

/// A non-fatal parse issue recorded while `failurePolicy` is `.warnAndContinue`.
public struct SVGParseWarning: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case rejectedExternalReference(href: String, reason: SVGHrefRejectionReason, line: Int?)
        case limitExceeded(kind: String, line: Int?)
        case unsupportedElement(name: String, line: Int?)
        case malformedAttribute(name: String, line: Int?)
        case missingDefinition(id: String)
    }

    public var kind: Kind
    public var message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }
}

/// Warnings collected during a successful parse.
public struct SVGParseReport: Sendable, Equatable {
    public var warnings: [SVGParseWarning]

    public init(warnings: [SVGParseWarning] = []) {
        self.warnings = warnings
    }
}

/// Document plus soft-failure report from `SVGParser.parse(…)`.
public struct SVGParseResult: Sendable, Equatable {
    public var document: SVGDocument
    public var report: SVGParseReport

    public init(document: SVGDocument, report: SVGParseReport) {
        self.document = document
        self.report = report
    }
}
