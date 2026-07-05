import SwiftUI

/// How an `SVGImageView` scales its document into the available layout space.
///
/// Mirrors the sizing behavior of `Image` with `scaledToFit()` / `scaledToFill()`.
public enum SVGImageContentMode: String, Equatable, Sendable, CaseIterable, Identifiable {
    /// Uniform scale so the entire SVG is visible (letterboxing as needed).
    case fit
    /// Uniform scale so the SVG fills the frame (cropping as needed).
    case fill
    /// Independent horizontal and vertical scale to exactly match the frame.
    case stretch

    public var id: Self { self }

    public var label: String {
        switch self {
        case .fit: return "Fit"
        case .fill: return "Fill"
        case .stretch: return "Stretch"
        }
    }

    var swiftUIContentMode: ContentMode {
        switch self {
        case .fit: return .fit
        case .fill: return .fill
        case .stretch: return .fit
        }
    }
}
