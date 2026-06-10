import CoreGraphics
import Foundation
import SVGCore

/// Parses the SVG `path` `d=` attribute into normalized absolute-coordinate
/// commands. Supports M/m L/l H/h V/v C/c S/s Q/q T/t A/a Z/z, the implicit
/// repeated-parameter rule, and arc-to-cubic decomposition.
enum PathDataParser {

    /// Returns nil for empty input. Returns the parsed commands even if the
    /// data ends mid-stream (matches permissive UA behavior).
    static func parse(_ raw: String) -> [SVGPathCommand]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var scanner = PathScanner(input: trimmed)
        var out: [SVGPathCommand] = []

        var current = CGPoint.zero          // current point
        var subpathStart = CGPoint.zero     // for Z/z
        var lastCubicCtrl: CGPoint? = nil   // for S/s reflection
        var lastQuadCtrl: CGPoint? = nil    // for T/t reflection
        var lastCommand: Character? = nil

        scanner.skipWhitespaceAndCommas()
        while let cmd = scanner.readCommand() {
            let isRelative = cmd.isLowercase
            let upper = Character(cmd.uppercased())

            // M/m must come first; subsequent coordinate pairs after a moveto
            // are implicit linetos (per SVG path grammar).
            var isFirstIteration = true
            repeat {
                if !isFirstIteration && !scanner.hasNumber { break }

                switch upper {
                case "M":
                    guard let p = scanner.readPoint() else { return out }
                    let target = isRelative && lastCommand != nil
                        ? CGPoint(x: current.x + p.x, y: current.y + p.y)
                        : p
                    if isFirstIteration {
                        out.append(.moveTo(target))
                        subpathStart = target
                    } else {
                        // Implicit lineto after moveto.
                        out.append(.lineTo(target))
                    }
                    current = target
                    lastCubicCtrl = nil
                    lastQuadCtrl = nil

                case "L":
                    guard let p = scanner.readPoint() else { return out }
                    let target = isRelative
                        ? CGPoint(x: current.x + p.x, y: current.y + p.y)
                        : p
                    out.append(.lineTo(target))
                    current = target
                    lastCubicCtrl = nil
                    lastQuadCtrl = nil

                case "H":
                    guard let x = scanner.readNumber() else { return out }
                    let target = CGPoint(
                        x: isRelative ? current.x + x : x,
                        y: current.y
                    )
                    out.append(.lineTo(target))
                    current = target
                    lastCubicCtrl = nil
                    lastQuadCtrl = nil

                case "V":
                    guard let y = scanner.readNumber() else { return out }
                    let target = CGPoint(
                        x: current.x,
                        y: isRelative ? current.y + y : y
                    )
                    out.append(.lineTo(target))
                    current = target
                    lastCubicCtrl = nil
                    lastQuadCtrl = nil

                case "C":
                    guard let c1 = scanner.readPoint(),
                          let c2 = scanner.readPoint(),
                          let end = scanner.readPoint() else { return out }
                    let absC1 = isRelative ? c1.offset(by: current) : c1
                    let absC2 = isRelative ? c2.offset(by: current) : c2
                    let absEnd = isRelative ? end.offset(by: current) : end
                    out.append(.cubicTo(control1: absC1, control2: absC2, end: absEnd))
                    current = absEnd
                    lastCubicCtrl = absC2
                    lastQuadCtrl = nil

                case "S":
                    guard let c2 = scanner.readPoint(),
                          let end = scanner.readPoint() else { return out }
                    let absC2 = isRelative ? c2.offset(by: current) : c2
                    let absEnd = isRelative ? end.offset(by: current) : end
                    // Reflect previous cubic control point. If the previous
                    // command wasn't a cubic, the spec says use the current point.
                    let absC1: CGPoint
                    if let prev = lastCubicCtrl {
                        absC1 = CGPoint(x: 2 * current.x - prev.x,
                                        y: 2 * current.y - prev.y)
                    } else {
                        absC1 = current
                    }
                    out.append(.cubicTo(control1: absC1, control2: absC2, end: absEnd))
                    current = absEnd
                    lastCubicCtrl = absC2
                    lastQuadCtrl = nil

                case "Q":
                    guard let c = scanner.readPoint(),
                          let end = scanner.readPoint() else { return out }
                    let absC = isRelative ? c.offset(by: current) : c
                    let absEnd = isRelative ? end.offset(by: current) : end
                    out.append(.quadTo(control: absC, end: absEnd))
                    current = absEnd
                    lastQuadCtrl = absC
                    lastCubicCtrl = nil

                case "T":
                    guard let end = scanner.readPoint() else { return out }
                    let absEnd = isRelative ? end.offset(by: current) : end
                    let absC: CGPoint
                    if let prev = lastQuadCtrl {
                        absC = CGPoint(x: 2 * current.x - prev.x,
                                       y: 2 * current.y - prev.y)
                    } else {
                        absC = current
                    }
                    out.append(.quadTo(control: absC, end: absEnd))
                    current = absEnd
                    lastQuadCtrl = absC
                    lastCubicCtrl = nil

                case "A":
                    guard let rx = scanner.readNumber(),
                          let ry = scanner.readNumber(),
                          let xrot = scanner.readNumber(),
                          let largeArc = scanner.readFlag(),
                          let sweep = scanner.readFlag(),
                          let end = scanner.readPoint() else { return out }
                    let absEnd = isRelative ? end.offset(by: current) : end
                    let arcs = arcToCubics(
                        from: current, to: absEnd,
                        rx: rx, ry: ry,
                        xAxisRotation: xrot,
                        largeArc: largeArc, sweep: sweep
                    )
                    out.append(contentsOf: arcs)
                    current = absEnd
                    lastCubicCtrl = nil
                    lastQuadCtrl = nil

                case "Z":
                    out.append(.close)
                    current = subpathStart
                    lastCubicCtrl = nil
                    lastQuadCtrl = nil

                default:
                    return out
                }

                isFirstIteration = false
                lastCommand = cmd
                scanner.skipWhitespaceAndCommas()
            } while upper != "Z"  // Z takes no parameters; never iterates
        }

        return out
    }

    // MARK: - Arc decomposition

    /// Endpoint → center parameterization (SVG Implementation Notes F.6.5),
    /// then approximates the arc with up to 4 cubic Bezier segments. Each
    /// sub-arc spans ≤ π/2 to keep approximation error small.
    private static func arcToCubics(
        from p1: CGPoint, to p2: CGPoint,
        rx rxIn: CGFloat, ry ryIn: CGFloat,
        xAxisRotation: CGFloat,
        largeArc: Bool, sweep: Bool
    ) -> [SVGPathCommand] {
        // Degenerate: identical endpoints → no segment per spec.
        if p1 == p2 { return [] }
        // Zero radius → straight line.
        if rxIn == 0 || ryIn == 0 {
            return [.lineTo(p2)]
        }

        var rx = abs(rxIn)
        var ry = abs(ryIn)
        let phi = xAxisRotation * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        // Step 1: compute (x1', y1') — endpoint in rotated coordinates.
        let dx = (p1.x - p2.x) / 2
        let dy = (p1.y - p2.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        // Ensure radii are large enough; scale up if not (per spec).
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s
            ry *= s
        }

        // Step 2: compute (cx', cy').
        let rx2 = rx * rx
        let ry2 = ry * ry
        let x1p2 = x1p * x1p
        let y1p2 = y1p * y1p
        let denom = rx2 * y1p2 + ry2 * x1p2
        var factor = (rx2 * ry2 - denom) / denom
        if factor < 0 { factor = 0 }
        var coef = sqrt(factor)
        if largeArc == sweep { coef = -coef }
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * -(ry * x1p / rx)

        // Step 3: compute (cx, cy) from (cx', cy').
        let cx = cosPhi * cxp - sinPhi * cyp + (p1.x + p2.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p1.y + p2.y) / 2

        // Step 4: compute theta1 and delta-theta.
        let ux = (x1p - cxp) / rx
        let uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx
        let vy = (-y1p - cyp) / ry

        let theta1 = angle(1, 0, ux, uy)
        var deltaTheta = angle(ux, uy, vx, vy)
        if !sweep && deltaTheta > 0 { deltaTheta -= 2 * .pi }
        if sweep && deltaTheta < 0 { deltaTheta += 2 * .pi }

        // Step 5: split into segments of ≤ π/2 and approximate each as cubic.
        let segmentCount = max(1, Int(ceil(abs(deltaTheta) / (.pi / 2))))
        let segmentAngle = deltaTheta / CGFloat(segmentCount)
        // Cubic approximation control-arm length for an arc of angle a:
        // t = (4/3) * tan(a/4)
        let t = (4.0 / 3.0) * tan(segmentAngle / 4)

        var out: [SVGPathCommand] = []
        out.reserveCapacity(segmentCount)
        for i in 0..<segmentCount {
            let startAngle = theta1 + CGFloat(i) * segmentAngle
            let endAngle = startAngle + segmentAngle
            let cos1 = cos(startAngle), sin1 = sin(startAngle)
            let cos2 = cos(endAngle), sin2 = sin(endAngle)

            // Points in the un-rotated unit-arc frame.
            let p0u = CGPoint(x: cos1, y: sin1)
            let p3u = CGPoint(x: cos2, y: sin2)
            let p1u = CGPoint(x: cos1 - t * sin1, y: sin1 + t * cos1)
            let p2u = CGPoint(x: cos2 + t * sin2, y: sin2 - t * cos2)

            // Scale by radii, rotate by phi, translate to center.
            func mapPoint(_ q: CGPoint) -> CGPoint {
                let xs = q.x * rx
                let ys = q.y * ry
                let xr = cosPhi * xs - sinPhi * ys
                let yr = sinPhi * xs + cosPhi * ys
                return CGPoint(x: xr + cx, y: yr + cy)
            }
            let _ = mapPoint(p0u) // unused — first point matches current path point
            let c1 = mapPoint(p1u)
            let c2 = mapPoint(p2u)
            let endPt = mapPoint(p3u)
            out.append(.cubicTo(control1: c1, control2: c2, end: endPt))
        }
        return out
    }

    /// Signed angle between two vectors (radians), per SVG implementation notes.
    private static func angle(_ ux: CGFloat, _ uy: CGFloat,
                              _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
        let dot = ux * vx + uy * vy
        let len = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
        var c = dot / len
        if c < -1 { c = -1 }
        if c > 1 { c = 1 }
        let sign: CGFloat = (ux * vy - uy * vx < 0) ? -1 : 1
        return sign * acos(c)
    }
}

// MARK: - Scanner

private struct PathScanner {
    let input: String
    private var index: String.Index

    init(input: String) {
        self.input = input
        self.index = input.startIndex
    }

    var hasNumber: Bool {
        var i = index
        while i < input.endIndex, input[i].isWhitespace || input[i] == "," {
            i = input.index(after: i)
        }
        guard i < input.endIndex else { return false }
        let c = input[i]
        return c.isNumber || c == "-" || c == "+" || c == "."
    }

    mutating func readCommand() -> Character? {
        skipWhitespaceAndCommas()
        guard index < input.endIndex else { return nil }
        let c = input[index]
        guard c.isLetter else { return nil }
        index = input.index(after: index)
        return c
    }

    mutating func readPoint() -> CGPoint? {
        guard let x = readNumber(), let y = readNumber() else { return nil }
        return CGPoint(x: x, y: y)
    }

    /// Arc flag: single 0 or 1 token (whitespace/comma-separated).
    mutating func readFlag() -> Bool? {
        skipWhitespaceAndCommas()
        guard index < input.endIndex else { return nil }
        let c = input[index]
        if c == "0" {
            index = input.index(after: index)
            return false
        }
        if c == "1" {
            index = input.index(after: index)
            return true
        }
        return nil
    }

    mutating func readNumber() -> CGFloat? {
        skipWhitespaceAndCommas()
        let start = index
        if index < input.endIndex, input[index] == "+" || input[index] == "-" {
            index = input.index(after: index)
        }
        while index < input.endIndex, input[index].isNumber || input[index] == "." {
            index = input.index(after: index)
        }
        if index < input.endIndex, input[index] == "e" || input[index] == "E" {
            index = input.index(after: index)
            if index < input.endIndex, input[index] == "+" || input[index] == "-" {
                index = input.index(after: index)
            }
            while index < input.endIndex, input[index].isNumber {
                index = input.index(after: index)
            }
        }
        let slice = input[start..<index]
        guard !slice.isEmpty, let d = Double(slice) else {
            index = start
            return nil
        }
        return CGFloat(d)
    }

    mutating func skipWhitespaceAndCommas() {
        while index < input.endIndex, input[index].isWhitespace || input[index] == "," {
            index = input.index(after: index)
        }
    }
}

private extension CGPoint {
    func offset(by other: CGPoint) -> CGPoint {
        CGPoint(x: x + other.x, y: y + other.y)
    }
}
