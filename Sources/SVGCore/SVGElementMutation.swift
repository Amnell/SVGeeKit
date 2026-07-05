import Foundation

public enum SVGElementMutationError: Error, Equatable {
  case notFound
  case unsupportedAttribute(String)
}

extension SVGDocument {

  /// Walk the render tree and index every element `id` (groups only today).
  public static func buildElementIndex(root: SVGGroup) -> [String: SVGElementPath] {
    var index: [String: SVGElementPath] = [:]
    if let id = root.id, !id.isEmpty {
      index[id] = SVGElementPath(indices: [])
    }
    func walk(_ elements: [SVGElement], prefix: [Int]) {
      for (offset, element) in elements.enumerated() {
        let path = prefix + [offset]
        switch element {
        case .group(let group):
          if let id = group.id, !id.isEmpty {
            index[id] = SVGElementPath(indices: path)
          }
          walk(group.children, prefix: path)
        case .svg(let svg):
          if let id = svg.id, !id.isEmpty {
            index[id] = SVGElementPath(indices: path)
          }
          walk(svg.children, prefix: path)
        case .text(let text):
          if let id = text.id, !id.isEmpty {
            index[id] = SVGElementPath(indices: path)
          }
        case .rect(let rect):
          if let id = rect.id, !id.isEmpty {
            index[id] = SVGElementPath(indices: path)
          }
        case .circle, .ellipse, .line, .polyline, .polygon, .path, .use:
          break
        }
      }
    }
    walk(root.children, prefix: [])
    return index
  }

  public func element(at path: SVGElementPath) -> SVGElement? {
    if path.indices.isEmpty {
      return .group(root)
    }
    var currentChildren = root.children
    var element: SVGElement?
    for (depth, index) in path.indices.enumerated() {
      guard index >= 0, index < currentChildren.count else { return nil }
      element = currentChildren[index]
      guard depth < path.indices.count - 1 else { break }
      switch element {
      case .group(let group):
        currentChildren = group.children
      case .svg(let svg):
        currentChildren = svg.children
      default:
        return nil
      }
    }
    return element
  }

  public mutating func setAttribute(at path: SVGElementPath, name: String, value: String) throws {
    let key = name.lowercased()
    if let element = element(at: path), case .group = element,
       Self.inheritablePresentationAttributes.contains(key) {
      try cascadeInheritableAttribute(at: path, name: key, value: value)
      return
    }
    if path.indices.isEmpty {
      let rootGroup = root
      let updated = try Self.applyAttribute(name: name, value: value, to: .group(rootGroup))
      guard case .group(let group) = updated else { throw SVGElementMutationError.notFound }
      root = group
      return
    }
    try mutate(at: path) { try Self.applyAttribute(name: name, value: value, to: $0) }
  }

  private static func applyAttribute(name: String, value: String, to element: SVGElement) throws -> SVGElement {
    let key = name.lowercased()
    switch element {
    case .group(var group):
      switch key {
      case "visibility":
        guard let visibility = SVGVisibility(rawValue: value.lowercased()) else {
          throw SVGElementMutationError.unsupportedAttribute(name)
        }
        group.visibility = visibility
        if visibility == .hidden { hideDescendants(in: &group) }
        else if visibility == .visible { showDescendants(in: &group) }
        return .group(group)
      case "display":
        return try applyAttribute(name: "visibility", value: displayToVisibility(value), to: .group(group))
      case "opacity":
        group.opacity = try parseOpacity(value)
        return .group(group)
      default:
        throw SVGElementMutationError.unsupportedAttribute(name)
      }
    case .rect(var rect):
      if try applyPaintAttribute(key: key, value: value, paint: &rect.paint) {
        return .rect(rect)
      }
      switch key {
      case "x": rect.origin.x = try parseLength(value); return .rect(rect)
      case "y": rect.origin.y = try parseLength(value); return .rect(rect)
      case "width": rect.size.width = try parseLength(value); return .rect(rect)
      case "height": rect.size.height = try parseLength(value); return .rect(rect)
      default: throw SVGElementMutationError.unsupportedAttribute(name)
      }
    case .circle(var circle):
      if try applyPaintAttribute(key: key, value: value, paint: &circle.paint) {
        return .circle(circle)
      }
      switch key {
      case "cx": circle.center.x = try parseLength(value); return .circle(circle)
      case "cy": circle.center.y = try parseLength(value); return .circle(circle)
      case "r": circle.radius = try parseLength(value); return .circle(circle)
      default: throw SVGElementMutationError.unsupportedAttribute(name)
      }
    case .ellipse(var ellipse):
      if try applyPaintAttribute(key: key, value: value, paint: &ellipse.paint) {
        return .ellipse(ellipse)
      }
      switch key {
      case "cx": ellipse.center.x = try parseLength(value); return .ellipse(ellipse)
      case "cy": ellipse.center.y = try parseLength(value); return .ellipse(ellipse)
      case "rx": ellipse.radii.width = try parseLength(value); return .ellipse(ellipse)
      case "ry": ellipse.radii.height = try parseLength(value); return .ellipse(ellipse)
      default: throw SVGElementMutationError.unsupportedAttribute(name)
      }
    case .line(var line):
      if try applyPaintAttribute(key: key, value: value, paint: &line.paint) {
        return .line(line)
      }
      switch key {
      case "x1": line.start.x = try parseLength(value); return .line(line)
      case "y1": line.start.y = try parseLength(value); return .line(line)
      case "x2": line.end.x = try parseLength(value); return .line(line)
      case "y2": line.end.y = try parseLength(value); return .line(line)
      default: throw SVGElementMutationError.unsupportedAttribute(name)
      }
    case .polyline(var polyline):
      if try applyPaintAttribute(key: key, value: value, paint: &polyline.paint) {
        return .polyline(polyline)
      }
      throw SVGElementMutationError.unsupportedAttribute(name)
    case .polygon(var polygon):
      if try applyPaintAttribute(key: key, value: value, paint: &polygon.paint) {
        return .polygon(polygon)
      }
      throw SVGElementMutationError.unsupportedAttribute(name)
    case .path(var pathEl):
      if try applyPaintAttribute(key: key, value: value, paint: &pathEl.paint) {
        return .path(pathEl)
      }
      throw SVGElementMutationError.unsupportedAttribute(name)
    case .text(var text):
      if key == "x" {
        text.origin.x = try parseLength(value)
        return .text(text)
      }
      if key == "y" {
        text.origin.y = try parseLength(value)
        return .text(text)
      }
      if key == "font-size" {
        let size = try parseLength(value)
        text.font.size = size
        for index in text.runs.indices {
          text.runs[index].font.size = size
        }
        return .text(text)
      }
      if try applyPaintAttribute(key: key, value: value, paint: &text.paint) {
        for index in text.runs.indices {
          switch key {
          case "fill": text.runs[index].paint.fill = text.paint.fill
          case "opacity": text.runs[index].paint.opacity = text.paint.opacity
          case "visibility": text.runs[index].paint.visibility = text.paint.visibility
          default: break
          }
        }
        return .text(text)
      }
      throw SVGElementMutationError.unsupportedAttribute(name)
    case .use(var use):
      if try applyPaintAttribute(key: key, value: value, paint: &use.paint) {
        return .use(use)
      }
      switch key {
      case "x": use.origin.x = try parseLength(value); return .use(use)
      case "y": use.origin.y = try parseLength(value); return .use(use)
      case "width":
        let width = try parseLength(value)
        let height = use.size?.height ?? width
        use.size = CGSize(width: width, height: height)
        return .use(use)
      case "height":
        let height = try parseLength(value)
        let width = use.size?.width ?? height
        use.size = CGSize(width: width, height: height)
        return .use(use)
      default: throw SVGElementMutationError.unsupportedAttribute(name)
      }
    case .svg:
      throw SVGElementMutationError.unsupportedAttribute(name)
    }
  }

  @discardableResult
  private static func applyPaintAttribute(
    key: String,
    value: String,
    paint: inout SVGPaintProperties
  ) throws -> Bool {
    switch key {
    case "visibility":
      guard let visibility = SVGVisibility(rawValue: value.lowercased()) else {
        throw SVGElementMutationError.unsupportedAttribute(key)
      }
      paint.visibility = visibility
      return true
    case "display":
      paint.visibility = SVGVisibility(rawValue: displayToVisibility(value)) ?? paint.visibility
      return true
    case "opacity":
      paint.opacity = try parseOpacity(value)
      return true
    case "fill":
      paint.fill = try parseFill(value)
      return true
    case "fill-opacity":
      paint.fillOpacity = try parseOpacity(value)
      return true
    case "stroke":
      paint.stroke = try parseFill(value)
      return true
    case "stroke-opacity":
      paint.strokeOpacity = try parseOpacity(value)
      return true
    case "stroke-width":
      paint.strokeWidth = try parseLength(value)
      return true
    default:
      return false
    }
  }

  private static func displayToVisibility(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "none" ? "hidden" : "visible"
  }

  private static func parseLength(_ value: String) throws -> CGFloat {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if let number = Double(trimmed) {
      return CGFloat(number)
    }
    throw SVGElementMutationError.unsupportedAttribute(trimmed)
  }

  private static func parseOpacity(_ value: String) throws -> CGFloat {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if let number = Double(trimmed) {
      return CGFloat(number)
    }
    throw SVGElementMutationError.unsupportedAttribute(trimmed)
  }

  private static let inheritablePresentationAttributes: Set<String> = [
    "fill", "fill-opacity", "fill-rule", "stroke", "stroke-opacity", "stroke-width",
    "stroke-linecap", "stroke-linejoin", "stroke-miterlimit", "stroke-dasharray",
    "stroke-dashoffset", "color", "opacity", "font-family", "font-size", "font-weight",
    "font-style", "text-anchor"
  ]

  private mutating func cascadeInheritableAttribute(
    at path: SVGElementPath,
    name: String,
    value: String
  ) throws {
    if path.indices.isEmpty {
      var children = root.children
      try Self.cascadeInheritableAttribute(into: &children, name: name, value: value)
      root.children = children
      return
    }
    var children = root.children
    try Self.cascadeInheritableAttribute(
      in: &children,
      path: path.indices,
      depth: 0,
      name: name,
      value: value
    )
    root.children = children
  }

  private static func cascadeInheritableAttribute(
    in children: inout [SVGElement],
    path: [Int],
    depth: Int,
    name: String,
    value: String
  ) throws {
    let index = path[depth]
    guard index >= 0, index < children.count else { throw SVGElementMutationError.notFound }
    if depth == path.count - 1 {
      guard case .group(var group) = children[index] else { throw SVGElementMutationError.notFound }
      try cascadeInheritableAttribute(into: &group.children, name: name, value: value)
      children[index] = .group(group)
      return
    }
    switch children[index] {
    case .group(var group):
      try cascadeInheritableAttribute(
        in: &group.children,
        path: path,
        depth: depth + 1,
        name: name,
        value: value
      )
      children[index] = .group(group)
    case .svg(var svg):
      try cascadeInheritableAttribute(
        in: &svg.children,
        path: path,
        depth: depth + 1,
        name: name,
        value: value
      )
      children[index] = .svg(svg)
    default:
      throw SVGElementMutationError.notFound
    }
  }

  private static func cascadeInheritableAttribute(
    into children: inout [SVGElement],
    name: String,
    value: String
  ) throws {
    for index in children.indices {
      switch children[index] {
      case .text(let text):
        guard !text.explicitPresentation.contains(name) else { continue }
        children[index] = try applyAttribute(name: name, value: value, to: .text(text))
      case .group(var group):
        guard !group.explicitPresentation.contains(name) else { continue }
        try cascadeInheritableAttribute(into: &group.children, name: name, value: value)
        children[index] = .group(group)
      case .svg(var svg):
        try cascadeInheritableAttribute(into: &svg.children, name: name, value: value)
        children[index] = .svg(svg)
      case .circle(let circle):
        guard !circle.explicitPresentation.contains(name) else { continue }
        children[index] = try applyAttribute(name: name, value: value, to: .circle(circle))
      case .path(let path):
        guard !path.explicitPresentation.contains(name) else { continue }
        children[index] = try applyAttribute(name: name, value: value, to: .path(path))
      default:
        break
      }
    }
  }

  private mutating func mutate(
    at path: SVGElementPath,
    _ transform: (SVGElement) throws -> SVGElement
  ) throws {
    var children = root.children
    try Self.mutateChildren(&children, path: path.indices, depth: 0, transform: transform)
    root.children = children
  }

  private static func mutateChildren(
    _ children: inout [SVGElement],
    path: [Int],
    depth: Int,
    transform: (SVGElement) throws -> SVGElement
  ) throws {
    guard depth < path.count else { throw SVGElementMutationError.notFound }
    let index = path[depth]
    guard index >= 0, index < children.count else { throw SVGElementMutationError.notFound }
    if depth == path.count - 1 {
      children[index] = try transform(children[index])
      return
    }
    switch children[index] {
    case .group(var group):
      try mutateChildren(&group.children, path: path, depth: depth + 1, transform: transform)
      children[index] = .group(group)
    case .svg(var svg):
      try mutateChildren(&svg.children, path: path, depth: depth + 1, transform: transform)
      children[index] = .svg(svg)
    default:
      throw SVGElementMutationError.notFound
    }
  }

  private static func parseFill(_ value: String) throws -> SVGPaint {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if trimmed == "none" { return .none }
    if let color = SVGColorParser.parse(trimmed) {
      return .color(color)
    }
    if trimmed.hasPrefix("rgb("), trimmed.hasSuffix(")") {
      let inner = trimmed.dropFirst(4).dropLast()
      let parts = inner.split(separator: ",").compactMap { parseColorComponent(String($0)) }
      guard parts.count == 3 else {
        throw SVGElementMutationError.unsupportedAttribute("fill")
      }
      return .color(SVGColor(red: parts[0], green: parts[1], blue: parts[2]))
    }
    throw SVGElementMutationError.unsupportedAttribute("fill")
  }

  private static func parseColorComponent(_ raw: String) -> CGFloat? {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    if trimmed.hasSuffix("%"), let value = Double(trimmed.dropLast()) {
      return CGFloat(value / 100)
    }
    if let value = Double(trimmed) {
      return CGFloat(value > 1 ? value / 255 : value)
    }
    return nil
  }

  private static func hideDescendants(in group: inout SVGGroup) {
    for index in group.children.indices {
      group.children[index] = hideElement(group.children[index])
    }
  }

  private static func showDescendants(in group: inout SVGGroup) {
    for index in group.children.indices {
      group.children[index] = showElement(group.children[index])
    }
  }

  private static func hideElement(_ element: SVGElement) -> SVGElement {
    switch element {
    case .group(var group):
      group.visibility = .hidden
      hideDescendants(in: &group)
      return .group(group)
    case .svg(var svg):
      for index in svg.children.indices {
        svg.children[index] = hideElement(svg.children[index])
      }
      return .svg(svg)
    case .rect(var rect):
      rect.paint.visibility = .hidden
      return .rect(rect)
    case .circle(var circle):
      circle.paint.visibility = .hidden
      return .circle(circle)
    case .ellipse(var ellipse):
      ellipse.paint.visibility = .hidden
      return .ellipse(ellipse)
    case .line(var line):
      line.paint.visibility = .hidden
      return .line(line)
    case .polyline(var polyline):
      polyline.paint.visibility = .hidden
      return .polyline(polyline)
    case .polygon(var polygon):
      polygon.paint.visibility = .hidden
      return .polygon(polygon)
    case .path(var path):
      path.paint.visibility = .hidden
      return .path(path)
    case .text(var text):
      text.paint.visibility = .hidden
      for index in text.runs.indices {
        text.runs[index].paint.visibility = .hidden
      }
      return .text(text)
    case .use:
      return element
    }
  }

  private static func showElement(_ element: SVGElement) -> SVGElement {
    switch element {
    case .group(var group):
      group.visibility = .visible
      showDescendants(in: &group)
      return .group(group)
    case .svg(var svg):
      for index in svg.children.indices {
        svg.children[index] = showElement(svg.children[index])
      }
      return .svg(svg)
    case .rect(var rect):
      rect.paint.visibility = .visible
      return .rect(rect)
    case .circle(var circle):
      circle.paint.visibility = .visible
      return .circle(circle)
    case .ellipse(var ellipse):
      ellipse.paint.visibility = .visible
      return .ellipse(ellipse)
    case .line(var line):
      line.paint.visibility = .visible
      return .line(line)
    case .polyline(var polyline):
      polyline.paint.visibility = .visible
      return .polyline(polyline)
    case .polygon(var polygon):
      polygon.paint.visibility = .visible
      return .polygon(polygon)
    case .path(var path):
      path.paint.visibility = .visible
      return .path(path)
    case .text(var text):
      text.paint.visibility = .visible
      for index in text.runs.indices {
        text.runs[index].paint.visibility = .visible
      }
      return .text(text)
    case .use:
      return element
    }
  }
}

/// Minimal color parser for script-driven `setAttribute('fill', …)`.
enum SVGColorParser {
  static func parse(_ raw: String) -> SVGColor? {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch value {
    case "black": return .black
    case "white": return .white
    case "red": return SVGColor(red: 1, green: 0, blue: 0)
    case "green": return SVGColor(red: 0, green: 1, blue: 0)
    case "blue": return SVGColor(red: 0, green: 0, blue: 1)
    case "lime": return SVGColor(red: 0, green: 1, blue: 0)
    default:
      if value.hasPrefix("#") {
        let hex = String(value.dropFirst())
        if let color = parseHexColor(hex) {
          return color
        }
      }
      return nil
    }
  }

  private static func parseHexColor(_ hex: String) -> SVGColor? {
    func byte(_ substring: Substring) -> CGFloat? {
      guard let value = UInt32(substring, radix: 16) else { return nil }
      return CGFloat(value) / 255
    }
    switch hex.count {
    case 3:
      let chars = Array(hex)
      guard chars.count == 3,
            let red = byte(Substring("\(chars[0])\(chars[0])")),
            let green = byte(Substring("\(chars[1])\(chars[1])")),
            let blue = byte(Substring("\(chars[2])\(chars[2])")) else {
        return nil
      }
      return SVGColor(red: red, green: green, blue: blue)
    case 6:
      let start = hex.startIndex
      guard let red = byte(hex[start..<hex.index(start, offsetBy: 2)]),
            let green = byte(hex[hex.index(start, offsetBy: 2)..<hex.index(start, offsetBy: 4)]),
            let blue = byte(hex[hex.index(start, offsetBy: 4)..<hex.index(start, offsetBy: 6)]) else {
        return nil
      }
      return SVGColor(red: red, green: green, blue: blue)
    default:
      return nil
    }
  }
}
