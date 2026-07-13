import CoreGraphics
import Foundation
import SVGCore

/// Parses the SVG `path` `d=` attribute into normalized absolute-coordinate
/// commands. Supports M/m L/l H/h V/v C/c S/s Q/q T/t A/a Z/z, the implicit
/// repeated-parameter rule, and arc-to-cubic decomposition.
enum PathDataParser {

    struct ParseResult {
        let commands: [SVGPathCommand]
        let truncated: Bool
    }

    /// Returns nil for empty input. Stops at `maxCommands` and sets `truncated`.
    static func parse(_ raw: String, maxCommands: Int) -> ParseResult? {
        var scanner = PathScanner(input: raw)
        guard scanner.hasNumberOrCommand else { return nil }
        var out: [SVGPathCommand] = []
        var truncated = false

        func append(_ command: SVGPathCommand) -> Bool {
            guard out.count < maxCommands else {
                truncated = true
                return false
            }
            out.append(command)
            return true
        }

        var current = CGPoint.zero          // current point
        var subpathStart = CGPoint.zero     // for Z/z
        var lastCubicCtrl: CGPoint? = nil   // for S/s reflection
        var lastQuadCtrl: CGPoint? = nil    // for T/t reflection
        var lastCommand: UInt8? = nil

        scanner.skipWhitespaceAndCommas()
        while let cmd = scanner.readCommand() {
            if truncated { break }
            let isRelative = cmd >= 97 && cmd <= 122
            let upper = isRelative ? cmd - 32 : cmd

            // M/m must come first; subsequent coordinate pairs after a moveto
            // are implicit linetos (per SVG path grammar).
            var isFirstIteration = true
            repeat {
                if truncated || (!isFirstIteration && !scanner.hasNumber) { break }

                switch upper {
                case 77: // M
                    guard let p = scanner.readPoint() else { return ParseResult(commands: out, truncated: truncated) }
                    let target = isRelative && lastCommand != nil
                        ? CGPoint(x: current.x + p.x, y: current.y + p.y)
                        : p
                    if isFirstIteration {
                        guard append(.moveTo(target)) else { break }
                        subpathStart = target
                    } else {
                        guard append(.lineTo(target)) else { break }
                    }
                    current = target
                    lastCubicCtrl = nil
                    lastQuadCtrl = nil

                case 76: // L
                    guard let p = scanner.readPoint() else { return ParseResult(commands: out, truncated: truncated) }
                    let target = isRelative
                        ? CGPoint(x: current.x + p.x, y: current.y + p.y)
                        : p
                    guard append(.lineTo(target)) else { break }
                    current = target
                    lastCubicCtrl = nil
                    lastQuadCtrl = nil

                case 72: // H
                    guard let x = scanner.readNumber() else { return ParseResult(commands: out, truncated: truncated) }
                    let target = CGPoint(
                        x: isRelative ? current.x + x : x,
                        y: current.y
                    )
                    guard append(.lineTo(target)) else { break }
                    current = target
                    lastCubicCtrl = nil
                    lastQuadCtrl = nil

                case 86: // V
                    guard let y = scanner.readNumber() else { return ParseResult(commands: out, truncated: truncated) }
                    let target = CGPoint(
                        x: current.x,
                        y: isRelative ? current.y + y : y
                    )
                    guard append(.lineTo(target)) else { break }
                    current = target
                    lastCubicCtrl = nil
                    lastQuadCtrl = nil

                case 67: // C
                    guard let c1 = scanner.readPoint(),
                          let c2 = scanner.readPoint(),
                          let end = scanner.readPoint() else { return ParseResult(commands: out, truncated: truncated) }
                    let absC1 = isRelative ? c1.offset(by: current) : c1
                    let absC2 = isRelative ? c2.offset(by: current) : c2
                    let absEnd = isRelative ? end.offset(by: current) : end
                    guard append(.cubicTo(control1: absC1, control2: absC2, end: absEnd)) else { break }
                    current = absEnd
                    lastCubicCtrl = absC2
                    lastQuadCtrl = nil

                case 83: // S
                    guard let c2 = scanner.readPoint(),
                          let end = scanner.readPoint() else { return ParseResult(commands: out, truncated: truncated) }
                    let absC2 = isRelative ? c2.offset(by: current) : c2
                    let absEnd = isRelative ? end.offset(by: current) : end
                    let absC1: CGPoint
                    if let prev = lastCubicCtrl {
                        absC1 = CGPoint(x: 2 * current.x - prev.x,
                                        y: 2 * current.y - prev.y)
                    } else {
                        absC1 = current
                    }
                    guard append(.cubicTo(control1: absC1, control2: absC2, end: absEnd)) else { break }
                    current = absEnd
                    lastCubicCtrl = absC2
                    lastQuadCtrl = nil

                case 81: // Q
                    guard let c = scanner.readPoint(),
                          let end = scanner.readPoint() else { return ParseResult(commands: out, truncated: truncated) }
                    let absC = isRelative ? c.offset(by: current) : c
                    let absEnd = isRelative ? end.offset(by: current) : end
                    guard append(.quadTo(control: absC, end: absEnd)) else { break }
                    current = absEnd
                    lastQuadCtrl = absC
                    lastCubicCtrl = nil

                case 84: // T
                    guard let end = scanner.readPoint() else { return ParseResult(commands: out, truncated: truncated) }
                    let absEnd = isRelative ? end.offset(by: current) : end
                    let absC: CGPoint
                    if let prev = lastQuadCtrl {
                        absC = CGPoint(x: 2 * current.x - prev.x,
                                       y: 2 * current.y - prev.y)
                    } else {
                        absC = current
                    }
                    guard append(.quadTo(control: absC, end: absEnd)) else { break }
                    current = absEnd
                    lastQuadCtrl = absC
                    lastCubicCtrl = nil

                case 65: // A
                    guard let rx = scanner.readNumber(),
                          let ry = scanner.readNumber(),
                          let xrot = scanner.readNumber(),
                          let largeArc = scanner.readFlag(),
                          let sweep = scanner.readFlag(),
                          let end = scanner.readPoint() else { return ParseResult(commands: out, truncated: truncated) }
                    let absEnd = isRelative ? end.offset(by: current) : end
                    let arcs = arcToCubics(
                        from: current, to: absEnd,
                        rx: rx, ry: ry,
                        xAxisRotation: xrot,
                        largeArc: largeArc, sweep: sweep
                    )
                    for arc in arcs {
                        guard append(arc) else { break }
                    }
                    current = absEnd
                    lastCubicCtrl = nil
                    lastQuadCtrl = nil

                case 90: // Z
                    guard append(.close) else { break }
                    current = subpathStart
                    lastCubicCtrl = nil
                    lastQuadCtrl = nil

                default:
                    return ParseResult(commands: out, truncated: truncated)
                }

                isFirstIteration = false
                lastCommand = cmd
                scanner.skipWhitespaceAndCommas()
            } while upper != 90  // Z takes no parameters; never iterates
        }

        return ParseResult(commands: out, truncated: truncated)
    }

    /// Returns nil for empty input. Returns the parsed commands even if the
    /// data ends mid-stream (matches permissive UA behavior).
    static func parse(_ raw: String) -> [SVGPathCommand]? {
        parse(raw, maxCommands: .max)?.commands
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
    private let bytes: [UInt8]
    private var index: Int

    init(input: String) {
        self.bytes = Array(input.utf8)
        self.index = bytes.startIndex
    }

    var hasNumberOrCommand: Bool {
        var i = index
        while i < bytes.endIndex, isWhitespaceOrComma(bytes[i]) {
            i += 1
        }
        guard i < bytes.endIndex else { return false }
        let c = bytes[i]
        return isNumberStart(c) || isLetter(c)
    }

    var hasNumber: Bool {
        var i = index
        while i < bytes.endIndex, isWhitespaceOrComma(bytes[i]) {
            i += 1
        }
        guard i < bytes.endIndex else { return false }
        return isNumberStart(bytes[i])
    }

    mutating func readCommand() -> UInt8? {
        skipWhitespaceAndCommas()
        guard index < bytes.endIndex else { return nil }
        let c = bytes[index]
        guard isLetter(c) else { return nil }
        index += 1
        return c
    }

    mutating func readPoint() -> CGPoint? {
        guard let x = readNumber(), let y = readNumber() else { return nil }
        return CGPoint(x: x, y: y)
    }

    /// Arc flag: single 0 or 1 token (whitespace/comma-separated).
    mutating func readFlag() -> Bool? {
        skipWhitespaceAndCommas()
        guard index < bytes.endIndex else { return nil }
        let c = bytes[index]
        if c == 48 {
            index += 1
            return false
        }
        if c == 49 {
            index += 1
            return true
        }
        return nil
    }

    mutating func readNumber() -> CGFloat? {
        skipWhitespaceAndCommas()
        let start = index

        var sign = 1.0
        if index < bytes.endIndex {
            if bytes[index] == 45 {
                sign = -1.0
                index += 1
            } else if bytes[index] == 43 {
                index += 1
            }
        }

        var mantissa = 0.0
        var sawDigit = false
        while index < bytes.endIndex, isDigit(bytes[index]) {
            sawDigit = true
            mantissa = mantissa * 10.0 + Double(bytes[index] - 48)
            index += 1
        }

        if index < bytes.endIndex, bytes[index] == 46 {
            index += 1
            var divisor = 10.0
            while index < bytes.endIndex, isDigit(bytes[index]) {
                sawDigit = true
                mantissa += Double(bytes[index] - 48) / divisor
                divisor *= 10.0
                index += 1
            }
        }

        guard sawDigit else {
            index = start
            return nil
        }

        var exponent = 0
        if index < bytes.endIndex, bytes[index] == 69 || bytes[index] == 101 {
            let exponentStart = index
            index += 1

            var exponentSign = 1
            if index < bytes.endIndex {
                if bytes[index] == 45 {
                    exponentSign = -1
                    index += 1
                } else if bytes[index] == 43 {
                    index += 1
                }
            }

            var sawExponentDigit = false
            while index < bytes.endIndex, isDigit(bytes[index]) {
                sawExponentDigit = true
                exponent = exponent * 10 + Int(bytes[index] - 48)
                index += 1
            }

            if sawExponentDigit {
                exponent *= exponentSign
            } else {
                index = exponentStart
            }
        }

        let value = exponent == 0
            ? sign * mantissa
            : sign * mantissa * pow(10.0, Double(exponent))
        return CGFloat(value)
    }

    mutating func skipWhitespaceAndCommas() {
        while index < bytes.endIndex, isWhitespaceOrComma(bytes[index]) {
            index += 1
        }
    }

    private func isNumberStart(_ byte: UInt8) -> Bool {
        isDigit(byte) || byte == 45 || byte == 43 || byte == 46
    }

    private func isLetter(_ byte: UInt8) -> Bool {
        (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
    }

    private func isDigit(_ byte: UInt8) -> Bool {
        byte >= 48 && byte <= 57
    }

    private func isWhitespaceOrComma(_ byte: UInt8) -> Bool {
        byte == 44 || byte == 32 || byte == 9 || byte == 10 || byte == 13 || byte == 12
    }
}

private extension CGPoint {
    func offset(by other: CGPoint) -> CGPoint {
        CGPoint(x: x + other.x, y: y + other.y)
    }
}
