import Testing
import Foundation
@testable import SVGConformance

@Suite("SVGTestMetadata extraction")
@MainActor
struct TestMetadataSuite {

    @Test func extractsW3CSectionsFromShapesRect01() throws {
        let url = try Paths.suiteRoot()
            .appendingPathComponent("svg/shapes-rect-01-t.svg")
        let m = SVGTestMetadata.extract(from: url)

        #expect(m.reviewer == "SVGWG")
        #expect(m.author == "Kelvin R")
        #expect(m.status == "accepted")
        // RCS keyword wrappers like `$RCSfile: ... $` should be unwrapped.
        #expect(m.title == "shapes-rect-01-t.svg,v")

        #expect(m.testDescriptionParagraphs == [
            "This is a simple test of the rect element."
        ])
        #expect(m.operatorScriptParagraphs == [
            "Run the test. No interaction required."
        ])
        #expect(m.passCriteriaParagraphs == [
            "The test passes if all four sets of two rectangles are drawn and they match the reference image."
        ])
    }

    @Test func returnsTitleAndDescForInHouseFixture() throws {
        let url = try Paths.suiteRoot()
            .appendingPathComponent("svg/shapes-rect-basic-01.svg")
        let m = SVGTestMetadata.extract(from: url)

        #expect(m.title == "shapes-rect-basic-01")
        #expect(m.description?.contains("Six rectangles") == true)
        #expect(m.testDescriptionParagraphs.isEmpty)
        #expect(m.passCriteriaParagraphs.isEmpty)
        #expect(m.operatorScriptParagraphs.isEmpty)
        #expect(m.author == nil)
    }

    @Test func emptyForMinimalDocument() {
        let svg = """
        <?xml version="1.0"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>
        """
        let m = SVGTestMetadata.extract(from: Data(svg.utf8))
        #expect(m.isEmpty)
    }
}
