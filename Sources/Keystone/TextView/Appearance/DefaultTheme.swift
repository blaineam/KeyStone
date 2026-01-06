#if canImport(UIKit)
import UIKit

/// Default theme used by Runestone when no other theme has been set.
public final class DefaultTheme: Theme {
    public let font: UIFont = .monospacedSystemFont(ofSize: 14, weight: .regular)
    public let textColor = UIColor(themeColorNamed: "foreground")
    public let gutterBackgroundColor = UIColor(themeColorNamed: "gutter_background")
    public let gutterHairlineColor = UIColor(themeColorNamed: "gutter_hairline")
    public let lineNumberColor = UIColor(themeColorNamed: "line_number")
    public let lineNumberFont: UIFont = .monospacedSystemFont(ofSize: 14, weight: .regular)
    public let selectedLineBackgroundColor = UIColor(themeColorNamed: "current_line")
    public let selectedLinesLineNumberColor = UIColor(themeColorNamed: "line_number_current_line")
    public let selectedLinesGutterBackgroundColor = UIColor(themeColorNamed: "gutter_background")
    public let invisibleCharactersColor = UIColor(themeColorNamed: "invisible_characters")
    public let pageGuideHairlineColor = UIColor(themeColorNamed: "page_guide_hairline")
    public let pageGuideBackgroundColor = UIColor(themeColorNamed: "page_guide_background")
    public let markedTextBackgroundColor = UIColor(themeColorNamed: "marked_text")
    public let selectionColor = UIColor(themeColorNamed: "selection")

    public init() {}

    // swiftlint:disable:next cyclomatic_complexity
    public func textColor(for highlightName: String) -> UIColor? {
        guard let highlightName = HighlightName(highlightName) else {
            return nil
        }
        switch highlightName {
        case .comment:
            return UIColor(themeColorNamed: "comment")
        case .constantBuiltin:
            return UIColor(themeColorNamed: "constant_builtin")
        case .constantCharacter:
            return UIColor(themeColorNamed: "constant_character")
        case .constructor:
            return UIColor(themeColorNamed: "constructor")
        case .function:
            return UIColor(themeColorNamed: "function")
        case .keyword:
            return UIColor(themeColorNamed: "keyword")
        case .number:
            return UIColor(themeColorNamed: "number")
        case .property:
            return UIColor(themeColorNamed: "property")
        case .string:
            return UIColor(themeColorNamed: "string")
        case .type:
            return UIColor(themeColorNamed: "type")
        case .variable:
            return nil
        case .variableBuiltin:
            return UIColor(themeColorNamed: "variable_builtin")
        case .operator:
            return UIColor(themeColorNamed: "operator")
        case .punctuation:
            return UIColor(themeColorNamed: "punctuation")
        }
    }

    public func fontTraits(for highlightName: String) -> FontTraits {
        guard let highlightName = HighlightName(highlightName) else {
            return []
        }
        if highlightName == .keyword {
            return .bold
        } else {
            return []
        }
    }

    @available(iOS 16.0, *)
    public func highlightedRange(forFoundTextRange foundTextRange: NSRange, ofStyle style: UITextSearchFoundTextStyle) -> HighlightedRange? {
        switch style {
        case .found:
            let color = UIColor(themeColorNamed: "search_match_found")
            return HighlightedRange(range: foundTextRange, color: color, cornerRadius: 2)
        case .highlighted:
            let color = UIColor(themeColorNamed: "search_match_highlighted")
            return HighlightedRange(range: foundTextRange, color: color, cornerRadius: 2)
        case .normal:
            return nil
        @unknown default:
            return nil
        }
    }
}

private extension UIColor {
    convenience init(themeColorNamed name: String) {
        self.init(named: "theme_" + name, in: .module, compatibleWith: nil)!
    }
}

#elseif canImport(AppKit)
import AppKit

/// Default theme used by Runestone when no other theme has been set.
public final class DefaultTheme: Theme {
    public let font: NSFont = .monospacedSystemFont(ofSize: 14, weight: .regular)
    public let textColor = NSColor(themeColorNamed: "foreground")
    public let gutterBackgroundColor = NSColor(themeColorNamed: "gutter_background")
    public let gutterHairlineColor = NSColor(themeColorNamed: "gutter_hairline")
    public let lineNumberColor = NSColor(themeColorNamed: "line_number")
    public let lineNumberFont: NSFont = .monospacedSystemFont(ofSize: 14, weight: .regular)
    public let selectedLineBackgroundColor = NSColor(themeColorNamed: "current_line")
    public let selectedLinesLineNumberColor = NSColor(themeColorNamed: "line_number_current_line")
    public let selectedLinesGutterBackgroundColor = NSColor(themeColorNamed: "gutter_background")
    public let invisibleCharactersColor = NSColor(themeColorNamed: "invisible_characters")
    public let pageGuideHairlineColor = NSColor(themeColorNamed: "page_guide_hairline")
    public let pageGuideBackgroundColor = NSColor(themeColorNamed: "page_guide_background")
    public let markedTextBackgroundColor = NSColor(themeColorNamed: "marked_text")
    public let selectionColor = NSColor(themeColorNamed: "selection")

    public init() {}

    // swiftlint:disable:next cyclomatic_complexity
    public func textColor(for highlightName: String) -> NSColor? {
        guard let highlightName = HighlightName(highlightName) else {
            return nil
        }
        switch highlightName {
        case .comment:
            return NSColor(themeColorNamed: "comment")
        case .constantBuiltin:
            return NSColor(themeColorNamed: "constant_builtin")
        case .constantCharacter:
            return NSColor(themeColorNamed: "constant_character")
        case .constructor:
            return NSColor(themeColorNamed: "constructor")
        case .function:
            return NSColor(themeColorNamed: "function")
        case .keyword:
            return NSColor(themeColorNamed: "keyword")
        case .number:
            return NSColor(themeColorNamed: "number")
        case .property:
            return NSColor(themeColorNamed: "property")
        case .string:
            return NSColor(themeColorNamed: "string")
        case .type:
            return NSColor(themeColorNamed: "type")
        case .variable:
            return nil
        case .variableBuiltin:
            return NSColor(themeColorNamed: "variable_builtin")
        case .operator:
            return NSColor(themeColorNamed: "operator")
        case .punctuation:
            return NSColor(themeColorNamed: "punctuation")
        }
    }

    public func fontTraits(for highlightName: String) -> FontTraits {
        guard let highlightName = HighlightName(highlightName) else {
            return []
        }
        if highlightName == .keyword {
            return .bold
        } else {
            return []
        }
    }
}

private extension NSColor {
    convenience init(themeColorNamed name: String) {
        if let color = NSColor(named: "theme_" + name, bundle: .module) {
            self.init(cgColor: color.cgColor)!
        } else {
            self.init(white: 0.5, alpha: 1.0)
        }
    }
}
#endif
