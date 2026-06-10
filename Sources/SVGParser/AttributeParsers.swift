import CoreGraphics
import Foundation
import SVGCore

/// Parsers for individual attribute values. All return nil for empty input.
enum AttributeParsers {

    /// Splits on whitespace and commas (SVG list-of-numbers grammar).
    static func numberList(_ s: String) -> [CGFloat]? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" || $0 == "," }
        var out: [CGFloat] = []
        out.reserveCapacity(parts.count)
        for p in parts {
            guard let d = Double(p) else { return nil }
            out.append(CGFloat(d))
        }
        return out
    }

    static func length(_ s: String) -> SVGLength? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let unitSuffixes: [(String, SVGLength.Unit)] = [
            ("px", .px), ("pt", .pt), ("pc", .pc),
            ("mm", .mm), ("cm", .cm), ("in", .in),
            ("em", .em), ("ex", .ex), ("%", .percent)
        ]
        for (suffix, unit) in unitSuffixes {
            if trimmed.hasSuffix(suffix) {
                let numberPart = String(trimmed.dropLast(suffix.count))
                guard let d = Double(numberPart) else { return nil }
                return SVGLength(CGFloat(d), unit: unit)
            }
        }
        guard let d = Double(trimmed) else { return nil }
        return SVGLength(CGFloat(d))
    }

    static func viewBox(_ s: String) -> CGRect? {
        guard let nums = numberList(s), nums.count == 4 else { return nil }
        return CGRect(x: nums[0], y: nums[1], width: nums[2], height: nums[3])
    }

    /// Parses the `points` attribute on `<polyline>` / `<polygon>` into x,y pairs.
    /// Trailing odd values are dropped to match permissive UA behavior.
    static func points(_ s: String) -> [CGPoint]? {
        guard let nums = numberList(s) else { return nil }
        let pairCount = nums.count / 2
        var out: [CGPoint] = []
        out.reserveCapacity(pairCount)
        for i in 0..<pairCount {
            out.append(CGPoint(x: nums[2 * i], y: nums[2 * i + 1]))
        }
        return out
    }

    /// Parses an SVG color value. Supports the named-color subset most tests
    /// need, plus #rgb/#rrggbb and rgb(r,g,b). Extends easily.
    static func color(_ raw: String) -> SVGPaint? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s == "none" { return SVGPaint.none }
        if s == "transparent" { return .color(SVGColor(red: 0, green: 0, blue: 0, alpha: 0)) }
        if let named = namedColors[s] { return .color(named) }
        if s.hasPrefix("#") {
            return hexColor(String(s.dropFirst())).map { .color($0) }
        }
        if s.hasPrefix("rgb(") && s.hasSuffix(")") {
            let inner = String(s.dropFirst(4).dropLast())
            let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 3,
                  let r = colorComponent(parts[0]),
                  let g = colorComponent(parts[1]),
                  let b = colorComponent(parts[2]) else { return nil }
            return .color(SVGColor(red: r, green: g, blue: b))
        }
        return nil
    }

    private static func colorComponent(_ s: String) -> CGFloat? {
        if s.hasSuffix("%") {
            guard let d = Double(s.dropLast()) else { return nil }
            return CGFloat(d / 100.0)
        }
        guard let d = Double(s) else { return nil }
        return CGFloat(d / 255.0)
    }

    private static func hexColor(_ hex: String) -> SVGColor? {
        func byte(_ s: Substring) -> CGFloat? {
            guard let v = UInt32(s, radix: 16) else { return nil }
            return CGFloat(v) / 255.0
        }
        switch hex.count {
        case 3:
            let chars = Array(hex)
            guard let r = byte(Substring("\(chars[0])\(chars[0])")),
                  let g = byte(Substring("\(chars[1])\(chars[1])")),
                  let b = byte(Substring("\(chars[2])\(chars[2])")) else { return nil }
            return SVGColor(red: r, green: g, blue: b)
        case 6:
            let i = hex.startIndex
            guard let r = byte(hex[i..<hex.index(i, offsetBy: 2)]),
                  let g = byte(hex[hex.index(i, offsetBy: 2)..<hex.index(i, offsetBy: 4)]),
                  let b = byte(hex[hex.index(i, offsetBy: 4)..<hex.index(i, offsetBy: 6)]) else { return nil }
            return SVGColor(red: r, green: g, blue: b)
        default:
            return nil
        }
    }

    /// Minimal named-color table. Expand alongside Phase 3.3 (painting).
    static let namedColors: [String: SVGColor] = [
        "black": SVGColor(red: 0, green: 0, blue: 0),
        "white": SVGColor(red: 1, green: 1, blue: 1),
        "red":   SVGColor(red: 1, green: 0, blue: 0),
        "lime":  SVGColor(red: 0, green: 1, blue: 0),
        "green": SVGColor(red: 0, green: 128.0/255, blue: 0),
        "blue":  SVGColor(red: 0, green: 0, blue: 1),
        "yellow":SVGColor(red: 1, green: 1, blue: 0),
        "cyan":  SVGColor(red: 0, green: 1, blue: 1),
        "aqua":  SVGColor(red: 0, green: 1, blue: 1),
        "magenta": SVGColor(red: 1, green: 0, blue: 1),
        "fuchsia": SVGColor(red: 1, green: 0, blue: 1),
        "gray":  SVGColor(red: 128.0/255, green: 128.0/255, blue: 128.0/255),
        "grey":  SVGColor(red: 128.0/255, green: 128.0/255, blue: 128.0/255),
        "silver":SVGColor(red: 192.0/255, green: 192.0/255, blue: 192.0/255),
        "maroon":SVGColor(red: 128.0/255, green: 0, blue: 0),
        "olive": SVGColor(red: 128.0/255, green: 128.0/255, blue: 0),
        "navy":  SVGColor(red: 0, green: 0, blue: 128.0/255),
        "purple":SVGColor(red: 128.0/255, green: 0, blue: 128.0/255),
        "teal":  SVGColor(red: 0, green: 128.0/255, blue: 128.0/255),
        "orange":SVGColor(red: 1, green: 165.0/255, blue: 0)
    ]

    /// Parses the SVG transform attribute. Handles the common functions used by
    /// the static suite: matrix, translate, scale, rotate, skewX, skewY.
    static func transform(_ raw: String) -> SVGTransform? {
        var result = CGAffineTransform.identity
        var scanner = TransformScanner(input: raw)
        while let fn = scanner.readFunction() {
            switch fn.name {
            case "matrix":
                guard fn.args.count == 6 else { return nil }
                let m = CGAffineTransform(
                    a: fn.args[0], b: fn.args[1],
                    c: fn.args[2], d: fn.args[3],
                    tx: fn.args[4], ty: fn.args[5]
                )
                result = m.concatenating(result)
            case "translate":
                let tx = fn.args.first ?? 0
                let ty = fn.args.count > 1 ? fn.args[1] : 0
                result = CGAffineTransform(translationX: tx, y: ty).concatenating(result)
            case "scale":
                let sx = fn.args.first ?? 1
                let sy = fn.args.count > 1 ? fn.args[1] : sx
                result = CGAffineTransform(scaleX: sx, y: sy).concatenating(result)
            case "rotate":
                guard let angle = fn.args.first else { return nil }
                let radians = angle * .pi / 180
                if fn.args.count == 3 {
                    let cx = fn.args[1], cy = fn.args[2]
                    var t = CGAffineTransform(translationX: cx, y: cy)
                    t = t.rotated(by: radians)
                    t = t.translatedBy(x: -cx, y: -cy)
                    result = t.concatenating(result)
                } else {
                    result = CGAffineTransform(rotationAngle: radians).concatenating(result)
                }
            case "skewx":
                guard let angle = fn.args.first else { return nil }
                let r = tan(angle * .pi / 180)
                result = CGAffineTransform(a: 1, b: 0, c: r, d: 1, tx: 0, ty: 0).concatenating(result)
            case "skewy":
                guard let angle = fn.args.first else { return nil }
                let r = tan(angle * .pi / 180)
                result = CGAffineTransform(a: 1, b: r, c: 0, d: 1, tx: 0, ty: 0).concatenating(result)
            default:
                return nil
            }
        }
        return SVGTransform(result)
    }
}

private struct TransformScanner {
    let input: String
    private var index: String.Index

    init(input: String) {
        self.input = input
        self.index = input.startIndex
    }

    struct Function { let name: String; let args: [CGFloat] }

    mutating func readFunction() -> Function? {
        skipWhitespaceAndCommas()
        guard index < input.endIndex else { return nil }

        let nameStart = index
        while index < input.endIndex, input[index].isLetter {
            index = input.index(after: index)
        }
        guard index > nameStart else { return nil }
        let name = input[nameStart..<index].lowercased()

        skipWhitespace()
        guard index < input.endIndex, input[index] == "(" else { return nil }
        index = input.index(after: index)

        var args: [CGFloat] = []
        while true {
            skipWhitespaceAndCommas()
            if index < input.endIndex, input[index] == ")" {
                index = input.index(after: index)
                break
            }
            guard let num = readNumber() else { return nil }
            args.append(num)
        }
        return Function(name: name, args: args)
    }

    private mutating func readNumber() -> CGFloat? {
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
        guard !slice.isEmpty, let d = Double(slice) else { return nil }
        return CGFloat(d)
    }

    private mutating func skipWhitespace() {
        while index < input.endIndex, input[index].isWhitespace {
            index = input.index(after: index)
        }
    }

    private mutating func skipWhitespaceAndCommas() {
        while index < input.endIndex, input[index].isWhitespace || input[index] == "," {
            index = input.index(after: index)
        }
    }
}
