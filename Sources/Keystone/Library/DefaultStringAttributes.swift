import Foundation
#if canImport(UIKit)
import UIKit

struct DefaultStringAttributes {
    let textColor: UIColor
    let font: UIFont
    let kern: CGFloat
    let tabWidth: CGFloat

    func apply(to attributedString: NSMutableAttributedString) {
        let paragraphStyle = DefaultStringAttributes.paragraphStyle(tabWidth: tabWidth)
        let range = NSRange(location: 0, length: attributedString.length)
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: textColor,
            .font: font,
            .kern: kern as NSNumber,
            .paragraphStyle: paragraphStyle
        ]
        attributedString.beginEditing()
        attributedString.setAttributes(attributes, range: range)
        attributedString.endEditing()
    }
}

#elseif canImport(AppKit)
import AppKit

struct DefaultStringAttributes {
    let textColor: NSColor
    let font: NSFont
    let kern: CGFloat
    let tabWidth: CGFloat

    func apply(to attributedString: NSMutableAttributedString) {
        let paragraphStyle = DefaultStringAttributes.paragraphStyle(tabWidth: tabWidth)
        let range = NSRange(location: 0, length: attributedString.length)
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: textColor,
            .font: font,
            .kern: kern as NSNumber,
            .paragraphStyle: paragraphStyle
        ]
        attributedString.beginEditing()
        attributedString.setAttributes(attributes, range: range)
        attributedString.endEditing()
    }
}
#endif

extension DefaultStringAttributes {
    /// Paragraph styles by tab width. Building 20 `NSTextTab`s per application showed up
    /// when a long line's chunk is rebuilt on every keystroke; the style is immutable once made.
    nonisolated(unsafe) private static var paragraphStyles: [CGFloat: NSParagraphStyle] = [:]
    private static let paragraphStylesLock = NSLock()

    static func paragraphStyle(tabWidth: CGFloat) -> NSParagraphStyle {
        paragraphStylesLock.lock()
        defer { paragraphStylesLock.unlock() }
        if let style = paragraphStyles[tabWidth] {
            return style
        }
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.tabStops = (0 ..< 20).map { index in
            NSTextTab(textAlignment: .natural, location: CGFloat(index) * tabWidth)
        }
        paragraphStyle.defaultTabInterval = tabWidth
        // swiftlint:disable:next force_cast
        let style = paragraphStyle.copy() as! NSParagraphStyle
        if paragraphStyles.count > 32 {
            paragraphStyles.removeAll()
        }
        paragraphStyles[tabWidth] = style
        return style
    }
}
