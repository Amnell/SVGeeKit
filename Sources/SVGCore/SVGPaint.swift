import CoreGraphics

/// sRGB color in 0...1 components.
public struct SVGColor: Equatable, Sendable {
    public var red: CGFloat
    public var green: CGFloat
    public var blue: CGFloat
    public var alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let black = SVGColor(red: 0, green: 0, blue: 0)
    public static let white = SVGColor(red: 1, green: 1, blue: 1)
}

/// Paint sources supported today. `paintServer` is a parse-time reference
/// to an `SVGDocument.paintServers` entry; lowering resolves it into a
/// concrete case (e.g. `.linearGradient`) before reaching the backend.
public enum SVGPaint: Equatable, Sendable {
    case none
    case color(SVGColor)
    case paintServer(id: String)
    case linearGradient(SVGLinearGradient)
    case radialGradient(SVGRadialGradient)
}

public enum SVGLineCap: String, Sendable, Equatable {
    case butt, round, square
}

public enum SVGLineJoin: String, Sendable, Equatable {
    case miter, round, bevel
}

public enum SVGFillRule: String, Sendable, Equatable {
    case nonzero, evenodd
}

public enum SVGVisibility: String, Sendable, Equatable {
    case visible, hidden, collapse
}

/// Painting properties shared by shapes. Mirrors the SVG painting chapter.
public struct SVGPaintProperties: Equatable, Sendable {
    public var fill: SVGPaint
    public var fillOpacity: CGFloat
    public var fillRule: SVGFillRule
    public var stroke: SVGPaint
    public var strokeOpacity: CGFloat
    public var strokeWidth: CGFloat
    public var lineCap: SVGLineCap
    public var lineJoin: SVGLineJoin
    public var miterLimit: CGFloat
    public var strokeDashArray: [CGFloat]
    public var strokeDashOffset: CGFloat
    public var opacity: CGFloat
    public var color: SVGColor
    public var visibility: SVGVisibility
    public var clipPathRef: String?
    public var maskRef: String?

    public init(
        fill: SVGPaint = .color(.black),
        fillOpacity: CGFloat = 1,
        fillRule: SVGFillRule = .nonzero,
        stroke: SVGPaint = .none,
        strokeOpacity: CGFloat = 1,
        strokeWidth: CGFloat = 1,
        lineCap: SVGLineCap = .butt,
        lineJoin: SVGLineJoin = .miter,
        miterLimit: CGFloat = 4,
        strokeDashArray: [CGFloat] = [],
        strokeDashOffset: CGFloat = 0,
        opacity: CGFloat = 1,
        color: SVGColor = .black,
        visibility: SVGVisibility = .visible,
        clipPathRef: String? = nil,
        maskRef: String? = nil
    ) {
        self.fill = fill
        self.fillOpacity = fillOpacity
        self.fillRule = fillRule
        self.stroke = stroke
        self.strokeOpacity = strokeOpacity
        self.strokeWidth = strokeWidth
        self.lineCap = lineCap
        self.lineJoin = lineJoin
        self.miterLimit = miterLimit
        self.strokeDashArray = strokeDashArray
        self.strokeDashOffset = strokeDashOffset
        self.opacity = opacity
        self.color = color
        self.visibility = visibility
        self.clipPathRef = clipPathRef
        self.maskRef = maskRef
    }
}
