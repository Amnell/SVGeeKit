import CoreGraphics
import Foundation

/// Aligns axis-aligned, integer-coordinate paths so odd-width strokes land on the
/// device pixel grid. Without this, Core Graphics anti-aliases 1px rect outlines
/// into gray half-pixel coverage (shapes-intro-01-t container boxes).
enum HairlineStrokeAlignment {
    static func alignedPathForStroke(_ path: CGPath, lineWidth: CGFloat) -> CGPath {
        let offset = CGFloat(Int(lineWidth.rounded(.down)) % 2) * 0.5
        guard offset > 0, pathIsAxisAlignedIntegerGrid(path) else { return path }

        // Only snap closed outlines (rect/polygon). Open polylines and lines keep
        // their authored coordinates so marker lines stay aligned with filled
        // geometry (types-basic-01-f grey rules at y=75/125).
        guard pathIsClosed(path) else { return path }

        var transform = CGAffineTransform(translationX: offset, y: offset)
        return path.copy(using: &transform) ?? path
    }

    private static func pathIsClosed(_ path: CGPath) -> Bool {
        var closed = false
        path.applyWithBlock { elementPtr in
            if elementPtr.pointee.type == .closeSubpath {
                closed = true
            }
        }
        return closed
    }

    private static func pathIsAxisAlignedIntegerGrid(_ path: CGPath) -> Bool {
        guard !path.isEmpty else { return false }

        var subpathStart: CGPoint?
        var previous: CGPoint?
        var valid = true

        func isInteger(_ value: CGFloat) -> Bool {
            abs(value - value.rounded()) <= 1e-4
        }

        func checkPoint(_ point: CGPoint) {
            if !isInteger(point.x) || !isInteger(point.y) {
                valid = false
            }
        }

        func checkSegment(to point: CGPoint) {
            guard let from = previous else { return }
            if from.x != point.x && from.y != point.y {
                valid = false
            }
        }

        path.applyWithBlock { elementPtr in
            guard valid else { return }
            let element = elementPtr.pointee
            switch element.type {
            case .moveToPoint:
                let point = element.points[0]
                checkPoint(point)
                subpathStart = point
                previous = point
            case .addLineToPoint:
                let point = element.points[0]
                checkPoint(point)
                checkSegment(to: point)
                previous = point
            case .closeSubpath:
                if let start = subpathStart {
                    checkSegment(to: start)
                    previous = start
                }
            default:
                valid = false
            }
        }

        return valid
    }
}
