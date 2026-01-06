#if canImport(UIKit)
import UIKit
public typealias ThemeFont = UIFont
public typealias ThemeColor = UIColor
#elseif canImport(AppKit)
import AppKit
public typealias ThemeFont = NSFont
public typealias ThemeColor = NSColor
#endif

/// Fonts and colors to be used by a `TextView`.
public protocol Theme: AnyObject {
    /// Default font of text in the text view.
    var font: ThemeFont { get }
    /// Default color of text in the text view.
    var textColor: ThemeColor { get }
    /// Background color of the gutter containing line numbers.
    var gutterBackgroundColor: ThemeColor { get }
    /// Color of the hairline next to the gutter containing line numbers.
    var gutterHairlineColor: ThemeColor { get }
    /// Width of the hairline next to the gutter containing line numbers.
    var gutterHairlineWidth: CGFloat { get }
    /// Color of the line numbers in the gutter.
    var lineNumberColor: ThemeColor { get }
    /// Font of the line nubmers in the gutter.
    var lineNumberFont: ThemeFont { get }
    /// Background color of the selected line.
    var selectedLineBackgroundColor: ThemeColor { get }
    /// Color of the line number of the selected line.
    var selectedLinesLineNumberColor: ThemeColor { get }
    /// Background color of the gutter for selected lines.
    var selectedLinesGutterBackgroundColor: ThemeColor { get }
    /// Color of invisible characters, i.e. dots, spaces and line breaks.
    var invisibleCharactersColor: ThemeColor { get }
    /// Color of the hairline next to the page guide.
    var pageGuideHairlineColor: ThemeColor { get }
    /// Width of the hairline next to the page guide.
    var pageGuideHairlineWidth: CGFloat { get }
    /// Background color of the page guide.
    var pageGuideBackgroundColor: ThemeColor { get }
    /// Background color of marked text. Text will be marked when writing certain languages, for example Chinese and Japanese.
    var markedTextBackgroundColor: ThemeColor { get }
    /// Corner radius of the background of marked text. Text will be marked when writing certain languages, for example Chinese and Japanese.
    /// A value of zero or less means that the background will not have rounded corners. Defaults to 0.
    var markedTextBackgroundCornerRadius: CGFloat { get }
    /// Color of text matching the capture sequence.
    ///
    /// See <doc:CreatingATheme> for more information on higlight names.
    func textColor(for highlightName: String) -> ThemeColor?
    /// Font of text matching the capture sequence.
    ///
    /// See <doc:CreatingATheme> for more information on higlight names.
    func font(for highlightName: String) -> ThemeFont?
    /// Traits of text matching the capture sequence.
    ///
    /// See <doc:CreatingATheme> for more information on higlight names.
    func fontTraits(for highlightName: String) -> FontTraits
    /// Shadow of text matching the capture sequence.
    ///
    /// See <doc:CreatingATheme> for more information on higlight names.
    func shadow(for highlightName: String) -> NSShadow?
    /// Highlighted range for a text range matching a search query.
    ///
    /// This function is called when highlighting a search result that was found using the standard find/replace interaction enabled using <doc:TextView/isFindInteractionEnabled>.
    ///
    /// Return `nil` to prevent highlighting the range.
    /// - Parameters:
    ///   - foundTextRange: The text range matching a search query.
    ///   - style: Style used to decorate the text.
    /// - Returns: The object used for highlighting the provided text range, or `nil` if the range should not be highlighted.
    #if canImport(UIKit)
    @available(iOS 16, *)
    func highlightedRange(forFoundTextRange foundTextRange: NSRange, ofStyle style: UITextSearchFoundTextStyle) -> HighlightedRange?
    #endif
}

public extension Theme {
    var gutterHairlineWidth: CGFloat {
        hairlineLength
    }

    var pageGuideHairlineWidth: CGFloat {
        hairlineLength
    }

    var markedTextBackgroundCornerRadius: CGFloat {
        0
    }

    func font(for highlightName: String) -> ThemeFont? {
        nil
    }

    func fontTraits(for highlightName: String) -> FontTraits {
        []
    }

    func shadow(for highlightName: String) -> NSShadow? {
        nil
    }

    #if canImport(UIKit)
    @available(iOS 16, *)
    func highlightedRange(forFoundTextRange foundTextRange: NSRange, ofStyle style: UITextSearchFoundTextStyle) -> HighlightedRange? {
        switch style {
        case .found:
            return HighlightedRange(range: foundTextRange, color: .systemYellow.withAlphaComponent(0.2))
        case .highlighted:
            return HighlightedRange(range: foundTextRange, color: .systemYellow)
        case .normal:
            return nil
        @unknown default:
            return nil
        }
    }
    #endif
}
