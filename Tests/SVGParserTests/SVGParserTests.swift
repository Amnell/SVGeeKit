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
}
