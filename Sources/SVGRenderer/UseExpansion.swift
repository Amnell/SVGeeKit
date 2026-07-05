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
      let inheritedFill = predominantFill(in: g)
      var group = g
      group.children = g.children.map { instanceGroupChild($0, use: use, inheritedFill: inheritedFill) }
      return .group(group)
    case .svg(var svg):
      svg.children = svg.children.map { instanceGroupChild($0, use: use, inheritedFill: nil) }
      return .svg(svg)
    default:
      return instanceGroupChild(element, use: use, inheritedFill: nil)
    }
  }

  private static func instanceGroupChild(
    _ element: SVGElement,
    use: SVGUse,
    inheritedFill: SVGPaint?
  ) -> SVGElement {
    switch element {
    case .group(let g):
      return instanceElement(.group(g), use: use)
    case .svg(let svg):
      return instanceElement(.svg(svg), use: use)
    case .rect(var r):
      r.paint = mergedInstancePaint(r.paint, use: use, inheritedFill: inheritedFill)
      return .rect(r)
    case .circle(var c):
      c.paint = mergedInstancePaint(c.paint, use: use, inheritedFill: inheritedFill)
      return .circle(c)
    case .ellipse(var e):
      e.paint = mergedInstancePaint(e.paint, use: use, inheritedFill: inheritedFill)
      return .ellipse(e)
    case .line(var l):
      l.paint = mergedInstancePaint(l.paint, use: use, inheritedFill: inheritedFill)
      return .line(l)
    case .polyline(var p):
      p.paint = mergedInstancePaint(p.paint, use: use, inheritedFill: inheritedFill)
      return .polyline(p)
    case .polygon(var p):
      p.paint = mergedInstancePaint(p.paint, use: use, inheritedFill: inheritedFill)
      return .polygon(p)
    case .path(var p):
      p.paint = mergedInstancePaint(p.paint, use: use, inheritedFill: inheritedFill)
      return .path(p)
    case .text(var t):
      t.paint = mergedInstancePaint(t.paint, use: use, inheritedFill: inheritedFill)
      return .text(t)
    case .use:
      return element
    case .image(var img):
      img.paint = mergedInstancePaint(img.paint, use: use, inheritedFill: inheritedFill)
      return .image(img)
    }
  }

  private static func mergedInstancePaint(
    _ referenced: SVGPaintProperties,
    use: SVGUse,
    inheritedFill: SVGPaint?
  ) -> SVGPaintProperties {
    var paint = referenced
    for key in use.explicitPresentation where key != "fill" {
      applyPresentationKey(key, from: use.paint, into: &paint)
    }
    if use.explicitPresentation.contains("fill") {
      if let inheritedFill {
        if referenced.fill == inheritedFill {
          paint.fill = use.paint.fill
        }
      } else {
        paint.fill = use.paint.fill
      }
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
    case "clip-path": paint.clipPathRef = source.clipPathRef
    case "mask": paint.maskRef = source.maskRef
    default: break
    }
  }

  private static func predominantFill(in group: SVGGroup) -> SVGPaint? {
    for child in group.children {
      if let fill = shapeFill(child) { return fill }
    }
    return nil
  }

  private static func shapeFill(_ element: SVGElement) -> SVGPaint? {
    switch element {
    case .rect(let r): return r.paint.fill
    case .circle(let c): return c.paint.fill
    case .ellipse(let e): return e.paint.fill
    case .line(let l): return l.paint.fill
    case .polyline(let p): return p.paint.fill
    case .polygon(let p): return p.paint.fill
    case .path(let p): return p.paint.fill
    case .text(let t): return t.paint.fill
    case .group, .svg, .use, .image: return nil
    }
  }
}
