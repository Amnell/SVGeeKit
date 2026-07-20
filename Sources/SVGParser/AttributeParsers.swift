import CoreGraphics
import Foundation
import SVGCore

/// Parsers for individual attribute values. All return nil for empty input.
enum AttributeParsers {

    /// Parses a whitespace/comma-separated list of numbers per SVG list grammar.
    /// Adjacent numbers may abut (e.g. `270-225` → `270`, `-225`).
    static func numberList(_ s: String) -> [CGFloat]? {
        var scanner = NumberListScanner(input: s)
        var out: [CGFloat] = []
        while let n = scanner.readNumber() {
            out.append(n)
        }
        guard !out.isEmpty else { return nil }
        scanner.skipWhitespaceAndCommas()
        guard scanner.isAtEnd else { return nil }
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

    /// CSS2 `clip` property: `auto` or `rect(top, right, bottom, left)`.
    static func cssClip(_ s: String) -> SVGCSSClip? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == "auto" { return .auto }
        guard trimmed.hasPrefix("rect("), trimmed.hasSuffix(")") else { return nil }
        let inner = String(trimmed.dropFirst(5).dropLast())
        guard let nums = numberList(inner), nums.count == 4 else { return nil }
        return .rect(top: nums[0], right: nums[1], bottom: nums[2], left: nums[3])
    }

    static func preserveAspectRatio(_ s: String) -> SVGPreserveAspectRatio? {
        let parts = s.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard let alignToken = parts.first else { return nil }
        let meetOrSlice: SVGPreserveAspectRatio.MeetOrSlice
        if parts.count > 1, parts[1].lowercased() == "slice" {
            meetOrSlice = .slice
        } else {
            meetOrSlice = .meet
        }
        let align: SVGPreserveAspectRatio.Align
        switch alignToken.lowercased() {
        case "none": align = .none
        case "xminymin": align = .xMinYMin
        case "xminymid": align = .xMinYMid
        case "xminymax": align = .xMinYMax
        case "xmidymin": align = .xMidYMin
        case "xmidymid": align = .xMidYMid
        case "xmidymax": align = .xMidYMax
        case "xmaxymin": align = .xMaxYMin
        case "xmaxymid": align = .xMaxYMid
        case "xmaxymax": align = .xMaxYMax
        default: return nil
        }
        return SVGPreserveAspectRatio(align: align, meetOrSlice: meetOrSlice)
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

    /// Parses a `unicode` attribute on `<glyph>` (literal, `&#…;`, or `&#x…;`).
    static func glyphUnicode(_ raw: String) -> Unicode.Scalar? {
        if raw.hasPrefix("&#x") || raw.hasPrefix("&#X") {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let body = trimmed.dropFirst(3)
            guard body.hasSuffix(";") else { return nil }
            let hex = body.dropLast()
            guard let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) else {
                return nil
            }
            return scalar
        }
        if raw.hasPrefix("&#") {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let body = trimmed.dropFirst(2)
            guard body.hasSuffix(";") else { return nil }
            let digits = body.dropLast()
            guard let value = UInt32(digits), let scalar = Unicode.Scalar(value) else {
                return nil
            }
            return scalar
        }
        // Literal glyph, including `unicode=" "` — must not trim whitespace away.
        guard raw.count == 1, let scalar = raw.unicodeScalars.first else { return nil }
        return scalar
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

    /// Full SVG 1.1 named-color table (X11 / CSS color keywords) plus the 28
    /// CSS2 system-color keywords (SVG 1.1 §4.2). System colors are mapped to
    /// platform-neutral fallbacks; exact values are UA-defined and the W3C test
    /// pass criteria only requires legible, UI-resembling colors — not a pixel match.
    static let namedColors: [String: SVGColor] = {
        let rgb: [(String, Int, Int, Int)] = [
            // CSS2 system colors
            ("activeborder",       212, 208, 200),
            ("activecaption",       10,  36, 106),
            ("appworkspace",       128, 128, 128),
            ("background",         58,  110, 165),
            ("buttonface",         212, 208, 200),
            ("buttonhighlight",    255, 255, 255),
            ("buttonshadow",       128, 128, 128),
            ("buttontext",           0,   0,   0),
            ("captiontext",        255, 255, 255),
            ("graytext",           128, 128, 128),
            ("greytext",           128, 128, 128),
            ("highlight",           10,  36, 106),
            ("highlighttext",      255, 255, 255),
            ("inactiveborder",     212, 208, 200),
            ("inactivecaption",    128, 128, 128),
            ("inactivecaptiontext",212, 208, 200),
            ("infobackground",     255, 255, 225),
            ("infotext",             0,   0,   0),
            ("menu",               212, 208, 200),
            ("menutext",             0,   0,   0),
            ("scrollbar",          212, 208, 200),
            ("threeddarkshadow",    64,  64,  64),
            ("threedface",         212, 208, 200),
            ("threedhighlight",    255, 255, 255),
            ("threedlightshadow",  212, 208, 200),
            ("threedshadow",       128, 128, 128),
            ("window",             255, 255, 255),
            ("windowframe",          0,   0,   0),
            ("windowtext",           0,   0,   0),
        ]
        var table: [String: SVGColor] = [:]
        table.reserveCapacity(rgb.count)
        for (name, r, g, b) in rgb {
            table[name] = SVGColor(
                red: CGFloat(r) / 255,
                green: CGFloat(g) / 255,
                blue: CGFloat(b) / 255
            )
        }

        let x11rgb: [(String, Int, Int, Int)] = [
            ("aliceblue", 240, 248, 255),
            ("antiquewhite", 250, 235, 215),
            ("aqua", 0, 255, 255),
            ("aquamarine", 127, 255, 212),
            ("azure", 240, 255, 255),
            ("beige", 245, 245, 220),
            ("bisque", 255, 228, 196),
            ("black", 0, 0, 0),
            ("blanchedalmond", 255, 235, 205),
            ("blue", 0, 0, 255),
            ("blueviolet", 138, 43, 226),
            ("brown", 165, 42, 42),
            ("burlywood", 222, 184, 135),
            ("cadetblue", 95, 158, 160),
            ("chartreuse", 127, 255, 0),
            ("chocolate", 210, 105, 30),
            ("coral", 255, 127, 80),
            ("cornflowerblue", 100, 149, 237),
            ("cornsilk", 255, 248, 220),
            ("crimson", 220, 20, 60),
            ("cyan", 0, 255, 255),
            ("darkblue", 0, 0, 139),
            ("darkcyan", 0, 139, 139),
            ("darkgoldenrod", 184, 134, 11),
            ("darkgray", 169, 169, 169),
            ("darkgreen", 0, 100, 0),
            ("darkgrey", 169, 169, 169),
            ("darkkhaki", 189, 183, 107),
            ("darkmagenta", 139, 0, 139),
            ("darkolivegreen", 85, 107, 47),
            ("darkorange", 255, 140, 0),
            ("darkorchid", 153, 50, 204),
            ("darkred", 139, 0, 0),
            ("darksalmon", 233, 150, 122),
            ("darkseagreen", 143, 188, 143),
            ("darkslateblue", 72, 61, 139),
            ("darkslategray", 47, 79, 79),
            ("darkslategrey", 47, 79, 79),
            ("darkturquoise", 0, 206, 209),
            ("darkviolet", 148, 0, 211),
            ("deeppink", 255, 20, 147),
            ("deepskyblue", 0, 191, 255),
            ("dimgray", 105, 105, 105),
            ("dimgrey", 105, 105, 105),
            ("dodgerblue", 30, 144, 255),
            ("firebrick", 178, 34, 34),
            ("floralwhite", 255, 250, 240),
            ("forestgreen", 34, 139, 34),
            ("fuchsia", 255, 0, 255),
            ("gainsboro", 220, 220, 220),
            ("ghostwhite", 248, 248, 255),
            ("gold", 255, 215, 0),
            ("goldenrod", 218, 165, 32),
            ("gray", 128, 128, 128),
            ("green", 0, 128, 0),
            ("greenyellow", 173, 255, 47),
            ("grey", 128, 128, 128),
            ("honeydew", 240, 255, 240),
            ("hotpink", 255, 105, 180),
            ("indianred", 205, 92, 92),
            ("indigo", 75, 0, 130),
            ("ivory", 255, 255, 240),
            ("khaki", 240, 230, 140),
            ("lavender", 230, 230, 250),
            ("lavenderblush", 255, 240, 245),
            ("lawngreen", 124, 252, 0),
            ("lemonchiffon", 255, 250, 205),
            ("lightblue", 173, 216, 230),
            ("lightcoral", 240, 128, 128),
            ("lightcyan", 224, 255, 255),
            ("lightgoldenrodyellow", 250, 250, 210),
            ("lightgray", 211, 211, 211),
            ("lightgreen", 144, 238, 144),
            ("lightgrey", 211, 211, 211),
            ("lightpink", 255, 182, 193),
            ("lightsalmon", 255, 160, 122),
            ("lightseagreen", 32, 178, 170),
            ("lightskyblue", 135, 206, 250),
            ("lightslategray", 119, 136, 153),
            ("lightslategrey", 119, 136, 153),
            ("lightsteelblue", 176, 196, 222),
            ("lightyellow", 255, 255, 224),
            ("lime", 0, 255, 0),
            ("limegreen", 50, 205, 50),
            ("linen", 250, 240, 230),
            ("magenta", 255, 0, 255),
            ("maroon", 128, 0, 0),
            ("mediumaquamarine", 102, 205, 170),
            ("mediumblue", 0, 0, 205),
            ("mediumorchid", 186, 85, 211),
            ("mediumpurple", 147, 112, 219),
            ("mediumseagreen", 60, 179, 113),
            ("mediumslateblue", 123, 104, 238),
            ("mediumspringgreen", 0, 250, 154),
            ("mediumturquoise", 72, 209, 204),
            ("mediumvioletred", 199, 21, 133),
            ("midnightblue", 25, 25, 112),
            ("mintcream", 245, 255, 250),
            ("mistyrose", 255, 228, 225),
            ("moccasin", 255, 228, 181),
            ("navajowhite", 255, 222, 173),
            ("navy", 0, 0, 128),
            ("oldlace", 253, 245, 230),
            ("olive", 128, 128, 0),
            ("olivedrab", 107, 142, 35),
            ("orange", 255, 165, 0),
            ("orangered", 255, 69, 0),
            ("orchid", 218, 112, 214),
            ("palegoldenrod", 238, 232, 170),
            ("palegreen", 152, 251, 152),
            ("paleturquoise", 175, 238, 238),
            ("palevioletred", 219, 112, 147),
            ("papayawhip", 255, 239, 213),
            ("peachpuff", 255, 218, 185),
            ("peru", 205, 133, 63),
            ("pink", 255, 192, 203),
            ("plum", 221, 160, 221),
            ("powderblue", 176, 224, 230),
            ("purple", 128, 0, 128),
            ("red", 255, 0, 0),
            ("rosybrown", 188, 143, 143),
            ("royalblue", 65, 105, 225),
            ("saddlebrown", 139, 69, 19),
            ("salmon", 250, 128, 114),
            ("sandybrown", 244, 164, 96),
            ("seagreen", 46, 139, 87),
            ("seashell", 255, 245, 238),
            ("sienna", 160, 82, 45),
            ("silver", 192, 192, 192),
            ("skyblue", 135, 206, 235),
            ("slateblue", 106, 90, 205),
            ("slategray", 112, 128, 144),
            ("slategrey", 112, 128, 144),
            ("snow", 255, 250, 250),
            ("springgreen", 0, 255, 127),
            ("steelblue", 70, 130, 180),
            ("tan", 210, 180, 140),
            ("teal", 0, 128, 128),
            ("thistle", 216, 191, 216),
            ("tomato", 255, 99, 71),
            ("turquoise", 64, 224, 208),
            ("violet", 238, 130, 238),
            ("wheat", 245, 222, 179),
            ("white", 255, 255, 255),
            ("whitesmoke", 245, 245, 245),
            ("yellow", 255, 255, 0),
            ("yellowgreen", 154, 205, 50)
        ]
        for (name, r, g, b) in x11rgb {
            table[name] = SVGColor(
                red: CGFloat(r) / 255,
                green: CGFloat(g) / 255,
                blue: CGFloat(b) / 255
            )
        }
        return table
    }()

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

/// Scanner for SVG list-of-numbers attributes (`points`, `viewBox`, …).
private struct NumberListScanner {
    private let bytes: [UInt8]
    private var index: Int

    init(input: String) {
        self.bytes = Array(input.utf8)
        self.index = bytes.startIndex
    }

    var isAtEnd: Bool {
        var i = index
        while i < bytes.endIndex, isWhitespaceOrComma(bytes[i]) {
            i += 1
        }
        return i >= bytes.endIndex
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

    private func isDigit(_ byte: UInt8) -> Bool {
        byte >= 48 && byte <= 57
    }

    private func isWhitespaceOrComma(_ byte: UInt8) -> Bool {
        byte == 44 || byte == 32 || byte == 9 || byte == 10 || byte == 13 || byte == 12
    }
}
