import Foundation
import SVGCore

enum AnimationAttributeParser {
    static func timedAnimation(
        elementName: String,
        attributes: [String: String]
    ) -> SVGTimedAnimation? {
        switch elementName {
        case "animate":
            guard let attributeName = attributes["attributeName"], !attributeName.isEmpty else {
                return nil
            }
            return .animate(SVGAnimateElement(
                id: attributes["id"],
                timing: timingAttributes(from: attributes),
                attributeName: attributeName,
                attributeType: attributes["attributeType"],
                from: attributes["from"],
                to: attributes["to"],
                values: attributes["values"],
                calcMode: attributes["calcMode"].flatMap(SVGCalcMode.init(rawValue:)),
                additive: attributes["additive"],
                accumulate: attributes["accumulate"]
            ))
        case "set":
            guard let attributeName = attributes["attributeName"], !attributeName.isEmpty,
                  let to = attributes["to"] else {
                return nil
            }
            return .set(SVGSetElement(
                id: attributes["id"],
                timing: timingAttributes(from: attributes),
                attributeName: attributeName,
                to: to
            ))
        case "animateTransform":
            guard let typeRaw = attributes["type"],
                  let type = SVGAnimateTransformType(rawValue: typeRaw) else {
                return nil
            }
            return .animateTransform(SVGAnimateTransformElement(
                id: attributes["id"],
                timing: timingAttributes(from: attributes),
                type: type,
                from: attributes["from"],
                to: attributes["to"],
                values: attributes["values"],
                additive: attributes["additive"],
                accumulate: attributes["accumulate"]
            ))
        case "animateMotion":
            return .animateMotion(SVGAnimateMotionElement(
                id: attributes["id"],
                timing: timingAttributes(from: attributes),
                path: attributes["path"],
                from: attributes["from"],
                to: attributes["to"],
                values: attributes["values"],
                rotate: attributes["rotate"],
                mpathHref: attributes["xlink:href"] ?? attributes["href"]
            ))
        default:
            return nil
        }
    }

    private static func timingAttributes(from attributes: [String: String]) -> SVGTimingAttributes {
        let fill: SVGTimingFill = {
            guard let raw = attributes["fill"]?.lowercased() else { return .remove }
            return SVGTimingFill(rawValue: raw) ?? .remove
        }()
        return SVGTimingAttributes(
            begin: attributes["begin"],
            dur: attributes["dur"].flatMap(SVGClockValue.parseSeconds),
            end: attributes["end"],
            repeatCount: attributes["repeatCount"],
            fill: fill
        )
    }
}
