import Foundation
import Testing
import SVGCore
import SVGParser

@Suite("SVGParsingLimits")
struct SVGParsingLimitsTests {

    private func limitWarning(_ result: SVGParseResult, kind: String) -> Bool {
        result.report.warnings.contains {
            if case .limitExceeded(let exceededKind, _) = $0.kind {
                return exceededKind == kind
            }
            return false
        }
    }

    @Test func oversizedDocumentBytesWarnsWithoutParsing() throws {
        let limits = SVGParsingLimits(maxDocumentBytes: 64)
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
          <rect width="100" height="100" fill="red"/>
        </svg>
        """
        let result = try SVGParser(options: SVGParserOptions(limits: limits))
            .parseWithReport(data: Data(svg.utf8))

        #expect(limitWarning(result, kind: "maxDocumentBytes"))
        #expect(result.document.root.children.isEmpty)
    }

    @Test func oversizedPathDataTruncatesWithWarning() throws {
        let limits = SVGParsingLimits(maxPathCommands: 3)
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
          <path d="M0 0 L1 1 L2 2 L3 3 L4 4" fill="red"/>
        </svg>
        """
        let result = try SVGParser(options: SVGParserOptions(limits: limits))
            .parseWithReport(string: svg)

        #expect(limitWarning(result, kind: "maxPathCommands"))
        guard case .path(let path) = result.document.root.children.first else {
            Issue.record("expected path element")
            return
        }
        #expect(path.commands.count == 3)
    }

    @Test func malformedXMLStillThrowsDespiteLimits() {
        let limits = SVGParsingLimits(maxDocumentBytes: 64)
        #expect(throws: SVGParseError.self) {
            _ = try SVGParser(options: SVGParserOptions(limits: limits))
                .parse(string: "<svg><rect")
        }
    }

    @Test func testingStrictThrowsOnLimitExceeded() {
        var options = SVGParserOptions.testingStrict
        options.limits = SVGParsingLimits(maxDocumentBytes: 32)
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"/>"
        #expect(throws: SVGParseError.self) {
            _ = try SVGParser(options: options).parseWithReport(data: Data(svg.utf8))
        }
    }
}
