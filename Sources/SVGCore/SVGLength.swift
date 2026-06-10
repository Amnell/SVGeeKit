import CoreGraphics
import Foundation

/// SVG length value with unit. Only px and unitless are honored today;
/// other units are parsed but coerced to px (good enough for the static subset).
public struct SVGLength: Equatable, Sendable {
    public enum Unit: String, Sendable, Equatable {
        case userSpace = ""
        case px, pt, pc, mm, cm, `in`
        case em, ex, percent
    }

    public var value: CGFloat
    public var unit: Unit

    public init(_ value: CGFloat, unit: Unit = .userSpace) {
        self.value = value
        self.unit = unit
    }

    /// Resolve to user-space units. Percentage handling deferred to renderer.
    public func resolved() -> CGFloat {
        switch unit {
        case .userSpace, .px: return value
        case .pt: return value * 1.3333333
        case .pc: return value * 16
        case .mm: return value * 3.7795275
        case .cm: return value * 37.795275
        case .in: return value * 96
        case .em, .ex, .percent: return value
        }
    }
}
