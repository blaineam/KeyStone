import Foundation

enum TreeSitterPredicateMapper {
    struct MapResult {
        let properties: [String: String]
        let textPredicates: [TreeSitterTextPredicate]
    }

    static func map(_ predicates: [TreeSitterPredicate]) -> MapResult {
        var properties: [String: String] = [:]
        var textPredicates: [TreeSitterTextPredicate] = []
        for predicate in predicates {
            switch predicate.name {
            case "set!":
                if let setProperties = self.properties(fromSetSteps: predicate.steps) {
                    properties[setProperties.name] = setProperties.value
                }
            case "eq?":
                if let pred = self.textPredicate(fromEqSteps: predicate.steps, isPositive: true) {
                    textPredicates.append(pred)
                }
            case "not-eq?":
                if let pred = self.textPredicate(fromEqSteps: predicate.steps, isPositive: false) {
                    textPredicates.append(pred)
                }
            case "match?":
                if let pred = self.textPredicate(fromMatchSteps: predicate.steps, isPositive: true) {
                    textPredicates.append(pred)
                }
            case "not-match?":
                if let pred = textPredicate(fromMatchSteps: predicate.steps, isPositive: false) {
                    textPredicates.append(pred)
                }
            default:
                let parameters = TreeSitterTextPredicate.UnsupportedParameters(name: predicate.name)
                textPredicates.append(.unsupported(parameters))
            }
        }
        return MapResult(properties: properties, textPredicates: textPredicates)
    }
}

private extension TreeSitterPredicateMapper {
    private static func properties(fromSetSteps steps: [TreeSitterPredicate.Step]) -> (name: String, value: String)? {
        guard steps.count == 2 else {
            return nil
        }
        switch (steps[0], steps[1]) {
        case let (.string(name), .string(value)):
            return (name, value)
        default:
            return nil
        }
    }

    private static func textPredicate(fromEqSteps steps: [TreeSitterPredicate.Step], isPositive: Bool) -> TreeSitterTextPredicate? {
        guard steps.count == 2 else {
            return nil
        }
        switch (steps[0], steps[1]) {
        case let (.capture(captureIndex), .string(value)):
            return .captureEqualsString(.init(captureIndex: captureIndex, string: value, isPositive: isPositive))
        case let (.capture(lhsCaptureIndex), .capture(rhsCaptureIndex)):
            return .captureEqualsCapture(.init(lhsCaptureIndex: lhsCaptureIndex, rhsCaptureIndex: rhsCaptureIndex, isPositive: isPositive))
        default:
            return nil
        }
    }

    private static func textPredicate(fromMatchSteps steps: [TreeSitterPredicate.Step], isPositive: Bool) -> TreeSitterTextPredicate? {
        guard steps.count == 2 else {
            return nil
        }
        switch (steps[0], steps[1]) {
        case let (.capture(captureIndex), .string(value)):
            return .captureMatchesPattern(.init(captureIndex: captureIndex, pattern: value, isPositive: isPositive))
        default:
            return nil
        }
    }
}
