#if canImport(UIKit)
import UIKit

extension UIFont {
    var totalLineHeight: CGFloat {
        ascender + abs(descender) + leading
    }
}
#elseif canImport(AppKit)
import AppKit

extension NSFont {
    var totalLineHeight: CGFloat {
        ascender + abs(descender) + leading
    }
}
#endif
