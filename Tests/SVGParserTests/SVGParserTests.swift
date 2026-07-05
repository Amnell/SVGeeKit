import Testing
import CoreGraphics
import Foundation
@testable import SVGParser
import SVGCore

@Suite("SVGParser — shapes")
struct SVGParserTests {

    @Test func parsesRootViewBoxAndIntrinsicSize() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="50" viewBox="0 0 200 100"/>
        """
        let doc = try SVGParser().parse(string: svg)
        #expect(doc.intrinsicSize == CGSize(width: 100, height: 50))
        #expect(doc.viewBox == CGRect(x: 0, y: 0, width: 200, height: 100))
    }

    @Test func parsesRectWithFillAndStroke() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
          <rect x="1" y="2" width="3" height="4" fill="red" stroke="black" stroke-width="2"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .rect(let r) = doc.root.children.first else {
            Issue.record("expected rect"); return
        }
        #expect(r.origin == CGPoint(x: 1, y: 2))
        #expect(r.size == CGSize(width: 3, height: 4))
        if case .color(let c) = r.paint.fill {
            #expect(c.red == 1 && c.green == 0 && c.blue == 0)
        } else {
            Issue.record("expected fill color")
        }
        #expect(r.paint.strokeWidth == 2)
    }

    @Test func parsesGroupTransformAndNestedRect() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
          <g transform="translate(5 5) scale(2)">
            <rect x="0" y="0" width="1" height="1" fill="#0000ff"/>
          </g>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .group(let g) = doc.root.children.first else {
            Issue.record("expected group"); return
        }
        let p = CGPoint(x: 0, y: 0).applying(g.transform.matrix)
        #expect(p == CGPoint(x: 5, y: 5))
        guard case .rect(let r) = g.children.first else {
            Issue.record("expected nested rect"); return
        }
        if case .color(let c) = r.paint.fill {
            #expect(c.blue == 1)
        } else {
            Issue.record("expected color fill")
        }
    }

    @Test func parsesCircle() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
          <circle cx="5" cy="5" r="3" fill="red"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .circle(let c) = doc.root.children.first else {
            Issue.record("expected circle"); return
        }
        #expect(c.center == CGPoint(x: 5, y: 5))
        #expect(c.radius == 3)
    }

    @Test func parsesEllipse() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="10">
          <ellipse cx="10" cy="5" rx="8" ry="4"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .ellipse(let e) = doc.root.children.first else {
            Issue.record("expected ellipse"); return
        }
        #expect(e.center == CGPoint(x: 10, y: 5))
        #expect(e.radii == CGSize(width: 8, height: 4))
    }

    @Test func parsesLine() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
          <line x1="0" y1="0" x2="10" y2="5" stroke="black"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .line(let l) = doc.root.children.first else {
            Issue.record("expected line"); return
        }
        #expect(l.start == CGPoint(x: 0, y: 0))
        #expect(l.end == CGPoint(x: 10, y: 5))
    }

    @Test func parsesPolylineWithMixedSeparators() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
          <polyline points="0,0 5 5, 10,0" fill="none" stroke="black"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .polyline(let p) = doc.root.children.first else {
            Issue.record("expected polyline"); return
        }
        #expect(p.points == [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 5, y: 5),
            CGPoint(x: 10, y: 0)
        ])
    }

    @Test func parsesPolygon() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
          <polygon points="0 0 10 0 5 10" fill="green"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .polygon(let p) = doc.root.children.first else {
            Issue.record("expected polygon"); return
        }
        #expect(p.points.count == 3)
        #expect(p.points.last == CGPoint(x: 5, y: 10))
    }

    @Test func parsesTextWithCascadedFont() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="200" height="100">
          <g font-family="Helvetica, sans-serif" font-size="20">
            <text x="10" y="40" text-anchor="middle" fill="red">Hi</text>
          </g>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .group(let g) = doc.root.children.first,
              case .text(let t) = g.children.first else {
            Issue.record("expected <g><text>"); return
        }
        #expect(t.origin == CGPoint(x: 10, y: 40))
        #expect(t.string == "Hi")
        #expect(t.font.family == "Helvetica, sans-serif")
        #expect(t.font.size == 20)
        #expect(t.font.anchor == .middle)
        if case .color(let c) = t.paint.fill {
            #expect(c.red == 1 && c.green == 0 && c.blue == 0)
        } else {
            Issue.record("expected red fill")
        }
    }

    @Test func collapsesWhitespaceAndFlattensTspan() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
          <text x="0" y="20">
            Hello  <tspan>brave</tspan>  world
          </text>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .text(let t) = doc.root.children.first else {
            Issue.record("expected text"); return
        }
        #expect(t.string == "Hello brave world")
    }

    @Test func parsesTspanWithDistinctStyleRuns() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
          <text x="0" y="20" fill="blue">You are<tspan font-weight="bold" fill="green"> not </tspan>a banana.</text>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .text(let t) = doc.root.children.first else {
            Issue.record("expected text"); return
        }
        #expect(t.runs.count == 3)
        #expect(t.runs[0].string == "You are")
        #expect(t.runs[1].string == " not ")
        if case .color(let c) = t.runs[1].paint.fill {
            #expect(c.green == CGFloat(128) / 255)
            #expect(c.blue == 0)
        } else {
            Issue.record("expected green tspan fill")
        }
        #expect(t.runs[1].font.weight == .bold)
    }

    @Test func stripsIgnorableWhitespaceFromIndentedTextRuns() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
          <text x="0" y="20" fill="blue">
            You are<tspan font-weight="bold" fill="green"> not </tspan>a banana.
          </text>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .text(let t) = doc.root.children.first else {
            Issue.record("expected text"); return
        }
        #expect(t.runs.count == 3)
        #expect(t.runs[0].string == "You are")
        #expect(t.runs[1].string == " not ")
        #expect(t.runs[2].string == "a banana.")
        #expect(!t.runs[0].string.contains("\n"))
    }

    @Test func parsesTspanExplicitXYWithoutLeadingWhitespaceRun() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="480" height="360">
          <text fill="orange">
            <tspan x="35 53.75 72.5" y="200">Cute</tspan>
            <tspan x="63.13 81.88" y="230.5">fu</tspan>
          </text>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .text(let t) = doc.root.children.first else {
            Issue.record("expected text"); return
        }
        #expect(t.runs.count == 2)
        #expect(t.runs[0].string == "Cute")
        #expect(t.runs[0].explicitX == [35, 53.75, 72.5])
        #expect(t.runs[1].string == "fu")
        #expect(t.runs[1].explicitX == [63.13, 81.88])
    }

    @Test func normalizesTextCharacterStreamForTspan02GreenText() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let svgURL = repoRoot
            .appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/text-tspan-02-b.svg")
        let doc = try SVGParser().parse(url: svgURL)

        guard case .group(let body) = doc.root.children.first(where: {
            if case .group = $0 { return true }
            return false
        }) else {
            Issue.record("expected body group"); return
        }

        let green = body.children.compactMap { el -> SVGText? in
            guard case .text(let t) = el else { return nil }
            guard t.font.size == 35, t.origin.x == 20, t.origin.y == 120 else { return nil }
            if case .color(let c) = t.paint.fill, c.green > 0.4, c.red < 0.1 { return t }
            return nil
        }.first
        guard let green else {
            Issue.record("expected green text"); return
        }

        #expect(green.string == "Not all characters in the text have a specified rotation")
        #expect(green.runs.first?.string == "Not")
        #expect(green.runs.first?.rotations == [5, 15, 25])

        let child4 = green.runs.first { $0.explicitX == [20] && $0.explicitY == 180 }
        #expect(child4?.string == "text")

        let inRun = green.runs.first { $0.string == "in" }
        #expect(inRun?.rotations == [70, 60])

        let theRun = green.runs.first { $0.string == " the" }
        #expect(theRun?.rotations == [50, 40, 30, 20])

        let spaceBeforeIn = green.runs.first { $0.string == " " && $0.rotations == [-40] }
        #expect(spaceBeforeIn != nil)

        #expect(green.runs.last?.string == "rotation")
        #expect(green.runs.last?.rotations?.allSatisfy { $0 == 55 } == true)

        let specified = green.runs.first { $0.string.contains("specified") }
        guard let specified else {
            Issue.record("missing specified run"); return
        }
        #expect(specified.rotations?.allSatisfy { $0 == -10 } == true)
        #expect(specified.rotations?.count == (specified.string == "specified" ? 9 : 10))
    }

    @Test func parsesRotationValuesAnnotationText() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let svgURL = repoRoot
            .appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/text-tspan-02-b.svg")
        let doc = try SVGParser().parse(url: svgURL)

        guard case .group(let body) = doc.root.children.first(where: {
            if case .group = $0 { return true }
            return false
        }) else {
            Issue.record("expected body group"); return
        }

        let annotations = body.children.compactMap { el -> SVGText? in
            guard case .text(let t) = el else { return nil }
            return t.font.size == 8 ? t : nil
        }
        #expect(annotations.count == 1)
        let text = annotations[0]
        #expect(text.runs.allSatisfy { $0.preserveSpace })
        #expect(text.runs[0].explicitX == [30])
        #expect(text.runs[0].explicitY == 135)
        #expect(text.runs[0].string.contains("5"))
        #expect(text.runs[3].explicitX == [295])
        #expect(text.runs[4].explicitX == [340])
    }

    @Test func preservesSpaceBeforeExplicitPositionedTspan() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="480" height="360">
          <text x="20" y="120" rotate="5,15,25,35,45">Not all characters in the
          <tspan x="20" y="180">text</tspan></text>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .text(let t) = doc.root.children.first else {
            Issue.record("expected text"); return
        }
        #expect(t.string == "Not all characters in the text")
        #expect(t.runs.count == 2)
        #expect(t.runs[0].string == "Not all characters in the ")
        #expect(t.runs[1].string == "text")
    }

    @Test func preservesXmlSpaceOnTextRun() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
          <text x="0" y="20" xml:space="preserve">  spaced  </text>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .text(let t) = doc.root.children.first else {
            Issue.record("expected text"); return
        }
        #expect(t.runs.count == 1)
        #expect(t.runs[0].preserveSpace)
        #expect(t.runs[0].string == "  spaced  ")
    }

    @Test func parsesTspanRotatePropagation() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="480" height="360"><text x="20" y="120" rotate="5,15,25">No<tspan rotate="-10,-20">te</tspan></text></svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .text(let t) = doc.root.children.first else {
            Issue.record("expected text"); return
        }
        #expect(t.runs.count == 2)
        #expect(t.runs[0].string == "No")
        #expect(t.runs[0].rotations == [5, 15])
        #expect(t.runs[1].string == "te")
        #expect(t.runs[1].rotations == [-10, -20])
    }

    @Test func parsesTspanExplicitXYLists() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="200" height="200">
          <text fill="orange"><tspan x="10 30 50" y="40">ABC</tspan></text>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .text(let t) = doc.root.children.first else {
            Issue.record("expected text"); return
        }
        #expect(t.runs.count == 1)
        #expect(t.runs[0].string == "ABC")
        #expect(t.runs[0].explicitX == [10, 30, 50])
        #expect(t.runs[0].explicitY == 40)
    }

    @Test func textIgnoresTitleAndDescContent() throws {
        // Ensures the text-capture machinery doesn't accidentally suck in
        // non-text content like <title>'s string.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
          <title>doc title</title>
          <desc>doc desc</desc>
          <text x="0" y="10">visible</text>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .text(let t) = doc.root.children.last else {
            Issue.record("expected text"); return
        }
        #expect(t.string == "visible")
    }

    @Test func parsesPathAbsoluteAndRelativeCommands() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
          <path d="M 10 20 L 30 40 H 50 V 60 Z" fill="red"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .path(let p) = doc.root.children.first else {
            Issue.record("expected path"); return
        }
        #expect(p.commands == [
            .moveTo(CGPoint(x: 10, y: 20)),
            .lineTo(CGPoint(x: 30, y: 40)),
            .lineTo(CGPoint(x: 50, y: 40)),
            .lineTo(CGPoint(x: 50, y: 60)),
            .close
        ])
        if case .color(let c) = p.paint.fill {
            #expect(c.red == 1 && c.green == 0 && c.blue == 0)
        } else { Issue.record("expected red fill") }
    }

    @Test func parsesPathRelativeAndImplicitLineto() throws {
        // "m 10 10 20 20" -> moveTo(10,10) then implicit lineTo (10+20, 10+20)
        let commands = PathDataParser.parse("m 10 10 20 20")
        #expect(commands == [
            .moveTo(CGPoint(x: 10, y: 10)),
            .lineTo(CGPoint(x: 30, y: 30))
        ])
    }

    @Test func parsesPathCubicAndSmoothReflection() throws {
        // C produces cubic with absC2 = (40,40); S should reflect that around the
        // current point (50,50) → absC1 = (60,60).
        let cmds = PathDataParser.parse("M 0 0 C 10 10 40 40 50 50 S 70 30 80 20")
        #expect(cmds?.count == 3)
        guard let cmds, case .cubicTo(let c1, _, let end) = cmds[2] else {
            Issue.record("expected cubic from S"); return
        }
        #expect(c1 == CGPoint(x: 60, y: 60))
        #expect(end == CGPoint(x: 80, y: 20))
    }

    @Test func parsesPathArcDecomposesToCubics() throws {
        // A 50 50 0 0 1 100 0 from (0,0): half-circle right.
        // Expect several cubic segments, ending at (100, 0).
        let cmds = PathDataParser.parse("M 0 0 A 50 50 0 0 1 100 0")
        guard let cmds else { Issue.record("expected commands"); return }
        #expect(cmds.first == .moveTo(.zero))
        if case .cubicTo(_, _, let end) = cmds.last {
            #expect(abs(end.x - 100) < 0.01 && abs(end.y) < 0.01)
        } else { Issue.record("arc should decompose to cubics") }
    }

    @Test func parsesFillRuleEvenOdd() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
          <path d="M 0 0 L 10 0 L 10 10 Z" fill="red" fill-rule="evenodd"/>
          <path d="M 0 0 L 10 0 L 10 10 Z" fill="red"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .path(let evenOdd) = doc.root.children[0],
              case .path(let nonzero) = doc.root.children[1] else {
            Issue.record("expected two paths"); return
        }
        #expect(evenOdd.paint.fillRule == .evenodd)
        #expect(nonzero.paint.fillRule == .nonzero)
    }

    @Test func resolvesPercentLengthsAgainstViewport() throws {
        // viewBox 480x360 -> 50% x = 240, 50% y = 180, 50% length-axis = ~212.13
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 480 360">
          <rect x="50%" y="50%" width="50%" height="50%"/>
          <circle cx="50%" cy="50%" r="50%"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .rect(let r) = doc.root.children[0],
              case .circle(let c) = doc.root.children[1] else {
            Issue.record("expected rect + circle"); return
        }
        #expect(abs(r.origin.x - 240) < 0.01)
        #expect(abs(r.origin.y - 180) < 0.01)
        #expect(abs(r.size.width - 240) < 0.01)
        #expect(abs(r.size.height - 180) < 0.01)
        #expect(abs(c.center.x - 240) < 0.01)
        #expect(abs(c.center.y - 180) < 0.01)
        let diag = (480.0 * 480.0 + 360.0 * 360.0).squareRoot() / 2.0.squareRoot()
        #expect(abs(c.radius - CGFloat(diag) / 2) < 0.01)
    }

    @Test func parsesStrokeDashAttributes() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
          <line x1="0" y1="0" x2="100" y2="0" stroke="black"
                stroke-dasharray="10, 5 20" stroke-dashoffset="3"/>
          <line x1="0" y1="0" x2="100" y2="0" stroke="black"
                stroke-dasharray="none"/>
          <line x1="0" y1="0" x2="100" y2="0" stroke="black"
                stroke-dasharray="10 -5"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .line(let a) = doc.root.children[0],
              case .line(let b) = doc.root.children[1],
              case .line(let c) = doc.root.children[2] else {
            Issue.record("expected three lines"); return
        }
        // Odd-length lists are duplicated per SVG 1.1.
        #expect(a.paint.strokeDashArray == [10, 5, 20, 10, 5, 20])
        #expect(a.paint.strokeDashOffset == 3)
        #expect(b.paint.strokeDashArray.isEmpty)
        // Negative values invalidate the whole list.
        #expect(c.paint.strokeDashArray.isEmpty)
    }

    @Test func parsesNamedColorPalette() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
          <rect fill="darkblue"/>
          <rect fill="LIGHTGREEN"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .rect(let a) = doc.root.children[0],
              case .rect(let b) = doc.root.children[1] else {
            Issue.record("expected two rects"); return
        }
        guard case .color(let ca) = a.paint.fill, case .color(let cb) = b.paint.fill else {
            Issue.record("expected color fills"); return
        }
        #expect(abs(ca.red - 0) < 0.01 && abs(ca.green - 0) < 0.01 && abs(ca.blue - 139.0/255) < 0.01)
        #expect(abs(cb.red - 144.0/255) < 0.01 && abs(cb.green - 238.0/255) < 0.01 && abs(cb.blue - 144.0/255) < 0.01)
    }

    @Test func resolvesCurrentColorAgainstColorCascade() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
          <g color="green">
            <rect id="a" fill="currentColor"/>
            <rect id="b" color="blue" fill="currentColor"/>
          </g>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .group(let g) = doc.root.children[0],
              case .rect(let a) = g.children[0],
              case .rect(let b) = g.children[1] else {
            Issue.record("expected group with two rects"); return
        }
        guard case .color(let ca) = a.paint.fill, case .color(let cb) = b.paint.fill else {
            Issue.record("expected resolved color fills"); return
        }
        // green = #008000
        #expect(abs(ca.red) < 0.01 && abs(ca.green - 128.0/255) < 0.01 && abs(ca.blue) < 0.01)
        // blue = #0000ff
        #expect(abs(cb.red) < 0.01 && abs(cb.green) < 0.01 && abs(cb.blue - 1) < 0.01)
    }

    @Test func cascadesVisibilityAndHonorsChildOverride() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
          <rect id="shown"/>
          <g visibility="hidden">
            <rect id="hidden"/>
            <rect id="revealed" visibility="visible"/>
          </g>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .rect(let shown) = doc.root.children[0],
              case .group(let g) = doc.root.children[1],
              case .rect(let hidden) = g.children[0],
              case .rect(let revealed) = g.children[1] else {
            Issue.record("expected shown rect and hidden group with two rects"); return
        }
        #expect(shown.paint.visibility == .visible)
        #expect(hidden.paint.visibility == .hidden)
        #expect(revealed.paint.visibility == .visible)
    }

    @Test func parsesLinearGradientWithXlinkHrefStopInheritance() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="100" height="50">
          <defs>
            <linearGradient id="A">
              <stop offset="0" stop-color="blue"/>
              <stop offset="1" stop-color="lime"/>
            </linearGradient>
            <linearGradient id="B" x1="0" y1="0" x2="1" y2="0" xlink:href="#A"/>
          </defs>
          <rect width="50" height="20" fill="url(#A)"/>
          <rect y="25" width="50" height="20" fill="url(#B)"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)

        guard case .linearGradient(let a) = doc.paintServers["A"] else {
            Issue.record("expected linearGradient A"); return
        }
        guard case .linearGradient(let b) = doc.paintServers["B"] else {
            Issue.record("expected linearGradient B (resolved via xlink:href)"); return
        }
        #expect(a.stops.count == 2)
        #expect(a.units == .objectBoundingBox)
        // B inherits stops from A since it defines none of its own.
        #expect(b.stops.count == 2)
        #expect(b.stops.map(\.offset) == a.stops.map(\.offset))

        // Rects carry parse-time `.paintServer` references; lowering resolves them.
        guard case .rect(let r1) = doc.root.children[0],
              case .rect(let r2) = doc.root.children[1] else {
            Issue.record("expected two rects"); return
        }
        #expect(r1.paint.fill == .paintServer(id: "A"))
        #expect(r2.paint.fill == .paintServer(id: "B"))
    }

    @Test func parsesGradientStopOpacity() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <linearGradient id="g">
            <stop offset="0" stop-color="red" stop-opacity="1"/>
            <stop offset="0.5" stop-color="blue" stop-opacity="0"/>
            <stop offset="1" stop-color="lime" stop-opacity="0.5"/>
          </linearGradient>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .linearGradient(let g) = doc.paintServers["g"] else {
            Issue.record("expected linearGradient"); return
        }
        #expect(g.stops.count == 3)
        #expect(g.stops[0].color.alpha == 1)
        #expect(g.stops[1].color.alpha == 0)
        #expect(g.stops[2].color.alpha == 0.5)
    }

    @Test func parsesPatternWithChildrenAndHrefMerge() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="100" height="100">
          <pattern id="p1" patternUnits="userSpaceOnUse" width="100" height="100" viewBox="0 0 10 10">
            <circle cx="5" cy="5" r="1" fill="red"/>
          </pattern>
          <pattern id="p2" xlink:href="#p1" y="30">
            <circle cx="5" cy="2" r="2" fill="lime"/>
          </pattern>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)

        guard case .pattern(let p1) = doc.paintServers["p1"] else {
            Issue.record("expected pattern p1"); return
        }
        guard case .pattern(let p2) = doc.paintServers["p2"] else {
            Issue.record("expected pattern p2"); return
        }
        #expect(p1.children.count == 1)
        #expect(p2.children.count == 1)
        #expect(p2.y == 30)
        #expect(p2.width == 100)
        #expect(p2.viewBox == CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    /// pservers-grad-03-b: pattern with xlink:href and no children inherits parent content.
    @Test func patternHrefInheritsChildrenWhenEmpty() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="480" height="360">
          <pattern id="Pat3a" x="0" y="0" width="20" height="20" patternUnits="userSpaceOnUse">
            <rect x="0" y="0" width="10" height="10" fill="#9933DD"/>
            <rect x="10" y="0" width="10" height="10" fill="green"/>
          </pattern>
          <pattern id="Pat3b" xlink:href="#Pat3a" width="20" height="20"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)

        guard case .pattern(let a) = doc.paintServers["Pat3a"] else {
            Issue.record("expected Pat3a"); return
        }
        guard case .pattern(let b) = doc.paintServers["Pat3b"] else {
            Issue.record("expected Pat3b"); return
        }
        #expect(a.children.count == 2)
        #expect(b.children.count == 2)
        #expect(b.width == 20)
        #expect(b.height == 20)
        #expect(b.patternUnits == .userSpaceOnUse)
        #expect(b.x == 0)
        #expect(b.y == 0)
    }

    @Test func invalidPatternHrefDoesNotMergeAttributes() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="100" height="100">
          <pattern id="p1" patternUnits="userSpaceOnUse" width="100" height="100" viewBox="0 0 10 10">
            <circle cx="5" cy="5" r="1" fill="red"/>
          </pattern>
          <pattern id="p2" xlink:href="#invalidlink" width="0.5" height="0.5">
            <circle cx="50" cy="50" r="20" fill="lime"/>
          </pattern>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)

        guard case .pattern(let p2) = doc.paintServers["p2"] else {
            Issue.record("expected pattern p2"); return
        }
        #expect(p2.width == 0.5)
        #expect(p2.height == 0.5)
        #expect(p2.patternUnits == .objectBoundingBox)
        #expect(p2.viewBox == nil)
        #expect(p2.children.count == 1)
        #expect(p2.hasInvalidHref)
    }

    @Test func validPatternHrefDoesNotSetInvalidHrefFlag() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="100" height="100">
          <pattern id="p1" patternUnits="userSpaceOnUse" width="100" height="100" viewBox="0 0 10 10">
            <circle cx="5" cy="5" r="1" fill="red"/>
          </pattern>
          <pattern id="p3" patternUnits="userSpaceOnUse" width="0" height="0" viewBox="0 0 10 10">
            <circle cx="5" cy="5" r="1.7" fill="red"/>
          </pattern>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .pattern(let p3) = doc.paintServers["p3"] else {
            Issue.record("expected pattern p3"); return
        }
        #expect(!p3.hasInvalidHref)
    }

    /// pservers-pattern-09-f `pattern2`: invalid `xlink:href` with default zero dims.
    @Test func invalidPatternHrefKeepsDefaultZeroDimensions() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="480" height="360">
          <pattern id="pattern2" xlink:href="#invalidlink">
            <circle cx="50" cy="50" r="20" fill="red"/>
          </pattern>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .pattern(let p2) = doc.paintServers["pattern2"] else {
            Issue.record("expected pattern2"); return
        }
        #expect(p2.width == 0)
        #expect(p2.height == 0)
        #expect(p2.hasInvalidHref)
    }

    @Test func parsesPaintServerFallbackColor() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="50" height="50">
          <rect width="50" height="50" fill="url(#missing) lime"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .rect(let r) = doc.root.children.first else {
            Issue.record("expected rect"); return
        }
        guard case .paintServer(let id, let fallback) = r.paint.fill else {
            Issue.record("expected paintServer"); return
        }
        #expect(id == "missing")
        #expect(fallback?.green == 1)
    }

    @Test func patternChildrenDoNotLeakToSceneGraph() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
          <pattern id="p" width="20" height="20">
            <rect width="10" height="10" fill="red"/>
          </pattern>
          <pattern width="20" height="20">
            <rect width="10" height="10" fill="red"/>
          </pattern>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        #expect(doc.root.children.isEmpty)
        #expect(doc.paintServers["p"] != nil)
    }

    @Test func parsesClipPathAndAppliesRef() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="200" height="200">
          <defs>
            <clipPath id="clip1">
              <rect x="10" y="10" width="80" height="80"/>
            </clipPath>
            <clipPath id="clip2">
              <rect x="0" y="0" width="50" height="50"/>
              <rect x="60" y="60" width="50" height="50"/>
            </clipPath>
          </defs>
          <rect x="0" y="0" width="100" height="100" fill="blue" clip-path="url(#clip1)"/>
          <g clip-path="url(#clip2)">
            <rect x="0" y="0" width="200" height="200" fill="red"/>
          </g>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)

        // clip paths are stored in the document
        #expect(doc.clipPaths.count == 2)

        guard let cp1 = doc.clipPaths["clip1"] else {
            Issue.record("expected clipPath clip1"); return
        }
        #expect(cp1.units == .userSpaceOnUse)
        #expect(cp1.children.count == 1)
        guard case .rect(let cpRect) = cp1.children.first else {
            Issue.record("expected rect in clip1"); return
        }
        #expect(cpRect.origin == CGPoint(x: 10, y: 10))

        guard let cp2 = doc.clipPaths["clip2"] else {
            Issue.record("expected clipPath clip2"); return
        }
        #expect(cp2.children.count == 2)

        // shape with clip-path attribute carries the ref
        guard case .rect(let blueRect) = doc.root.children.first else {
            Issue.record("expected blue rect"); return
        }
        #expect(blueRect.paint.clipPathRef == "clip1")

        // group with clip-path attribute carries the ref
        guard case .group(let g) = doc.root.children.last else {
            Issue.record("expected group"); return
        }
        #expect(g.clipPathRef == "clip2")
    }

    @Test func defsChildrenAreNotInRenderTree() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="480" height="360">
          <g>
            <defs>
              <rect x="0" y="0" width="480" height="360" fill="red"/>
            </defs>
            <rect x="140" y="80" width="200" height="200" fill="lime"/>
            <defs>
              <rect x="160" y="100" width="160" height="160" fill="red"/>
            </defs>
          </g>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .group(let g) = doc.root.children.first else {
            Issue.record("expected group"); return
        }
        #expect(g.children.count == 1)
        guard case .rect(let visible) = g.children[0] else {
            Issue.record("expected visible rect"); return
        }
        if case .color(let c) = visible.paint.fill {
            #expect(c.green == 1)
        } else {
            Issue.record("expected lime fill")
        }
    }

    @Test func defsClipPathChildrenAreStillRegistered() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
          <defs>
            <clipPath id="clip">
              <rect x="10" y="10" width="80" height="80"/>
            </clipPath>
          </defs>
          <rect x="0" y="0" width="100" height="100" fill="blue" clip-path="url(#clip)"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        #expect(doc.clipPaths["clip"]?.children.count == 1)
        #expect(doc.root.children.count == 1)
    }

    @Test func parsesInternalUseReference() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="100" height="100">
          <defs>
            <rect id="r" x="0" y="0" width="10" height="10" fill="red"/>
          </defs>
          <use xlink:href="#r" x="20" y="30" fill="lime"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)

        guard case .rect(let def) = doc.definitions["r"] else {
            Issue.record("expected rect definition"); return
        }
        #expect(def.size == CGSize(width: 10, height: 10))

        #expect(doc.root.children.count == 1)
        guard case .use(let u) = doc.root.children[0] else {
            Issue.record("expected use in scene graph"); return
        }
        #expect(u.href == "r")
        #expect(u.origin == CGPoint(x: 20, y: 30))
        #expect(u.explicitPresentation.contains("fill"))
        if case .color(let c) = u.paint.fill {
            #expect(c.green == 1)
        } else {
            Issue.record("expected lime fill override on use")
        }
    }

    @Test func useInClipPathIsRegistered() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="100" height="100">
          <defs>
            <rect id="shape" x="0" y="0" width="50" height="50"/>
            <clipPath id="clip">
              <use xlink:href="#shape" x="10" y="10"/>
            </clipPath>
          </defs>
          <rect x="0" y="0" width="100" height="100" fill="blue" clip-path="url(#clip)"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard let clip = doc.clipPaths["clip"] else {
            Issue.record("expected clipPath"); return
        }
        #expect(clip.children.count == 1)
        guard case .use(let u) = clip.children[0] else {
            Issue.record("expected use in clipPath"); return
        }
        #expect(u.href == "shape")
        #expect(u.origin == CGPoint(x: 10, y: 10))
    }

    @Test func symbolInDefsRegistersChildrenAndNestedUse() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="100" height="100">
          <defs>
            <symbol id="inner" overflow="visible">
              <rect x="-10" y="-10" width="20" height="20" fill="none" stroke="red"/>
            </symbol>
            <symbol id="outer" overflow="visible">
              <use xlink:href="#inner"/>
              <rect x="-20" y="-20" width="40" height="40" fill="none" stroke="blue"/>
            </symbol>
          </defs>
          <use x="50" y="50" xlink:href="#outer"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)

        guard case .group(let inner) = doc.definitions["inner"] else {
            Issue.record("expected inner symbol as group"); return
        }
        #expect(inner.children.count == 1)

        guard case .group(let outer) = doc.definitions["outer"] else {
            Issue.record("expected outer symbol as group"); return
        }
        #expect(outer.children.count == 2)
        guard case .use(let u) = outer.children[0] else {
            Issue.record("expected use in outer symbol"); return
        }
        #expect(u.href == "inner")

        #expect(doc.root.children.count == 1)
        guard case .use(let sceneUse) = doc.root.children[0] else {
            Issue.record("expected scene use"); return
        }
        #expect(sceneUse.href == "outer")
        #expect(sceneUse.origin == CGPoint(x: 50, y: 50))
    }

    @Test func parsesMaskRegionAndAppliesRef() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="480" height="360">
          <mask id="mask1" maskUnits="userSpaceOnUse" x="60" y="50" width="100" height="60">
            <rect x="60" y="50" width="100" height="60" fill="white"/>
          </mask>
          <rect x="60" y="50" width="100" height="60" fill="lime" mask="url(#mask1)"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)

        guard let mask = doc.masks["mask1"] else {
            Issue.record("expected mask mask1"); return
        }
        #expect(mask.maskUnits == .userSpaceOnUse)
        #expect(mask.x == 60)
        #expect(mask.y == 50)
        #expect(mask.width == 100)
        #expect(mask.height == 60)
        #expect(mask.children.count == 1)

        guard case .rect(let masked) = doc.root.children.first else {
            Issue.record("expected masked rect"); return
        }
        #expect(masked.paint.maskRef == "mask1")
    }

    @Test func parsesGroupOpacity() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="200" height="200">
          <g opacity="0.5">
            <rect x="0" y="0" width="100" height="100" fill="blue"/>
          </g>
          <g>
            <rect x="0" y="0" width="100" height="100" fill="lime"/>
          </g>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .group(let g1) = doc.root.children.first else {
            Issue.record("expected first group"); return
        }
        #expect(g1.opacity == 0.5)
        guard case .group(let g2) = doc.root.children.last else {
            Issue.record("expected second group"); return
        }
        #expect(g2.opacity == 1.0)
    }

    @Test func parsesRadialGradientWithXlinkHrefStopInheritance() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
             width="480" height="360" viewBox="0 0 480 360">
          <radialGradient id="Grad2a" gradientUnits="objectBoundingBox"
                          cx=".5" cy=".5" fx=".5" fy=".5" r=".5">
            <stop stop-color="black" offset="0"/>
            <stop stop-color="orange" offset="1"/>
          </radialGradient>
          <radialGradient id="Grad2b" xlink:href="#Grad2a"
                          gradientUnits="userSpaceOnUse" cx="240" cy="190" fx="240" fy="190" r="40"/>
          <rect x="20" y="20" width="440" height="80" fill="url(#Grad2a)"/>
          <rect x="20" y="150" width="440" height="80" fill="url(#Grad2b)"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)

        guard case .radialGradient(let a) = doc.paintServers["Grad2a"] else {
            Issue.record("expected Grad2a radialGradient"); return
        }
        #expect(a.units == .objectBoundingBox)
        #expect(a.cx == 0.5)
        #expect(a.cy == 0.5)
        #expect(a.r == 0.5)
        #expect(a.stops.count == 2)

        guard case .radialGradient(let b) = doc.paintServers["Grad2b"] else {
            Issue.record("expected Grad2b radialGradient"); return
        }
        #expect(b.units == .userSpaceOnUse)
        #expect(b.cx == 240)
        #expect(b.cy == 190)
        #expect(b.r == 40)
        // Stops inherited from Grad2a via xlink:href
        #expect(b.stops.count == 2)
    }

    @Test func parsesObjectBoundingBoxPaintServerPercentagesAsFractions() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="480" height="360" viewBox="0 0 480 360">
          <linearGradient id="lg" gradientUnits="objectBoundingBox" x1="0%" y1="0%" x2="100%" y2="0%"/>
          <radialGradient id="rg" gradientUnits="objectBoundingBox" cx="25%" cy="25%" r="25%"/>
          <pattern id="p" patternUnits="objectBoundingBox" x="25%" y="25%" width="50%" height="50%"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)

        guard case .linearGradient(let lg) = doc.paintServers["lg"] else {
            Issue.record("expected linearGradient"); return
        }
        #expect(lg.x1 == 0)
        #expect(lg.y1 == 0)
        #expect(lg.x2 == 1)
        #expect(lg.y2 == 0)

        guard case .radialGradient(let rg) = doc.paintServers["rg"] else {
            Issue.record("expected radialGradient"); return
        }
        #expect(rg.cx == 0.25)
        #expect(rg.cy == 0.25)
        #expect(rg.r == 0.25)

        guard case .pattern(let p) = doc.paintServers["p"] else {
            Issue.record("expected pattern"); return
        }
        #expect(p.x == 0.25)
        #expect(p.y == 0.25)
        #expect(p.width == 0.5)
        #expect(p.height == 0.5)
    }

    @Test func parseStoresBaseURL() throws {
        let base = URL(fileURLWithPath: "/tmp/svgeekit/tests/svg", isDirectory: true)
        let doc = try SVGParser().parse(
            string: "<svg xmlns=\"http://www.w3.org/2000/svg\"/>",
            baseURL: base
        )
        #expect(doc.baseURL == base)
    }

    @Test func resolveURLHandlesRelativeHrefs() throws {
        let base = URL(fileURLWithPath: "/tmp/svgeekit/tests/svg", isDirectory: true)
        let doc = try SVGParser().parse(
            string: "<svg xmlns=\"http://www.w3.org/2000/svg\"/>",
            baseURL: base
        )
        let resolved = doc.resolveURL("../resources/SVGFreeSans.svg#ascii")
        #expect(resolved?.lastPathComponent == "SVGFreeSans.svg")
        #expect(resolved?.fragment == "ascii")
        #expect(resolved?.path.contains("resources") == true)
    }

    @Test func parseURLSetsBaseURLToParentDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("sample.svg")
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"/>"
        try svg.write(to: file, atomically: true, encoding: .utf8)

        let doc = try SVGParser().parse(url: file)
        #expect(doc.baseURL == directory)
    }

    @Test func parsesTextClipPathAttribute() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
          <defs>
            <clipPath id="c"><rect width="50" height="50"/></clipPath>
          </defs>
          <text x="0" y="20" clip-path="url(#c)">Hi</text>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .text(let t) = doc.root.children.first else {
            Issue.record("expected text"); return
        }
        #expect(t.paint.clipPathRef == "c")
    }

    @Test func parsesInlineSVGFontGlyphs() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fontURL = repoRoot
            .appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/resources/SVGFreeSans.svg")

        let doc = try SVGParser().parse(url: fontURL)
        guard let ascii = doc.fonts["ascii"] else {
            Issue.record("expected font id ascii"); return
        }
        #expect(ascii.unitsPerEm == 1000)
        #expect(ascii.defaultAdvance == 481)
        #expect(ascii.glyphs.count > 90)
        let a = Unicode.Scalar("A")
        #expect(ascii.glyphs[a]?.advance == 667)
        #expect(ascii.glyphs[a]?.commands != nil)
        let space = Unicode.Scalar(" ")
        #expect(ascii.glyphs[space]?.advance == 278)
        #expect(ascii.glyphs[space]?.commands == nil)
    }

    @Test func loadsFreeSerifFontsForTspanConformance() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let svgURL = repoRoot
            .appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/text-tspan-01-b.svg")

        let doc = try SVGParser().parse(url: svgURL)
        guard let regular = doc.fonts["FreeSerif"] else {
            Issue.record("expected FreeSerif font table"); return
        }
        guard let bold = doc.fonts["FreeSerifBold"] else {
            Issue.record("expected FreeSerifBold font table"); return
        }
        #expect(regular.unitsPerEm == 1000)
        #expect(regular.glyphs.count > 100)
        #expect(bold.glyphs.count > 100)
        let space = Unicode.Scalar(" ")
        let apostrophe = Unicode.Scalar("'")
        #expect(regular.glyphs[space]?.advance == 250)
        #expect(bold.glyphs[space]?.advance == 250)
        #expect(regular.glyphs[apostrophe]?.commands != nil)
        #expect(bold.glyphs[apostrophe]?.commands != nil)

        let boldFaces = doc.fontFaces.filter { $0.family == "FreeSerif" && $0.weight == .bold }
        #expect(boldFaces.count == 2) // bold + bold-italic faces
        #expect(doc.fonts[boldFaces[0].fontID] != nil)

        let quote = Unicode.Scalar("\"")
        #expect(regular.glyphs[quote]?.commands != nil)
    }

    @Test func registersFontFaceAndLoadsReferencedFont() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
          <defs>
            <font id="ascii" horiz-adv-x="100">
              <font-face units-per-em="100" ascent="80" descent="-20"/>
              <glyph unicode="!" d="M10 0V50H30V0H10Z" horiz-adv-x="40"/>
            </font>
            <font-face font-family="MiniASCII">
              <font-face-src>
                <font-face-uri xlink:href="#ascii"/>
              </font-face-src>
            </font-face>
          </defs>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        #expect(doc.fontFaces.count == 1)
        #expect(doc.fontFaces[0].family == "MiniASCII")
        #expect(doc.fonts["ascii"]?.glyphs[Unicode.Scalar("!")] != nil)
    }

    @Test func loadsExternalFontViaFontFaceURI() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let svgDir = repoRoot
            .appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg")
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
          <defs>
            <font-face font-family="SVGFreeSansASCII">
              <font-face-src>
                <font-face-uri xlink:href="../resources/SVGFreeSans.svg#ascii"/>
              </font-face-src>
            </font-face>
          </defs>
        </svg>
        """
        let doc = try SVGParser().parse(
            data: Data(svg.utf8),
            baseURL: svgDir
        )
        #expect(doc.fontFaces.count == 1)
        #expect(doc.fontFaces[0].family == "SVGFreeSansASCII")
        guard let ascii = doc.fonts["ascii"] else {
            Issue.record("expected external font id ascii"); return
        }
        #expect(ascii.glyphs[Unicode.Scalar("A")]?.commands != nil)
    }

    @Test func appliesClassStylesFromStyleElement() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
          <style type="text/css"><![CDATA[
            .testClass { fill: blue; }
            .testClass2 { stroke: orange; }
          ]]></style>
          <rect x="10" y="10" width="50" height="50" class="testClass"/>
          <rect x="60" y="60" width="30" height="30" class="testClass testClass2" stroke-width="5"/>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .rect(let first) = doc.root.children[0],
              case .rect(let second) = doc.root.children[1] else {
            Issue.record("expected two rects"); return
        }
        if case .color(let fill) = first.paint.fill {
            #expect(fill.blue == 1 && fill.red == 0)
        } else {
            Issue.record("expected blue fill from class")
        }
        if case .color(let fill) = second.paint.fill {
            #expect(fill.blue == 1)
        } else {
            Issue.record("expected blue fill from shared class")
        }
        if case .color(let stroke) = second.paint.stroke {
            #expect(stroke.red == 1 && stroke.green > 0.5 && stroke.blue == 0)
        } else {
            Issue.record("expected orange stroke from second class")
        }
        #expect(second.paint.strokeWidth == 5)
    }

    @Test func appliesTypeAndClassStylesFromStyleElement() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
          <defs>
            <style type="text/css">
              rect { fill: green }
              .warning { fill: green }
              .bar { fill: green }
            </style>
          </defs>
          <g style="fill: red">
            <rect x="10" y="10" width="30" height="30"/>
            <circle class="warning" cx="60" cy="25" r="15"/>
            <polygon class="foo bar baz" points="80,10 95,40 65,40"/>
          </g>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .group(let g) = doc.root.children[0] else {
            Issue.record("expected group"); return
        }
        guard case .rect(let rect) = g.children[0],
              case .circle(let circle) = g.children[1],
              case .polygon(let polygon) = g.children[2] else {
            Issue.record("expected rect, circle, polygon"); return
        }
        for (label, shape) in [("rect", rect.paint), ("circle", circle.paint), ("polygon", polygon.paint)] {
            guard case .color(let fill) = shape.fill else {
                Issue.record("expected green fill on \(label)"); return
            }
            #expect(fill.green > 0.4 && fill.red < 0.1, "expected green fill on \(label)")
        }
    }

    @Test func stylingCss01bRectsGetGreenFillFromTypeSelector() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let svgURL = repoRoot
            .appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/styling-css-01-b.svg")
        let data = try Data(contentsOf: svgURL)
        let doc = try SVGParser().parse(data: data, baseURL: svgURL.deletingLastPathComponent())

        var rects: [SVGRect] = []
        func collectRects(_ el: SVGElement) {
            switch el {
            case .rect(let r): rects.append(r)
            case .group(let g): g.children.forEach(collectRects)
            default: break
            }
        }
        collectRects(.group(SVGGroup(children: doc.root.children)))

        #expect(rects.count >= 2)
        for (index, rect) in rects.enumerated() where rect.paint.fill != .none {
            guard case .color(let fill) = rect.paint.fill else {
                Issue.record("rect \(index) expected color fill"); return
            }
            #expect(fill.green > 0.4 && fill.red < 0.1, "rect \(index) expected green from type selector")
        }
    }

    @Test func appliesIdAndAttributeStylesFromStyleElement() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
          <defs>
            <style type="text/css">
              #one, #two { fill: green }
              [transform="scale(2)"] { fill: green }
              #x [points] { fill: green }
            </style>
          </defs>
          <g style="fill: red">
            <rect id="one" x="10" y="10" width="20" height="20"/>
            <rect id="two" x="40" y="10" width="20" height="20"/>
            <circle transform="scale(2)" cx="70" cy="20" r="10"/>
          </g>
          <g style="fill: red" id="x">
            <polygon points="10,50 30,70 50,50"/>
          </g>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .group(let body) = doc.root.children[0] else {
            Issue.record("expected body group"); return
        }
        guard case .rect(let one) = body.children[0],
              case .rect(let two) = body.children[1],
              case .circle(let circle) = body.children[2] else {
            Issue.record("expected rects and circle"); return
        }
        guard case .group(let xGroup) = doc.root.children[1],
              case .polygon(let polygon) = xGroup.children[0] else {
            Issue.record("expected polygon in #x group"); return
        }
        for (label, shape) in [
            ("#one", one.paint), ("#two", two.paint),
            ("[transform]", circle.paint), ("#x [points]", polygon.paint),
        ] {
            guard case .color(let fill) = shape.fill else {
                Issue.record("expected green fill on \(label)"); return
            }
            #expect(fill.green > 0.4 && fill.red < 0.1, "expected green fill on \(label)")
        }
    }

    @Test func stylingCss02bShapesGetGreenFillFromSelectors() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let svgURL = repoRoot
            .appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/styling-css-02-b.svg")
        let data = try Data(contentsOf: svgURL)
        let doc = try SVGParser().parse(data: data, baseURL: svgURL.deletingLastPathComponent())

        var paintedShapes: [SVGPaintProperties] = []
        func collectPaintedShapes(_ el: SVGElement) {
            switch el {
            case .rect(let r) where r.paint.fill != .none: paintedShapes.append(r.paint)
            case .circle(let c) where c.paint.fill != .none: paintedShapes.append(c.paint)
            case .polygon(let p) where p.paint.fill != .none: paintedShapes.append(p.paint)
            case .group(let g): g.children.forEach(collectPaintedShapes)
            default: break
            }
        }
        collectPaintedShapes(.group(SVGGroup(children: doc.root.children)))

        // Six content shapes (excluding test-frame rect and revision text).
        #expect(paintedShapes.count >= 6)
        for (index, paint) in paintedShapes.prefix(6).enumerated() {
            guard case .color(let fill) = paint.fill else {
                Issue.record("shape \(index) expected color fill"); return
            }
            #expect(fill.green > 0.4 && fill.red < 0.1, "shape \(index) expected green fill")
        }
    }

    @Test func stylingCss03bShapesGetGreenFillFromSelectors() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let svgURL = repoRoot
            .appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/styling-css-03-b.svg")
        let data = try Data(contentsOf: svgURL)
        let doc = try SVGParser().parse(data: data, baseURL: svgURL.deletingLastPathComponent())

        var paintedShapes: [SVGPaintProperties] = []
        func collectPaintedShapes(_ el: SVGElement) {
            switch el {
            case .rect(let r) where r.paint.fill != .none: paintedShapes.append(r.paint)
            case .circle(let c) where c.paint.fill != .none: paintedShapes.append(c.paint)
            case .polygon(let p) where p.paint.fill != .none: paintedShapes.append(p.paint)
            case .group(let g): g.children.forEach(collectPaintedShapes)
            default: break
            }
        }
        collectPaintedShapes(.group(SVGGroup(children: doc.root.children)))

        #expect(paintedShapes.count >= 6)
        for (index, paint) in paintedShapes.prefix(6).enumerated() {
            guard case .color(let fill) = paint.fill else {
                Issue.record("shape \(index) expected color fill"); return
            }
            #expect(fill.green > 0.4 && fill.red < 0.1, "shape \(index) expected green fill")
        }
    }

    @Test func stylingCss04fGridUsesExpectedColumnColors() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let svgURL = repoRoot
            .appendingPathComponent("Tests/SVGConformanceTests/Resources/W3C-SVG-1.1/svg/styling-css-04-f.svg")
        let data = try Data(contentsOf: svgURL)
        let doc = try SVGParser().parse(data: data, baseURL: svgURL.deletingLastPathComponent())

        var contentRects: [SVGRect] = []
        func collectRects(_ el: SVGElement) {
            switch el {
            case .rect(let rect):
                // Skip outer frame and any non-grid rectangles.
                let x = rect.origin.x
                let y = rect.origin.y
                if abs(rect.size.width - 67.5) < 0.01,
                   abs(rect.size.height - 67.5) < 0.01,
                   x >= 30, x <= 380, y >= 70, y <= 210
                {
                    contentRects.append(rect)
                }
            case .group(let g):
                g.children.forEach(collectRects)
            default:
                break
            }
        }
        collectRects(.group(SVGGroup(children: doc.root.children)))

        #expect(contentRects.count == 18)

        let expectedColumns: [(x: CGFloat, color: String)] = [
            (30, "blue"),
            (100, "green"),
            (170, "orange"),
            (240, "gold"),
            (310, "purple"),
            (380, "silver"),
        ]
        let expectedRows: [CGFloat] = [70, 140, 210]

        func rectAt(x: CGFloat, y: CGFloat) -> SVGRect? {
            for rect in contentRects {
                if abs(rect.origin.x - x) < 0.01 && abs(rect.origin.y - y) < 0.01 {
                    return rect
                }
            }
            return nil
        }

        for column in expectedColumns {
            for row in expectedRows {
                guard let rect = rectAt(x: column.x, y: row) else {
                    Issue.record("missing rect at x=\(column.x), y=\(row)"); return
                }
                guard case .color(let fill) = rect.paint.fill else {
                    Issue.record("expected color fill at x=\(column.x), y=\(row)"); return
                }
                switch column.color {
                case "blue":
                    #expect(fill.blue > 0.45 && fill.red < 0.2 && fill.green < 0.3, "x=\(column.x), y=\(row) expected blue")
                case "green":
                    #expect(fill.green > 0.35 && fill.red < 0.2 && fill.blue < 0.2, "x=\(column.x), y=\(row) expected green")
                case "orange":
                    #expect(fill.red > 0.6 && fill.green > 0.2 && fill.green < 0.7 && fill.blue < 0.15, "x=\(column.x), y=\(row) expected orange")
                case "gold":
                    #expect(fill.red > 0.6 && fill.green > 0.45 && fill.blue < 0.2, "x=\(column.x), y=\(row) expected gold")
                case "purple":
                    #expect(fill.red > 0.35 && fill.blue > 0.35 && fill.green < 0.25, "x=\(column.x), y=\(row) expected purple")
                case "silver":
                    #expect(fill.red > 0.65 && fill.green > 0.65 && fill.blue > 0.65, "x=\(column.x), y=\(row) expected silver")
                    #expect(abs(fill.red - fill.green) < 0.15 && abs(fill.green - fill.blue) < 0.15, "x=\(column.x), y=\(row) expected near-gray silver")
                default:
                    Issue.record("unexpected column color \(column.color)")
                }
            }
        }
    }

    @Test func capturesAnimateChildrenOnRect() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
          <rect x="10" y="10" width="20" height="20">
            <animate attributeName="width" from="20" to="40" dur="2s" begin="0s"/>
          </rect>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .rect(let rect) = doc.root.children.first else {
            Issue.record("expected rect"); return
        }
        #expect(rect.animations.count == 1)
        guard case .animate(let animate) = rect.animations[0] else {
            Issue.record("expected animate"); return
        }
        #expect(animate.attributeName == "width")
        #expect(animate.timing.dur == 2)
    }
}

@Suite("SVGParser — conditional processing")
struct SVGParserConditionalTests {

    @Test func switchSelectsFirstMatchingRequiredExtensionsChild() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
          <switch>
            <rect fill="red" width="10" height="10" requiredExtensions="http://example.org/bogus"/>
            <rect fill="green" y="5" width="10" height="5"/>
            <rect fill="blue" x="5" width="5" height="10"/>
          </switch>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        #expect(doc.root.children.count == 1)
        guard case .rect(let rect) = doc.root.children[0] else {
            Issue.record("expected single rect"); return
        }
        guard case .color(let fill) = rect.paint.fill else {
            Issue.record("expected color fill"); return
        }
        #expect(fill.green > 0.4 && fill.red < 0.2 && fill.blue < 0.2)
        #expect(rect.origin.y == 5)
    }

    @Test func switchSelectsSystemLanguageMatch() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
          <switch>
            <text systemLanguage="fr" y="1">French</text>
            <text systemLanguage="en" y="2">English</text>
            <text y="3">Fallback</text>
          </switch>
        </svg>
        """
        let context = SVGConditionalProcessingContext(preferredLanguages: ["en-US"])
        let doc = try SVGParser(conditionalContext: context).parse(string: svg)
        #expect(doc.root.children.count == 1)
        guard case .text(let text) = doc.root.children[0] else {
            Issue.record("expected text"); return
        }
        #expect(text.runs.map(\.string).joined() == "English")
        #expect(text.origin.y == 2)
    }

    @Test func switchUsesDefaultChildWhenNoLanguageMatches() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
          <switch>
            <text systemLanguage="fr" y="1">French</text>
            <text systemLanguage="de" y="2">German</text>
            <g>
              <text y="3">One</text>
              <text y="4">Two</text>
            </g>
          </switch>
        </svg>
        """
        let context = SVGConditionalProcessingContext(preferredLanguages: ["xx"])
        let doc = try SVGParser(conditionalContext: context).parse(string: svg)
        #expect(doc.root.children.count == 1)
        guard case .group(let group) = doc.root.children[0] else {
            Issue.record("expected default group"); return
        }
        #expect(group.children.count == 2)
    }

    @Test func switchSelectsRequiredFeaturesChild() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
          <switch>
            <rect fill="red" width="10" height="10"
              requiredFeatures="http://www.w3.org/TR/SVG11/feature#SVGDOM"/>
            <rect fill="green" width="10" height="10"
              requiredFeatures="http://www.w3.org/TR/SVG11/feature#BasicText"/>
          </switch>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .rect(let rect) = doc.root.children[0] else {
            Issue.record("expected rect"); return
        }
        guard case .color(let fill) = rect.paint.fill else {
            Issue.record("expected color fill"); return
        }
        #expect(fill.green > 0.4 && fill.red < 0.2)
    }
}

@Suite("SVGParser — script metadata")
struct SVGParserScriptTests {

    @Test func parsesScriptHandle01Metadata() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repo.appendingPathComponent(
            "SVGConformanceTests/Resources/W3C-SVG-1.1/svg/script-handle-01-b.svg"
        )
        let data = try Data(contentsOf: url)
        let doc = try SVGParser().parse(data: data, baseURL: url.deletingLastPathComponent())
        #expect(doc.scriptMetadata.blocks.count == 1)
        #expect(doc.scriptMetadata.elementIndex["target"] != nil)
        #expect(doc.scriptMetadata.elementIndex["testPassed"] != nil)
        #expect(doc.scriptMetadata.handlersByElementID["target"]?.contains(where: { $0.event == "click" }) == true)
    }

    @Test func parsesGroupVisibility() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
          <g id="hidden" visibility="hidden">
            <rect width="10" height="10"/>
          </g>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .group(let group) = doc.root.children.first else {
            Issue.record("expected group"); return
        }
        #expect(group.id == "hidden")
        #expect(group.visibility == .hidden)
    }

    @Test func parsesNestedSVGViewport() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="480" height="360" viewBox="0 0 480 360">
          <g>
            <svg x="115" y="100" width="250" height="160">
              <g transform="translate(50,-15)">
                <rect x="10" y="10" width="20" height="20" fill="#ff0000"/>
              </g>
            </svg>
          </g>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .group(let g) = doc.root.children.first else {
            Issue.record("expected group"); return
        }
        guard case .svg(let inner) = g.children.first else {
            Issue.record("expected nested svg"); return
        }
        #expect(inner.origin == CGPoint(x: 115, y: 100))
        #expect(inner.size == CGSize(width: 250, height: 160))
        #expect(inner.overflow == .hidden)
        #expect(inner.viewBox == nil)
        guard case .group(let viewportGroup) = inner.children.first else {
            Issue.record("expected group inside nested svg"); return
        }
        let transformedOrigin = CGPoint(x: 0, y: 0).applying(viewportGroup.transform.matrix)
        #expect(transformedOrigin == CGPoint(x: 50, y: -15))
        guard case .rect(let r) = viewportGroup.children.first else {
            Issue.record("expected rect inside nested svg group"); return
        }
        #expect(r.origin == CGPoint(x: 10, y: 10))
    }

    @Test func parsesNestedSVGPreserveAspectRatio() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
          <svg x="0" y="0" width="50" height="30" viewBox="0 0 30 40"
               preserveAspectRatio="xMaxYMax slice">
            <rect x="0" y="0" width="30" height="40" fill="red"/>
          </svg>
        </svg>
        """
        let doc = try SVGParser().parse(string: svg)
        guard case .svg(let inner) = doc.root.children.first else {
            Issue.record("expected nested svg"); return
        }
        #expect(inner.preserveAspectRatio == SVGPreserveAspectRatio(align: .xMaxYMax, meetOrSlice: .slice))
        #expect(inner.viewBox == CGRect(x: 0, y: 0, width: 30, height: 40))
    }

    @Test func parsesImageGeometryAndHref() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
             width="100" height="100">
          <image x="10" y="20" width="30" height="40"
                 preserveAspectRatio="xMidYMid meet"
                 xlink:href="photo.png"/>
        </svg>
        """
        let base = URL(fileURLWithPath: "/tmp/test/svg", isDirectory: true)
        let doc = try SVGParser().parse(string: svg, baseURL: base)
        guard case .image(let img) = doc.root.children.first else {
            Issue.record("expected image"); return
        }
        #expect(img.origin == CGPoint(x: 10, y: 20))
        #expect(img.size == CGSize(width: 30, height: 40))
        #expect(img.href == "photo.png")
        #expect(img.preserveAspectRatio == SVGPreserveAspectRatio(align: .xMidYMid, meetOrSlice: .meet))
        #expect(doc.resolveURL(img.href)?.lastPathComponent == "photo.png")
    }
}
