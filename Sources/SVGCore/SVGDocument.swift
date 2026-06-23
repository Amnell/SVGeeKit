import CoreGraphics
import Foundation

/// A parsed SVG document. Pure value type; no I/O, no rendering.
public struct SVGDocument: Equatable, Sendable {
    public var viewBox: CGRect?
    public var intrinsicSize: CGSize?
    /// Directory containing the parsed SVG file, used to resolve relative
    /// `xlink:href` / `href` values (e.g. external SVG fonts in Phase 2).
    public var baseURL: URL?
    public var root: SVGGroup
    public var paintServers: [String: SVGPaintServer]
    public var clipPaths: [String: SVGClipPath]
    public var masks: [String: SVGMask]
    /// CSS `<font-face>` family → font id bindings.
    public var fontFaces: [SVGFontFace]
    /// SVG `<font id="…">` tables keyed by id.
    public var fonts: [String: SVGFontDefinition]

    public init(
        viewBox: CGRect? = nil,
        intrinsicSize: CGSize? = nil,
        baseURL: URL? = nil,
        root: SVGGroup = SVGGroup(),
        paintServers: [String: SVGPaintServer] = [:],
        clipPaths: [String: SVGClipPath] = [:],
        masks: [String: SVGMask] = [:],
        fontFaces: [SVGFontFace] = [],
        fonts: [String: SVGFontDefinition] = [:]
    ) {
        self.viewBox = viewBox
        self.intrinsicSize = intrinsicSize
        self.baseURL = baseURL
        self.root = root
        self.paintServers = paintServers
        self.clipPaths = clipPaths
        self.masks = masks
        self.fontFaces = fontFaces
        self.fonts = fonts
    }

    /// Resolve `href` against `baseURL`. Absolute URLs are returned unchanged;
    /// fragment identifiers are preserved.
    public func resolveURL(_ href: String) -> URL? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute
        }
        guard let baseURL else { return URL(string: trimmed) }
        let (pathPart, fragment) = Self.splitHrefFragment(trimmed)
        guard var resolved = URL(string: pathPart, relativeTo: baseURL)?.standardizedFileURL else {
            return nil
        }
        if let fragment {
            var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false)
            components?.fragment = fragment
            resolved = components?.url ?? resolved
        }
        return resolved
    }

    private static func splitHrefFragment(_ href: String) -> (String, String?) {
        guard let hash = href.firstIndex(of: "#") else { return (href, nil) }
        let pathPart = String(href[..<hash])
        let fragment = String(href[href.index(after: hash)...])
        return (pathPart, fragment.isEmpty ? nil : fragment)
    }
}

/// A grouping container. Used for the implicit root and for `<g>`.
public struct SVGGroup: Equatable, Sendable {
    public var transform: SVGTransform
    /// Group-level opacity (`opacity` presentation attribute on `<g>`).
    /// Children are composited as a unit before this opacity is applied,
    /// so overlapping children don't show through each other.
    public var opacity: CGFloat
    public var clipPathRef: String?
    public var maskRef: String?
    public var children: [SVGElement]

    public init(
        transform: SVGTransform = .identity,
        opacity: CGFloat = 1,
        clipPathRef: String? = nil,
        maskRef: String? = nil,
        children: [SVGElement] = []
    ) {
        self.transform = transform
        self.opacity = opacity
        self.clipPathRef = clipPathRef
        self.maskRef = maskRef
        self.children = children
    }
}

/// A clipping path definition (`<clipPath>`). Children describe the clip region.
public struct SVGClipPath: Equatable, Sendable {
    public enum Units: String, Equatable, Sendable {
        case userSpaceOnUse
        case objectBoundingBox
    }
    public var units: Units
    public var transform: SVGTransform
    public var children: [SVGElement]

    public init(
        units: Units = .userSpaceOnUse,
        transform: SVGTransform = .identity,
        children: [SVGElement] = []
    ) {
        self.units = units
        self.transform = transform
        self.children = children
    }
}

/// An alpha mask definition (`<mask>`). Children define the mask image.
/// An empty mask (no children) suppresses rendering of the referencing element.
public struct SVGMask: Equatable, Sendable {
    public enum Units: String, Equatable, Sendable {
        case userSpaceOnUse
        case objectBoundingBox
    }

    /// Coordinate system for the `x`/`y`/`width`/`height` region. Per SVG 1.1
    /// the default is `objectBoundingBox`.
    public var maskUnits: Units
    /// Coordinate system for the mask's content.
    public var maskContentUnits: Units
    /// Mask region in the units given by `maskUnits`. `nil` means the SVG 1.1
    /// default (`-10%`, `-10%`, `120%`, `120%` of the bounding box).
    public var x: CGFloat?
    public var y: CGFloat?
    public var width: CGFloat?
    public var height: CGFloat?
    public var children: [SVGElement]

    public init(
        maskUnits: Units = .objectBoundingBox,
        maskContentUnits: Units = .userSpaceOnUse,
        x: CGFloat? = nil,
        y: CGFloat? = nil,
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        children: [SVGElement] = []
    ) {
        self.maskUnits = maskUnits
        self.maskContentUnits = maskContentUnits
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.children = children
    }
}

/// Discriminated union of SVG elements supported by the model.
/// Add new cases here as features land in Phase 3.
public enum SVGElement: Equatable, Sendable {
    case group(SVGGroup)
    case rect(SVGRect)
    case circle(SVGCircle)
    case ellipse(SVGEllipse)
    case line(SVGLine)
    case polyline(SVGPolyline)
    case polygon(SVGPolygon)
    case path(SVGPath)
    case text(SVGText)
}

/// Normalized path-data segments. The parser resolves `d=` (relative,
/// shorthand, arc commands) into this absolute-coordinate form.
public enum SVGPathCommand: Equatable, Sendable {
    case moveTo(CGPoint)
    case lineTo(CGPoint)
    case quadTo(control: CGPoint, end: CGPoint)
    case cubicTo(control1: CGPoint, control2: CGPoint, end: CGPoint)
    case close
}

public struct SVGPath: Equatable, Sendable {
    public var commands: [SVGPathCommand]
    public var paint: SVGPaintProperties
    public var transform: SVGTransform

    public init(
        commands: [SVGPathCommand],
        paint: SVGPaintProperties = .init(),
        transform: SVGTransform = .identity
    ) {
        self.commands = commands
        self.paint = paint
        self.transform = transform
    }
}

public struct SVGRect: Equatable, Sendable {
    public var origin: CGPoint
    public var size: CGSize
    public var cornerRadii: CGSize
    public var paint: SVGPaintProperties
    public var transform: SVGTransform

    public init(
        origin: CGPoint,
        size: CGSize,
        cornerRadii: CGSize = .zero,
        paint: SVGPaintProperties = .init(),
        transform: SVGTransform = .identity
    ) {
        self.origin = origin
        self.size = size
        self.cornerRadii = cornerRadii
        self.paint = paint
        self.transform = transform
    }
}

public struct SVGCircle: Equatable, Sendable {
    public var center: CGPoint
    public var radius: CGFloat
    public var paint: SVGPaintProperties
    public var transform: SVGTransform

    public init(
        center: CGPoint,
        radius: CGFloat,
        paint: SVGPaintProperties = .init(),
        transform: SVGTransform = .identity
    ) {
        self.center = center
        self.radius = radius
        self.paint = paint
        self.transform = transform
    }
}

public struct SVGEllipse: Equatable, Sendable {
    public var center: CGPoint
    public var radii: CGSize
    public var paint: SVGPaintProperties
    public var transform: SVGTransform

    public init(
        center: CGPoint,
        radii: CGSize,
        paint: SVGPaintProperties = .init(),
        transform: SVGTransform = .identity
    ) {
        self.center = center
        self.radii = radii
        self.paint = paint
        self.transform = transform
    }
}

public struct SVGLine: Equatable, Sendable {
    public var start: CGPoint
    public var end: CGPoint
    public var paint: SVGPaintProperties
    public var transform: SVGTransform

    public init(
        start: CGPoint,
        end: CGPoint,
        paint: SVGPaintProperties = .init(),
        transform: SVGTransform = .identity
    ) {
        self.start = start
        self.end = end
        self.paint = paint
        self.transform = transform
    }
}

public struct SVGPolyline: Equatable, Sendable {
    public var points: [CGPoint]
    public var paint: SVGPaintProperties
    public var transform: SVGTransform

    public init(
        points: [CGPoint],
        paint: SVGPaintProperties = .init(),
        transform: SVGTransform = .identity
    ) {
        self.points = points
        self.paint = paint
        self.transform = transform
    }
}

public struct SVGPolygon: Equatable, Sendable {
    public var points: [CGPoint]
    public var paint: SVGPaintProperties
    public var transform: SVGTransform

    public init(
        points: [CGPoint],
        paint: SVGPaintProperties = .init(),
        transform: SVGTransform = .identity
    ) {
        self.points = points
        self.paint = paint
        self.transform = transform
    }
}

public enum SVGTextAnchor: String, Sendable, Equatable {
    case start, middle, end
}

public enum SVGFontWeight: Sendable, Equatable, Hashable {
    case normal
    case bold
    case numeric(Int)

    public static func parse(_ raw: String) -> SVGFontWeight? {
        switch raw.lowercased() {
        case "normal": return .normal
        case "bold": return .bold
        default:
            if let n = Int(raw) { return .numeric(n) }
            return nil
        }
    }
}

/// Text presentation properties inherited through the element tree.
public struct SVGFont: Equatable, Sendable {
    /// Comma-separated font-family list as authored in SVG (e.g. "Arial, sans-serif").
    public var family: String?
    public var size: CGFloat
    public var weight: SVGFontWeight
    public var anchor: SVGTextAnchor

    public init(
        family: String? = nil,
        size: CGFloat = 16,
        weight: SVGFontWeight = .normal,
        anchor: SVGTextAnchor = .start
    ) {
        self.family = family
        self.size = size
        self.weight = weight
        self.anchor = anchor
    }
}

public struct SVGText: Equatable, Sendable {
    public var origin: CGPoint
    public var string: String
    public var font: SVGFont
    public var paint: SVGPaintProperties
    public var transform: SVGTransform

    public init(
        origin: CGPoint,
        string: String,
        font: SVGFont = SVGFont(),
        paint: SVGPaintProperties = .init(),
        transform: SVGTransform = .identity
    ) {
        self.origin = origin
        self.string = string
        self.font = font
        self.paint = paint
        self.transform = transform
    }
}
