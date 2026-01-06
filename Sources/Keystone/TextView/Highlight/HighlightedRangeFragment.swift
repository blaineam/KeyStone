#if canImport(UIKit)
import UIKit

final class HighlightedRangeFragment: Equatable {
    let range: NSRange
    let containsStart: Bool
    let containsEnd: Bool
    let color: RunestoneColor
    let cornerRadius: CGFloat
    var roundedCorners: UIRectCorner {
        if containsStart && containsEnd {
            return .allCorners
        } else if containsStart {
            return [.topLeft, .bottomLeft]
        } else if containsEnd {
            return [.topRight, .bottomRight]
        } else {
            return []
        }
    }

    init(range: NSRange, containsStart: Bool, containsEnd: Bool, color: RunestoneColor, cornerRadius: CGFloat) {
        self.range = range
        self.containsStart = containsStart
        self.containsEnd = containsEnd
        self.color = color
        self.cornerRadius = cornerRadius
    }
}

extension HighlightedRangeFragment {
    static func == (lhs: HighlightedRangeFragment, rhs: HighlightedRangeFragment) -> Bool {
        lhs.range == rhs.range
        && lhs.containsStart == rhs.containsStart
        && lhs.containsEnd == rhs.containsEnd
        && lhs.color == rhs.color
        && lhs.cornerRadius == rhs.cornerRadius
    }
}

#elseif canImport(AppKit)
import AppKit

/// Represents which corners should be rounded
struct RSRectCorner: OptionSet {
    let rawValue: Int
    static let topLeft = RSRectCorner(rawValue: 1 << 0)
    static let topRight = RSRectCorner(rawValue: 1 << 1)
    static let bottomLeft = RSRectCorner(rawValue: 1 << 2)
    static let bottomRight = RSRectCorner(rawValue: 1 << 3)
    static let allCorners: RSRectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

final class HighlightedRangeFragment: Equatable {
    let range: NSRange
    let containsStart: Bool
    let containsEnd: Bool
    let color: RunestoneColor
    let cornerRadius: CGFloat
    var roundedCorners: RSRectCorner {
        if containsStart && containsEnd {
            return .allCorners
        } else if containsStart {
            return [.topLeft, .bottomLeft]
        } else if containsEnd {
            return [.topRight, .bottomRight]
        } else {
            return []
        }
    }

    init(range: NSRange, containsStart: Bool, containsEnd: Bool, color: RunestoneColor, cornerRadius: CGFloat) {
        self.range = range
        self.containsStart = containsStart
        self.containsEnd = containsEnd
        self.color = color
        self.cornerRadius = cornerRadius
    }
}

extension HighlightedRangeFragment {
    static func == (lhs: HighlightedRangeFragment, rhs: HighlightedRangeFragment) -> Bool {
        lhs.range == rhs.range
        && lhs.containsStart == rhs.containsStart
        && lhs.containsEnd == rhs.containsEnd
        && lhs.color == rhs.color
        && lhs.cornerRadius == rhs.cornerRadius
    }
}
#endif
