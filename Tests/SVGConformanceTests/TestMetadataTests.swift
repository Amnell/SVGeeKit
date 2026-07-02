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

    @Test func capturesListItemsInPassCriteria() throws {
        let url = try Paths.suiteRoot()
            .appendingPathComponent("svg/animate-elem-25-t.svg")
        let m = SVGTestMetadata.extract(from: url)

        // The `<p>` intro plus each `<li>` bullet should be captured; the
        // `<ul>` list items used to be dropped entirely.
        #expect(m.passCriteriaParagraphs.count == 3)
        #expect(m.passCriteriaParagraphs.first == "The test is passed if:")
        #expect(m.passCriteriaParagraphs.dropFirst().allSatisfy { $0.hasPrefix("• ") })
        #expect(m.passCriteriaParagraphs.contains {
            $0.hasPrefix("• the left yellow rectangle animates its height from 100 to 50")
        })
        #expect(m.passCriteriaParagraphs.contains {
            $0.hasPrefix("• the right yellow rectangle animates its height from 100 to 50")
        })
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

    @Test func animateElemTestsAreNotSkipped() throws {
        let index = try SVGTestSuiteIndex(rootDirectory: Paths.suiteRoot())
        let elemCases = index.cases.filter { $0.id.hasPrefix("animate-elem-") }
        #expect(elemCases.count == 68)
        #expect(elemCases.allSatisfy { !$0.isSkipped })
    }

    @Test func excludedAnimateFamiliesStaySkipped() throws {
        let index = try SVGTestSuiteIndex(rootDirectory: Paths.suiteRoot())
        let excluded = [
            "animate-dom-01-f",
            "animate-dom-02-f",
            "animate-script-elem-01-b",
            "animate-struct-dom-01-b",
            "animate-interact-events-01-t",
            "animate-interact-pevents-01-t",
            "animate-interact-pevents-02-t",
            "animate-interact-pevents-03-t",
            "animate-interact-pevents-04-t",
            "animate-pservers-grad-01-b"
        ]
        for id in excluded {
            let testCase = try #require(index.cases.first { $0.id == id })
            #expect(testCase.isSkipped, "expected \(id) to stay skipped")
        }
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
