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
}
