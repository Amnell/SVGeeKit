import CoreGraphics
import SVGCore

public struct SVGHitResult: Equatable, Sendable {
  public var path: SVGElementPath
  public var element: SVGElement

  public init(path: SVGElementPath, element: SVGElement) {
    self.path = path
    self.element = element
  }
}

/// Backend-neutral hit testing against the SVG element tree.
public enum SVGHitTester {

  public static func hitTest(document: SVGDocument, at point: CGPoint) -> SVGHitResult? {
    testGroup(
      document.root,
      pathPrefix: [],
      transform: .identity,
      point: point
    )
  }

  /// Walk from the hit target up the tree to find an element id with a handler.
  public static func handlerOwnerPath(
    hitPath: SVGElementPath,
    document: SVGDocument,
    event: String
  ) -> (path: SVGElementPath, handler: SVGEventHandler)? {
    var path = hitPath
    while true {
      if let id = elementID(at: path, document: document),
         let handlers = document.scriptMetadata.handlersByElementID[id],
         let handler = handlers.first(where: { $0.event == event }) {
        return (path, handler)
      }
      guard !path.indices.isEmpty else { break }
      path = SVGElementPath(indices: Array(path.indices.dropLast()))
    }
    return nil
  }

  private static func elementID(at path: SVGElementPath, document: SVGDocument) -> String? {
    guard let element = document.element(at: path) else { return nil }
    if case .group(let group) = element {
      return group.id
    }
    return nil
  }

  private static func testGroup(
    _ group: SVGGroup,
    pathPrefix: [Int],
    transform: CGAffineTransform,
    point: CGPoint
  ) -> SVGHitResult? {
    guard group.visibility == .visible else { return nil }
    let local = transform.concatenating(group.transform.matrix)
    // Paint order: last child is topmost — test front-to-back and return the first hit.
    for (index, child) in group.children.enumerated().reversed() {
      if let hit = testElement(
        child,
        path: SVGElementPath(indices: pathPrefix + [index]),
        transform: local,
        point: point
      ) {
        return hit
      }
    }
    return nil
  }

  private static func testSVGElement(
    _ svg: SVGSVGElement,
    pathPrefix: [Int],
    transform: CGAffineTransform,
    point: CGPoint
  ) -> SVGHitResult? {
    var local = transform
    if svg.origin != .zero {
      local = local.concatenating(CGAffineTransform(translationX: svg.origin.x, y: svg.origin.y))
    }
    if let vb = svg.viewBox, svg.size.width > 0, svg.size.height > 0, vb.width > 0, vb.height > 0 {
      let sx = svg.size.width / vb.width
      let sy = svg.size.height / vb.height
      var t = CGAffineTransform(scaleX: sx, y: sy)
      t = t.translatedBy(x: -vb.origin.x, y: -vb.origin.y)
      local = local.concatenating(t)
    }
    for (index, child) in svg.children.enumerated().reversed() {
      if let hit = testElement(
        child,
        path: SVGElementPath(indices: pathPrefix + [index]),
        transform: local,
        point: point
      ) {
        return hit
      }
    }
    return nil
  }

  private static func testElement(
    _ element: SVGElement,
    path: SVGElementPath,
    transform: CGAffineTransform,
    point: CGPoint
  ) -> SVGHitResult? {
    switch element {
    case .group(let group):
      return testGroup(group, pathPrefix: path.indices, transform: transform, point: point)
    case .svg(let svg):
      return testSVGElement(svg, pathPrefix: path.indices, transform: transform, point: point)
    case .rect(let rect):
      guard rect.paint.visibility == .visible, isFilled(rect.paint) else { return nil }
      let local = transform.concatenating(rect.transform.matrix)
      let bounds = CGRect(origin: rect.origin, size: rect.size)
      if localContains(local, bounds: bounds, point: point) {
        return SVGHitResult(path: path, element: element)
      }
    case .circle(let circle):
      guard circle.paint.visibility == .visible, isFilled(circle.paint) else { return nil }
      let local = transform.concatenating(circle.transform.matrix)
      let center = circle.center.applying(local)
      let radius = circle.radius * max(abs(local.a), abs(local.d))
      let dx = point.x - center.x
      let dy = point.y - center.y
      if dx * dx + dy * dy <= radius * radius {
        return SVGHitResult(path: path, element: element)
      }
    case .ellipse(let ellipse):
      guard ellipse.paint.visibility == .visible, isFilled(ellipse.paint) else { return nil }
      let local = transform.concatenating(ellipse.transform.matrix)
      let center = ellipse.center.applying(local)
      let rx = ellipse.radii.width * abs(local.a)
      let ry = ellipse.radii.height * abs(local.d)
      guard rx > 0, ry > 0 else { return nil }
      let dx = (point.x - center.x) / rx
      let dy = (point.y - center.y) / ry
      if dx * dx + dy * dy <= 1 {
        return SVGHitResult(path: path, element: element)
      }
    case .line(let line):
      guard line.paint.visibility == .visible else { return nil }
      let local = transform.concatenating(line.transform.matrix)
      let start = line.start.applying(local)
      let end = line.end.applying(local)
      if distanceToSegment(point: point, start: start, end: end) <= max(2, line.paint.strokeWidth) {
        return SVGHitResult(path: path, element: element)
      }
    case .polyline(let polyline):
      guard polyline.paint.visibility == .visible, !polyline.points.isEmpty else { return nil }
      let local = transform.concatenating(polyline.transform.matrix)
      let points = polyline.points.map { $0.applying(local) }
      if pointInPolyline(point: point, points: points, strokeWidth: polyline.paint.strokeWidth) {
        return SVGHitResult(path: path, element: element)
      }
    case .polygon(let polygon):
      guard polygon.paint.visibility == .visible, isFilled(polygon.paint), !polygon.points.isEmpty else {
        return nil
      }
      let local = transform.concatenating(polygon.transform.matrix)
      let points = polygon.points.map { $0.applying(local) }
      if pointInPolygon(point: point, points: points) {
        return SVGHitResult(path: path, element: element)
      }
    case .path:
      break
    case .text(let text):
      guard text.paint.visibility == .visible else { return nil }
      let local = transform.concatenating(text.transform.matrix)
      let origin = text.origin.applying(local)
      let width = CGFloat(max(text.string.count, 1)) * text.font.size * 0.6
      let height = text.font.size * 1.2
      let bounds = CGRect(x: origin.x, y: origin.y - height, width: width, height: height)
      if bounds.contains(point) {
        return SVGHitResult(path: path, element: element)
      }
    case .use:
      break
    }
    return nil
  }

  private static func isFilled(_ paint: SVGPaintProperties) -> Bool {
    if case .none = paint.fill { return false }
    return true
  }

  private static func localContains(
    _ transform: CGAffineTransform,
    bounds: CGRect,
    point: CGPoint
  ) -> Bool {
    guard transform.invertible else { return false }
    let localPoint = point.applying(transform.inverted())
    return bounds.contains(localPoint)
  }

  private static func distanceToSegment(point: CGPoint, start: CGPoint, end: CGPoint) -> CGFloat {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0 else {
      let px = point.x - start.x
      let py = point.y - start.y
      return sqrt(px * px + py * py)
    }
    let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
    let projX = start.x + t * dx
    let projY = start.y + t * dy
    let px = point.x - projX
    let py = point.y - projY
    return sqrt(px * px + py * py)
  }

  private static func pointInPolyline(point: CGPoint, points: [CGPoint], strokeWidth: CGFloat) -> Bool {
    let threshold = max(2, strokeWidth)
    guard let first = points.first else { return false }
    var previous = first
    for current in points.dropFirst() {
      if distanceToSegment(point: point, start: previous, end: current) <= threshold {
        return true
      }
      previous = current
    }
    return false
  }

  private static func pointInPolygon(point: CGPoint, points: [CGPoint]) -> Bool {
    guard points.count >= 3 else { return false }
    var inside = false
    var previous = points[points.count - 1]
    for current in points {
      let intersects = (current.y > point.y) != (previous.y > point.y)
        && point.x < (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x
      if intersects { inside.toggle() }
      previous = current
    }
    return inside
  }
}

private extension CGAffineTransform {
  var invertible: Bool {
    a * d - b * c != 0
  }
}
