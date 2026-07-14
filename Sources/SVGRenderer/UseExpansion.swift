import CoreGraphics
import SVGCore

enum SVGUseExpansion {

  static func placementTransform(for use: SVGUse) -> CGAffineTransform {
    CGAffineTransform(translationX: use.origin.x, y: use.origin.y)
      .concatenating(use.transform.matrix)
  }

  static func instanceElement(_ element: SVGElement, use: SVGUse) -> SVGElement {
    switch element {
    case .group(let g):
      var group = g
      group.children = g.children.map { instanceGroupChild($0, use: use) }
      return .group(group)
    case .svg(var svg):
      svg.children = svg.children.map { instanceGroupChild($0, use: use) }
      return .svg(svg)
    default:
      return instanceGroupChild(element, use: use)
    }
  }

  private static func instanceGroupChild(
    _ element: SVGElement,
    use: SVGUse
  ) -> SVGElement {
    switch element {
    case .group(let g):
      return instanceElement(.group(g), use: use)
    case .svg(let svg):
      return instanceElement(.svg(svg), use: use)
    case .rect(var r):
      r.paint = mergedInstancePaint(
        r.paint, use: use, explicitPresentation: r.explicitPresentation
      )
      return .rect(r)
    case .circle(var c):
      c.paint = mergedInstancePaint(c.paint, use: use)
      return .circle(c)
    case .ellipse(var e):
      e.paint = mergedInstancePaint(e.paint, use: use)
      return .ellipse(e)
    case .line(var l):
      l.paint = mergedInstancePaint(l.paint, use: use)
      return .line(l)
    case .polyline(var p):
      p.paint = mergedInstancePaint(p.paint, use: use)
      return .polyline(p)
    case .polygon(var p):
      p.paint = mergedInstancePaint(p.paint, use: use)
      return .polygon(p)
    case .path(var p):
      p.paint = mergedInstancePaint(p.paint, use: use)
      return .path(p)
    case .text(var t):
      t.paint = mergedInstancePaint(t.paint, use: use)
      return .text(t)
    case .use:
      return element
    case .image(var img):
      img.paint = mergedInstancePaint(img.paint, use: use)
      return .image(img)
    }
  }

  private static func mergedInstancePaint(
    _ referenced: SVGPaintProperties,
    use: SVGUse,
    explicitPresentation: Set<String> = []
  ) -> SVGPaintProperties {
    var paint = referenced
    for key in use.explicitPresentation where key != "fill" {
      applyPresentationKey(key, from: use.paint, into: &paint)
    }
    // Use fill overrides only shapes without a specified fill (struct-use-01-t).
    // Explicit fills on referenced children are kept (pservers-grad-13-b stripes + yellow base).
    if use.explicitPresentation.contains("fill"), !explicitPresentation.contains("fill") {
      paint.fill = use.paint.fill
    }
    return paint
  }

  private static func applyPresentationKey(
    _ key: String,
    from source: SVGPaintProperties,
    into paint: inout SVGPaintProperties
  ) {
    switch key {
    case "fill-opacity": paint.fillOpacity = source.fillOpacity
    case "fill-rule": paint.fillRule = source.fillRule
    case "stroke": paint.stroke = source.stroke
    case "stroke-opacity": paint.strokeOpacity = source.strokeOpacity
    case "stroke-width": paint.strokeWidth = source.strokeWidth
    case "stroke-linecap": paint.lineCap = source.lineCap
    case "stroke-linejoin": paint.lineJoin = source.lineJoin
    case "stroke-miterlimit": paint.miterLimit = source.miterLimit
    case "stroke-dasharray": paint.strokeDashArray = source.strokeDashArray
    case "stroke-dashoffset": paint.strokeDashOffset = source.strokeDashOffset
    case "opacity": paint.opacity = source.opacity
    case "color": paint.color = source.color
    case "visibility": paint.visibility = source.visibility
    case "display": paint.visibility = source.visibility
    case "clip-path": paint.clipPathRef = source.clipPathRef
    case "mask": paint.maskRef = source.maskRef
    default: break
    }
  }
}
