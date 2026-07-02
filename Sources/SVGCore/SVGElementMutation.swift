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
        case .text(let text):
          if let id = text.id, !id.isEmpty {
            index[id] = SVGElementPath(indices: path)
          }
        case .rect, .circle, .ellipse, .line, .polyline, .polygon, .path, .use:
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
      guard case .group(let group) = element else { return nil }
      currentChildren = group.children
    }
    return element
  }

  public mutating func setAttribute(at path: SVGElementPath, name: String, value: String) throws {
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
    switch (name.lowercased(), element) {
      case ("visibility", .group(var group)):
        guard let visibility = SVGVisibility(rawValue: value.lowercased()) else {
          throw SVGElementMutationError.unsupportedAttribute(name)
        }
        group.visibility = visibility
        if visibility == .hidden {
          Self.hideDescendants(in: &group)
        } else if visibility == .visible {
          Self.showDescendants(in: &group)
        }
        return .group(group)
      case ("visibility", .rect(var rect)):
        guard let visibility = SVGVisibility(rawValue: value.lowercased()) else {
          throw SVGElementMutationError.unsupportedAttribute(name)
        }
        rect.paint.visibility = visibility
        return .rect(rect)
      case ("visibility", .circle(var circle)):
        guard let visibility = SVGVisibility(rawValue: value.lowercased()) else {
          throw SVGElementMutationError.unsupportedAttribute(name)
        }
        circle.paint.visibility = visibility
        return .circle(circle)
      case ("visibility", .ellipse(var ellipse)):
        guard let visibility = SVGVisibility(rawValue: value.lowercased()) else {
          throw SVGElementMutationError.unsupportedAttribute(name)
        }
        ellipse.paint.visibility = visibility
        return .ellipse(ellipse)
      case ("visibility", .line(var line)):
        guard let visibility = SVGVisibility(rawValue: value.lowercased()) else {
          throw SVGElementMutationError.unsupportedAttribute(name)
        }
        line.paint.visibility = visibility
        return .line(line)
      case ("visibility", .polyline(var polyline)):
        guard let visibility = SVGVisibility(rawValue: value.lowercased()) else {
          throw SVGElementMutationError.unsupportedAttribute(name)
        }
        polyline.paint.visibility = visibility
        return .polyline(polyline)
      case ("visibility", .polygon(var polygon)):
        guard let visibility = SVGVisibility(rawValue: value.lowercased()) else {
          throw SVGElementMutationError.unsupportedAttribute(name)
        }
        polygon.paint.visibility = visibility
        return .polygon(polygon)
      case ("visibility", .path(var pathEl)):
        guard let visibility = SVGVisibility(rawValue: value.lowercased()) else {
          throw SVGElementMutationError.unsupportedAttribute(name)
        }
        pathEl.paint.visibility = visibility
        return .path(pathEl)
      case ("visibility", .text(var text)):
        guard let visibility = SVGVisibility(rawValue: value.lowercased()) else {
          throw SVGElementMutationError.unsupportedAttribute(name)
        }
        text.paint.visibility = visibility
        for index in text.runs.indices {
          text.runs[index].paint.visibility = visibility
        }
        return .text(text)
      case ("fill", .rect(var rect)):
        rect.paint.fill = try Self.parseFill(value)
        return .rect(rect)
      case ("fill", .circle(var circle)):
        circle.paint.fill = try Self.parseFill(value)
        return .circle(circle)
      case ("fill", .text(var text)):
        text.paint.fill = try Self.parseFill(value)
        for index in text.runs.indices {
          text.runs[index].paint.fill = text.paint.fill
        }
        return .text(text)
      case ("fill", .group):
        throw SVGElementMutationError.unsupportedAttribute(name)
      default:
        throw SVGElementMutationError.unsupportedAttribute(name)
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
    guard case .group(var group) = children[index] else { throw SVGElementMutationError.notFound }
    try mutateChildren(&group.children, path: path, depth: depth + 1, transform: transform)
    children[index] = .group(group)
  }

  private static func parseFill(_ value: String) throws -> SVGPaint {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if trimmed == "none" { return .none }
    if let color = SVGColorParser.parse(trimmed) {
      return .color(color)
    }
    throw SVGElementMutationError.unsupportedAttribute("fill")
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
      if value.hasPrefix("#"), value.count == 7 {
        let hex = value.dropFirst()
        guard let rgb = UInt32(hex, radix: 16) else { return nil }
        return SVGColor(
          red: CGFloat((rgb >> 16) & 0xFF) / 255,
          green: CGFloat((rgb >> 8) & 0xFF) / 255,
          blue: CGFloat(rgb & 0xFF) / 255
        )
      }
      return nil
    }
  }
}
