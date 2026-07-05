import Foundation

// MARK: - Timing

public enum SVGClockValue {
    /// Parses an SVG clock value (`0s`, `500ms`, `2min`, bare number) into seconds.
    public static func parseSeconds(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == "indefinite" { return nil }
        if trimmed.hasSuffix("ms") {
            let num = trimmed.dropLast(2)
            guard let ms = Double(num) else { return nil }
            return ms / 1000
        }
        if trimmed.hasSuffix("min") {
            let num = trimmed.dropLast(3)
            guard let minutes = Double(num) else { return nil }
            return minutes * 60
        }
        if trimmed.hasSuffix("h") {
            let num = trimmed.dropLast()
            guard let hours = Double(num) else { return nil }
            return hours * 3600
        }
        if trimmed.hasSuffix("s") {
            let num = trimmed.dropLast()
            return Double(num)
        }
        return Double(trimmed)
    }
}

public enum SVGTimingFill: String, Equatable, Sendable, Codable {
    case remove
    case freeze
}

public enum SVGCalcMode: String, Equatable, Sendable, Codable {
    case discrete
    case linear
    case paced
    case spline
}

public struct SVGTimingAttributes: Equatable, Sendable, Codable {
    /// Raw `begin` attribute (clock values, syncbases, or event specs).
    public var begin: String?
    public var dur: Double?
    public var end: String?
    /// Raw `repeatCount` (`indefinite` or a number string).
    public var repeatCount: String?
    public var fill: SVGTimingFill

    public init(
        begin: String? = nil,
        dur: Double? = nil,
        end: String? = nil,
        repeatCount: String? = nil,
        fill: SVGTimingFill = .remove
    ) {
        self.begin = begin
        self.dur = dur
        self.end = end
        self.repeatCount = repeatCount
        self.fill = fill
    }
}

// MARK: - Animation elements

public struct SVGAnimateElement: Equatable, Sendable, Codable {
    public var id: String?
    public var timing: SVGTimingAttributes
    public var attributeName: String
    public var attributeType: String?
    /// Fragment id (`#rect1`) of the element to animate; nil targets the animation parent.
    public var targetHref: String?
    public var from: String?
    public var to: String?
    public var values: String?
    public var calcMode: SVGCalcMode?
    public var additive: String?
    public var accumulate: String?

    public init(
        id: String? = nil,
        timing: SVGTimingAttributes = SVGTimingAttributes(),
        attributeName: String,
        attributeType: String? = nil,
        targetHref: String? = nil,
        from: String? = nil,
        to: String? = nil,
        values: String? = nil,
        calcMode: SVGCalcMode? = nil,
        additive: String? = nil,
        accumulate: String? = nil
    ) {
        self.id = id
        self.timing = timing
        self.attributeName = attributeName
        self.attributeType = attributeType
        self.targetHref = targetHref
        self.from = from
        self.to = to
        self.values = values
        self.calcMode = calcMode
        self.additive = additive
        self.accumulate = accumulate
    }
}

public struct SVGSetElement: Equatable, Sendable, Codable {
    public var id: String?
    public var timing: SVGTimingAttributes
    public var attributeName: String
    /// Fragment id of the element to animate; nil targets the animation parent.
    public var targetHref: String?
    public var to: String

    public init(
        id: String? = nil,
        timing: SVGTimingAttributes = SVGTimingAttributes(),
        attributeName: String,
        targetHref: String? = nil,
        to: String
    ) {
        self.id = id
        self.timing = timing
        self.attributeName = attributeName
        self.targetHref = targetHref
        self.to = to
    }
}

public enum SVGAnimateTransformType: String, Equatable, Sendable, Codable {
    case translate
    case scale
    case rotate
    case skewX
    case skewY
}

public struct SVGAnimateTransformElement: Equatable, Sendable, Codable {
    public var id: String?
    public var timing: SVGTimingAttributes
    public var type: SVGAnimateTransformType
    public var from: String?
    public var to: String?
    public var values: String?
    public var additive: String?
    public var accumulate: String?

    public init(
        id: String? = nil,
        timing: SVGTimingAttributes = SVGTimingAttributes(),
        type: SVGAnimateTransformType,
        from: String? = nil,
        to: String? = nil,
        values: String? = nil,
        additive: String? = nil,
        accumulate: String? = nil
    ) {
        self.id = id
        self.timing = timing
        self.type = type
        self.from = from
        self.to = to
        self.values = values
        self.additive = additive
        self.accumulate = accumulate
    }
}

public struct SVGAnimateMotionElement: Equatable, Sendable, Codable {
    public var id: String?
    public var timing: SVGTimingAttributes
    public var path: String?
    public var from: String?
    public var to: String?
    public var values: String?
    public var rotate: String?
    public var mpathHref: String?

    public init(
        id: String? = nil,
        timing: SVGTimingAttributes = SVGTimingAttributes(),
        path: String? = nil,
        from: String? = nil,
        to: String? = nil,
        values: String? = nil,
        rotate: String? = nil,
        mpathHref: String? = nil
    ) {
        self.id = id
        self.timing = timing
        self.path = path
        self.from = from
        self.to = to
        self.values = values
        self.rotate = rotate
        self.mpathHref = mpathHref
    }
}

public enum SVGTimedAnimation: Equatable, Sendable, Codable {
    case animate(SVGAnimateElement)
    case set(SVGSetElement)
    case animateTransform(SVGAnimateTransformElement)
    case animateMotion(SVGAnimateMotionElement)

    public var id: String? {
        switch self {
        case .animate(let element): element.id
        case .set(let element): element.id
        case .animateTransform(let element): element.id
        case .animateMotion(let element): element.id
        }
    }

    public var timing: SVGTimingAttributes {
        switch self {
        case .animate(let element): element.timing
        case .set(let element): element.timing
        case .animateTransform(let element): element.timing
        case .animateMotion(let element): element.timing
        }
    }

    /// Fragment id from `xlink:href` / `href`, when the animation targets another element.
    public var targetHref: String? {
        switch self {
        case .animate(let element): element.targetHref
        case .set(let element): element.targetHref
        case .animateTransform, .animateMotion: nil
        }
    }
}

/// Animations attached to the document root (siblings of the render tree).
public struct SVGAnimationMetadata: Equatable, Sendable, Codable {
    public var rootAnimations: [SVGTimedAnimation]
    /// Animation `id` → index in `rootAnimations` (syncbase resolution).
    public var index: [String: Int]

    public init(
        rootAnimations: [SVGTimedAnimation] = [],
        index: [String: Int] = [:]
    ) {
        self.rootAnimations = rootAnimations
        self.index = index
    }
}

/// Protocol-style accessor for elements that carry SMIL children.
public protocol SVGAnimationCarrier {
    var animations: [SVGTimedAnimation] { get set }
}

extension SVGGroup: SVGAnimationCarrier {}
extension SVGRect: SVGAnimationCarrier {}
extension SVGCircle: SVGAnimationCarrier {}
extension SVGEllipse: SVGAnimationCarrier {}
extension SVGLine: SVGAnimationCarrier {}
extension SVGPolyline: SVGAnimationCarrier {}
extension SVGPolygon: SVGAnimationCarrier {}
extension SVGPath: SVGAnimationCarrier {}
extension SVGText: SVGAnimationCarrier {}
extension SVGUse: SVGAnimationCarrier {}

extension SVGElement {
    public var animations: [SVGTimedAnimation] {
        get {
            switch self {
            case .group(let group): group.animations
            case .svg: []
            case .rect(let rect): rect.animations
            case .circle(let circle): circle.animations
            case .ellipse(let ellipse): ellipse.animations
            case .line(let line): line.animations
            case .polyline(let polyline): polyline.animations
            case .polygon(let polygon): polygon.animations
            case .path(let path): path.animations
            case .text(let text): text.animations
            case .use(let use): use.animations
            }
        }
        set {
            switch self {
            case .group(var group):
                group.animations = newValue
                self = .group(group)
            case .svg:
                break
            case .rect(var rect):
                rect.animations = newValue
                self = .rect(rect)
            case .circle(var circle):
                circle.animations = newValue
                self = .circle(circle)
            case .ellipse(var ellipse):
                ellipse.animations = newValue
                self = .ellipse(ellipse)
            case .line(var line):
                line.animations = newValue
                self = .line(line)
            case .polyline(var polyline):
                polyline.animations = newValue
                self = .polyline(polyline)
            case .polygon(var polygon):
                polygon.animations = newValue
                self = .polygon(polygon)
            case .path(var path):
                path.animations = newValue
                self = .path(path)
            case .text(var text):
                text.animations = newValue
                self = .text(text)
            case .use(var use):
                use.animations = newValue
                self = .use(use)
            }
        }
    }

    public mutating func setAnimations(_ animations: [SVGTimedAnimation]) {
        self.animations = animations
    }
}
