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
}
