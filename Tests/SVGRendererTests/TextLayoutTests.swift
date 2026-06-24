import CoreGraphics
import Foundation
import SVGCore
import SVGParser
import Testing
@testable import SVGRenderer

@Suite("Text layout")
struct TextLayoutTests {

    @Test func textTspan02Line1SplitMatchesMergedLayout() throws {
        let doc = try loadTextTspan02()
        let green = try greenText(in: doc)
        let line1Runs = Array(green.runs.prefix { $0.explicitY == nil })

        var split = green
        split.runs = line1Runs

        let mergedString = line1Runs.map(\.string).joined()
        let mergedRotations = line1Runs.flatMap { $0.rotations ?? [] }
        let merged = SVGText(
            origin: green.origin,
            runs: [
                SVGTextRun(
                    string: mergedString,
                    font: green.font,
                    paint: green.paint,
                    rotations: mergedRotations
                )
            ],
            font: green.font,
            paint: green.paint
        )

        let splitPlacements = TextLayout.layoutCharacterPlacements(
            text: split,
            fontFaces: doc.fontFaces,
            fonts: doc.fonts
        )
        let mergedPlacements = TextLayout.layoutCharacterPlacements(
            text: merged,
            fontFaces: doc.fontFaces,
            fonts: doc.fonts
        )

        #expect(splitPlacements.count == mergedPlacements.count)
        #expect(splitPlacements.count == mergedString.count)

        for i in splitPlacements.indices {
            let lhs = splitPlacements[i]
            let rhs = mergedPlacements[i]
            #expect(lhs.character == rhs.character)
            #expect(lhs.rotation == rhs.rotation)
            #expect(abs(lhs.position.x - rhs.position.x) < 0.001)
            #expect(abs(lhs.position.y - rhs.position.y) < 0.001)
        }
    }

    /// Pins pen positions at word boundaries on line 1. Update only when layout
    /// math intentionally changes; use split-vs-merged test to catch run bugs first.
    @Test func textTspan02Line1AnchorPenPositions() throws {
        let doc = try loadTextTspan02()
        let green = try greenText(in: doc)
        let line1Runs = Array(green.runs.prefix { $0.explicitY == nil })

        var line1 = green
        line1.runs = line1Runs

        let placements = TextLayout.layoutCharacterPlacements(
            text: line1,
            fontFaces: doc.fontFaces,
            fonts: doc.fonts
        )
        let stream = line1Runs.map(\.string).joined()

        func placement(of character: Character, occurrence: Int = 1) -> TextLayout.CharacterPlacement? {
            var seen = 0
            for p in placements {
                if p.character == character {
                    seen += 1
                    if seen == occurrence { return p }
                }
            }
            return nil
        }

        guard let s = placement(of: "s", occurrence: 1),
              let n = placement(of: "n", occurrence: 1),
              let e = placement(of: "e", occurrence: 2) else {
            Issue.record("missing anchor characters in '\(stream)'")
            return
        }

        // Golden pen anchors on line 1 (SVGFreeSansASCII, font-size 35).
        #expect(abs(s.position.x - 233.158) < 0.05)
        #expect(abs(s.position.y - 26.986) < 0.05)
        #expect(abs(n.position.x - 256.675) < 0.05)
        #expect(abs(n.position.y - 16.785) < 0.05)
        #expect(abs(e.position.x - 296.966) < 0.05)
        #expect(abs(e.position.y - 57.075) < 0.05)
    }

    @Test func textTspan02GreenLine1MatchesRedReferenceRotations() throws {
        let doc = try loadTextTspan02()
        let green = try greenText(in: doc)
        let red = try redText(in: doc)

        let greenLine1 = Array(green.runs.prefix { $0.explicitY == nil })
        let redLine1 = Array(red.runs.prefix { $0.explicitY == nil })

        let greenStream = greenLine1.map(\.string).joined()
        let redStream = redLine1.map(\.string).joined()
        let greenRots = greenLine1.flatMap { $0.rotations ?? [] }
        let redRots = redLine1.flatMap { $0.rotations ?? [] }

        #expect(redStream == "Not all characters in the")
        #expect(greenStream == "Not all characters in the")

        let shared = min(greenRots.count, redRots.count)
        for i in 0..<shared {
            #expect(greenRots[i] == redRots[i])
        }
        #expect(greenRots.count == redRots.count)
    }

    @Test func svgFontCharAdvanceMatchesSingleGlyphWidth() throws {
        let doc = try loadTextTspan02()
        let green = try greenText(in: doc)
        let font = green.font

        for scalar in ["N", "o", "t", " ", "a", "s", "i", "n", "e"].map(Character.init) {
            let s = String(scalar)
            let width = TextLayout.typographicWidth(
                string: s,
                font: font,
                fontFaces: doc.fontFaces,
                fonts: doc.fonts
            )
            let placements = TextLayout.layoutCharacterPlacements(
                text: SVGText(
                    origin: .zero,
                    runs: [SVGTextRun(string: s, font: font, paint: green.paint)]
                ),
                fontFaces: doc.fontFaces,
                fonts: doc.fonts
            )
            guard placements.count == 1 else { continue }
            let line1 = TextLayout.layoutCharacterPlacements(
                text: SVGText(
                    origin: .zero,
                    runs: [
                        SVGTextRun(string: s, font: font, paint: green.paint),
                        SVGTextRun(string: "X", font: font, paint: green.paint)
                    ]
                ),
                fontFaces: doc.fontFaces,
                fonts: doc.fonts
            )
            #expect(line1.count == 2)
            #expect(abs(line1[1].position.x - width) < 0.001)
        }
    }

    // MARK: - Fixtures

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func loadTextTspan02() throws -> SVGDocument {
        let svgURL = repoRoot()
            .appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/text-tspan-02-b.svg")
        return try SVGParser().parse(url: svgURL)
    }

    private func greenText(in doc: SVGDocument) throws -> SVGText {
        guard case .group(let body) = doc.root.children.first(where: {
            if case .group = $0 { return true }
            return false
        }) else {
            Issue.record("expected body group")
            throw FixtureError.missingBody
        }

        guard let green = body.children.compactMap({ el -> SVGText? in
            guard case .text(let t) = el else { return nil }
            guard t.font.size == 35, t.origin.x == 20, t.origin.y == 120 else { return nil }
            if case .color(let c) = t.paint.fill, c.green > 0.4, c.red < 0.1 { return t }
            return nil
        }).first else {
            Issue.record("expected green text")
            throw FixtureError.missingGreenText
        }
        return green
    }

    private func redText(in doc: SVGDocument) throws -> SVGText {
        guard case .group(let body) = doc.root.children.first(where: {
            if case .group = $0 { return true }
            return false
        }) else {
            Issue.record("expected body group")
            throw FixtureError.missingBody
        }

        guard let red = body.children.compactMap({ el -> SVGText? in
            guard case .text(let t) = el else { return nil }
            guard t.font.size == 35, t.origin.x == 20, t.origin.y == 120 else { return nil }
            if case .color(let c) = t.paint.fill, c.red > 0.4, c.green < 0.1 { return t }
            return nil
        }).first else {
            Issue.record("expected red text")
            throw FixtureError.missingRedText
        }
        return red
    }

    private enum FixtureError: Error {
        case missingBody
        case missingGreenText
        case missingRedText
    }
}
