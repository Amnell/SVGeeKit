import Foundation
import SVGCore
import SVGParser

/// Samples declarative SMIL animations at a document timeline offset.
public enum SVGAnimationEngine {

    private struct TargetedAnimation {
        var path: SVGElementPath
        var animation: SVGTimedAnimation
    }

    /// Returns a copy of `document` with animated attributes applied at `time` seconds.
    public static func sample(document: SVGDocument, at time: Double) -> SVGDocument {
        var doc = document
        let targets = collectAnimations(from: document)
        for targeted in targets {
            guard let application = valueToApply(
                targeted.animation,
                at: time,
                baseElement: document.element(at: targeted.path)
            ) else {
                continue
            }
            switch application {
            case .attribute(let name, let value):
                try? doc.setAttribute(at: targeted.path, name: name, value: value)
            case .setElement(let set):
                try? doc.setAttribute(at: targeted.path, name: set.attributeName, value: set.to)
            }
        }
        return doc
    }

    /// Whether the parsed document carries any declarative SMIL elements.
    public static func containsAnimations(in document: SVGDocument) -> Bool {
        if !document.animationMetadata.rootAnimations.isEmpty { return true }
        return walkForAnimations(document.root.children)
    }

    /// Upper bound for the document timeline (latest `begin + dur * repeatCount` across animations).
    public static func suggestedDuration(in document: SVGDocument) -> Double {
        var maxEnd: Double = 0
        func consider(_ animation: SVGTimedAnimation) {
            let begin = resolveBegin(animation.timing.begin) ?? 0
            let dur = animation.timing.dur ?? 0
            let repeats = resolvedRepeatCount(animation.timing.repeatCount)
            let total = repeats == .indefinite ? dur * 10 : dur * repeats.value
            maxEnd = max(maxEnd, begin + total)
        }
        for animation in document.animationMetadata.rootAnimations {
            consider(animation)
        }
        collectAllAnimations(from: document.root.children).forEach(consider)
        return max(maxEnd, 1)
    }

    private static func walkForAnimations(_ elements: [SVGElement]) -> Bool {
        for element in elements {
            if !element.animations.isEmpty { return true }
            if case .group(let group) = element, walkForAnimations(group.children) {
                return true
            }
            if case .svg(let svg) = element, walkForAnimations(svg.children) {
                return true
            }
        }
        return false
    }

    private static func collectAllAnimations(from elements: [SVGElement]) -> [SVGTimedAnimation] {
        var results: [SVGTimedAnimation] = []
        func walk(_ elements: [SVGElement]) {
            for element in elements {
                results.append(contentsOf: element.animations)
                if case .group(let group) = element {
                    walk(group.children)
                }
                if case .svg(let svg) = element {
                    walk(svg.children)
                }
            }
        }
        walk(elements)
        return results
    }

    private enum Application {
        case attribute(name: String, value: String)
        case setElement(SVGSetElement)
    }

    private static func collectAnimations(from document: SVGDocument) -> [TargetedAnimation] {
        let elementIndex = document.scriptMetadata.elementIndex
        var results: [TargetedAnimation] = []
        func walk(_ elements: [SVGElement], prefix: [Int]) {
            for (offset, element) in elements.enumerated() {
                let path = SVGElementPath(indices: prefix + [offset])
                for animation in element.animations {
                    let targetPath = resolveTargetPath(
                        for: animation,
                        carrierPath: path,
                        elementIndex: elementIndex
                    )
                    guard let targetPath else { continue }
                    results.append(TargetedAnimation(path: targetPath, animation: animation))
                }
                if case .group(let group) = element {
                    walk(group.children, prefix: path.indices)
                }
                if case .svg(let svg) = element {
                    walk(svg.children, prefix: path.indices)
                }
            }
        }
        walk(document.root.children, prefix: [])
        for animation in document.animationMetadata.rootAnimations {
            if let targetPath = resolveTargetPath(
                for: animation,
                carrierPath: SVGElementPath(indices: []),
                elementIndex: elementIndex
            ) {
                results.append(TargetedAnimation(path: targetPath, animation: animation))
            }
        }
        return results
    }

    private static func resolveTargetPath(
        for animation: SVGTimedAnimation,
        carrierPath: SVGElementPath,
        elementIndex: [String: SVGElementPath]
    ) -> SVGElementPath? {
        if let href = animation.targetHref {
            return elementIndex[href]
        }
        return carrierPath
    }

    private enum RepeatCount: Equatable {
        case finite(Double)
        case indefinite

        var value: Double {
            switch self {
            case .finite(let count): count
            case .indefinite: .infinity
            }
        }
    }

    private struct ActiveIteration {
        var index: Int
        var iterationTime: Double
        var isFrozen: Bool
    }

    private static func valueToApply(
        _ animation: SVGTimedAnimation,
        at time: Double,
        baseElement: SVGElement?
    ) -> Application? {
        switch animation {
        case .animate(let element):
            guard let value = animateValue(element, at: time, baseElement: baseElement) else { return nil }
            return .attribute(name: element.attributeName, value: value)
        case .set(let element):
            guard setIsActive(element, at: time) else { return nil }
            return .setElement(element)
        case .animateTransform, .animateMotion:
            return nil
        }
    }

    private static func animateValue(
        _ element: SVGAnimateElement,
        at time: Double,
        baseElement: SVGElement?
    ) -> String? {
        guard let active = activeIteration(element.timing, at: time) else { return nil }
        let dur = element.timing.dur ?? 0
        guard dur > 0 else { return nil }

        let calcMode = element.calcMode ?? defaultCalcMode(for: element)
        let valueList = parseValueList(element)
        let progress = min(1, active.iterationTime / dur)
        let raw = rawAnimatedValue(
            valueList: valueList,
            element: element,
            calcMode: calcMode,
            progress: progress
        )

        let accumulated = applyAccumulate(
            raw: raw,
            element: element,
            valueList: valueList,
            calcMode: calcMode,
            dur: dur,
            iteration: active.index
        )
        return applyAdditive(
            animated: accumulated,
            baseElement: baseElement,
            attributeName: element.attributeName,
            additive: element.additive
        )
    }

    private static func activeIteration(_ timing: SVGTimingAttributes, at time: Double) -> ActiveIteration? {
        guard let beginTime = resolveBegin(timing.begin) else { return nil }
        let dur = timing.dur ?? 0
        guard dur > 0 else { return nil }

        let elapsed = time - beginTime
        if elapsed < 0 { return nil }

        let repeats = resolvedRepeatCount(timing.repeatCount)
        switch repeats {
        case .indefinite:
            let index = Int(floor(elapsed / dur))
            let iterationTime = elapsed - Double(index) * dur
            return ActiveIteration(index: index, iterationTime: iterationTime, isFrozen: false)
        case .finite(let count):
            let totalDuration = dur * count
            if elapsed >= totalDuration {
                guard timing.fill == .freeze else { return nil }
                return ActiveIteration(index: max(0, Int(count) - 1), iterationTime: dur, isFrozen: true)
            }
            let index = Int(floor(elapsed / dur))
            let iterationTime = elapsed - Double(index) * dur
            return ActiveIteration(index: index, iterationTime: iterationTime, isFrozen: false)
        }
    }

    private static func rawAnimatedValue(
        valueList: [String],
        element: SVGAnimateElement,
        calcMode: SVGCalcMode,
        progress: Double
    ) -> String {
        switch calcMode {
        case .discrete:
            let index = min(valueList.count - 1, Int(progress * Double(valueList.count)))
            return valueList[max(0, index)]
        case .linear, .paced, .spline:
            guard valueList.count >= 2 else {
                return valueList.first ?? element.from ?? ""
            }
            return interpolateValues(valueList, progress: progress, attributeName: element.attributeName)
        }
    }

    private static func applyAccumulate(
        raw: String,
        element: SVGAnimateElement,
        valueList: [String],
        calcMode: SVGCalcMode,
        dur: Double,
        iteration: Int
    ) -> String {
        guard element.accumulate?.lowercased() == "sum", iteration > 0 else { return raw }
        guard let rawNumbers = parseNumbers(raw) else { return raw }

        var accumulated = rawNumbers
        for _ in 0..<iteration {
            let endValue = rawAnimatedValue(
                valueList: valueList,
                element: element,
                calcMode: calcMode,
                progress: 1.0
            )
            guard let endNumbers = parseNumbers(endValue),
                  endNumbers.count == accumulated.count else {
                continue
            }
            accumulated = zip(accumulated, endNumbers).map(+)
        }
        return formatNumbers(accumulated, template: raw)
    }

    private static func applyAdditive(
        animated: String,
        baseElement: SVGElement?,
        attributeName: String,
        additive: String?
    ) -> String {
        guard additive?.lowercased() == "sum" else { return animated }
        guard let base = baseElement.flatMap({ attributeStringValue($0, name: attributeName) }),
              let baseNumbers = parseNumbers(base),
              let animatedNumbers = parseNumbers(animated),
              baseNumbers.count == animatedNumbers.count else {
            return animated
        }
        let summed = zip(baseNumbers, animatedNumbers).map(+)
        return formatNumbers(summed, template: animated)
    }

    private static func attributeStringValue(_ element: SVGElement, name: String) -> String? {
        switch name.lowercased() {
        case "height":
            if case .rect(let rect) = element { return formatNumber(Double(rect.size.height), template: "0") }
        case "width":
            if case .rect(let rect) = element { return formatNumber(Double(rect.size.width), template: "0") }
        case "x":
            if case .rect(let rect) = element { return formatNumber(Double(rect.origin.x), template: "0") }
        case "y":
            if case .rect(let rect) = element { return formatNumber(Double(rect.origin.y), template: "0") }
        default:
            break
        }
        return nil
    }

    private static func resolvedRepeatCount(_ raw: String?) -> RepeatCount {
        guard let raw else { return .finite(1) }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == "indefinite" { return .indefinite }
        if let count = Double(trimmed), count > 0 { return .finite(count) }
        return .finite(1)
    }

    private static func setIsActive(_ element: SVGSetElement, at time: Double) -> Bool {
        guard let beginTime = resolveBegin(element.timing.begin) else { return false }
        let dur = element.timing.dur ?? 0
        if time < beginTime { return false }
        if dur <= 0 {
            return element.timing.fill == .freeze && time >= beginTime
        }
        if time < beginTime + dur { return true }
        return element.timing.fill == .freeze
    }

    /// First resolvable clock value in a `begin` list; returns nil when indefinite or only event specs.
    private static func resolveBegin(_ raw: String?) -> Double? {
        guard let raw, !raw.isEmpty else { return 0 }
        let parts = raw.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        for part in parts {
            if let clock = SVGClockValue.parseSeconds(part) {
                return clock
            }
            if part.lowercased() == "indefinite" {
                return nil
            }
            if isEventSpec(part) {
                continue
            }
            if let syncbase = parseSyncbaseClock(part) {
                return syncbase
            }
        }
        return nil
    }

    private static func isEventSpec(_ part: String) -> Bool {
        let lower = part.lowercased()
        if lower == "click" || lower == "mouseover" || lower == "mouseout" || lower == "mousedown"
            || lower == "mouseup" || lower.hasSuffix(".click") || lower.hasSuffix(".mouseover")
            || lower.hasSuffix(".mouseout") {
            return true
        }
        return false
    }

    /// Minimal syncbase support: `id.begin+2s` resolved against begin=0 for unknown ids.
    private static func parseSyncbaseClock(_ part: String) -> Double? {
        guard let dot = part.firstIndex(of: ".") else { return nil }
        let offsetPart = part[part.index(after: dot)...]
        guard let plus = offsetPart.firstIndex(of: "+") else { return 0 }
        let offset = String(offsetPart[offsetPart.index(after: plus)...])
        return SVGClockValue.parseSeconds(offset) ?? 0
    }

    private static func parseValueList(_ element: SVGAnimateElement) -> [String] {
        if let values = element.values, !values.isEmpty {
            return values.split(separator: ";").map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }
        }
        var list: [String] = []
        if let from = element.from { list.append(from) }
        if let to = element.to { list.append(to) }
        return list
    }

    private static func defaultCalcMode(for element: SVGAnimateElement) -> SVGCalcMode {
        if element.attributeType?.lowercased() == "css" {
            return .linear
        }
        return isDiscreteAttribute(element.attributeName) ? .discrete : .linear
    }

    private static func isDiscreteAttribute(_ name: String) -> Bool {
        switch name.lowercased() {
        case "display", "visibility", "fill", "stroke":
            return true
        default:
            return false
        }
    }

    private static func interpolateValues(
        _ values: [String],
        progress: CGFloat,
        attributeName: String
    ) -> String {
        let clamped = max(0, min(1, progress))
        let scaled = clamped * CGFloat(values.count - 1)
        let lowerIndex = Int(floor(scaled))
        let upperIndex = min(values.count - 1, lowerIndex + 1)
        let fraction = scaled - CGFloat(lowerIndex)
        let lower = values[lowerIndex]
        let upper = values[upperIndex]
        if fraction == 0 || lowerIndex == upperIndex {
            return lower
        }
        if let lowerNumbers = parseNumbers(lower), let upperNumbers = parseNumbers(upper),
           lowerNumbers.count == upperNumbers.count, !lowerNumbers.isEmpty {
            let interpolated = zip(lowerNumbers, upperNumbers).map { lo, hi in
                lo + (hi - lo) * Double(fraction)
            }
            return formatNumbers(interpolated, template: lower)
        }
        if let lowerColor = parseColorComponents(lower), let upperColor = parseColorComponents(upper) {
            let color = SVGColor(
                red: CGFloat(lowerColor.0 + (upperColor.0 - lowerColor.0) * Double(fraction)),
                green: CGFloat(lowerColor.1 + (upperColor.1 - lowerColor.1) * Double(fraction)),
                blue: CGFloat(lowerColor.2 + (upperColor.2 - lowerColor.2) * Double(fraction)),
                alpha: CGFloat(lowerColor.3 + (upperColor.3 - lowerColor.3) * Double(fraction))
            )
            return formatColor(color, template: lower)
        }
        return fraction < 0.5 ? lower : upper
    }

    private static func parseNumbers(_ raw: String) -> [Double]? {
        let parts = raw.split(whereSeparator: { $0 == "," || $0.isWhitespace })
        let numbers = parts.compactMap { Double($0) }
        return numbers.count == parts.count ? numbers : nil
    }

    private static func formatNumbers(_ numbers: [Double], template: String) -> String {
        guard let first = numbers.first else { return template }
        if numbers.count == 1 {
            return formatNumber(first, template: template)
        }
        let separator = template.contains(",") ? "," : " "
        return numbers.map { formatNumber($0, template: template) }.joined(separator: separator)
    }

    private static func formatNumber(_ value: Double, template: String) -> String {
        if template.contains(".") {
            var formatted = String(format: "%.4f", value)
            while formatted.contains(".") && (formatted.hasSuffix("0") || formatted.hasSuffix(".")) {
                formatted.removeLast()
            }
            return formatted
        }
        if abs(value.rounded() - value) < 0.0001 {
            return String(Int(value.rounded()))
        }
        return String(value)
    }

    private static func parseColorComponents(_ raw: String) -> (Double, Double, Double, Double)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("rgb("), trimmed.hasSuffix(")") {
            let inner = trimmed.dropFirst(4).dropLast()
            let parts = inner.split(separator: ",").compactMap { parseColorComponent(String($0)) }
            guard parts.count == 3 else { return nil }
            return (parts[0], parts[1], parts[2], 1)
        }
        if trimmed.hasPrefix("#") {
            let hex = String(trimmed.dropFirst())
            if hex.count == 3 {
                let chars = Array(hex)
                guard chars.count == 3,
                      let red = hexByte("\(chars[0])\(chars[0])"),
                      let green = hexByte("\(chars[1])\(chars[1])"),
                      let blue = hexByte("\(chars[2])\(chars[2])") else {
                    return nil
                }
                return (red, green, blue, 1)
            }
            if hex.count == 6, let rgb = UInt32(hex, radix: 16) {
                return (
                    Double((rgb >> 16) & 0xFF) / 255,
                    Double((rgb >> 8) & 0xFF) / 255,
                    Double(rgb & 0xFF) / 255,
                    1
                )
            }
        }
        return nil
    }

    private static func hexByte(_ raw: String) -> Double? {
        guard let value = UInt32(raw, radix: 16) else { return nil }
        return Double(value) / 255
    }

    private static func parseColorComponent(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("%"), let value = Double(trimmed.dropLast()) {
            return value / 100
        }
        if let value = Double(trimmed) {
            return value > 1 ? value / 255 : value
        }
        return nil
    }

    private static func formatColor(_ color: SVGColor, template: String) -> String {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("rgb(") {
            let red = Int((color.red * 255).rounded())
            let green = Int((color.green * 255).rounded())
            let blue = Int((color.blue * 255).rounded())
            return "rgb(\(red),\(green),\(blue))"
        }
        if trimmed.hasPrefix("#") {
            let red = Int((color.red * 255).rounded())
            let green = Int((color.green * 255).rounded())
            let blue = Int((color.blue * 255).rounded())
            return String(format: "#%02x%02x%02x", red, green, blue)
        }
        return template
    }
}
