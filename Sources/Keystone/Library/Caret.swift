#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum Caret {
    static let width: CGFloat = 2

    #if canImport(UIKit)
    static func defaultHeight(for font: UIFont?) -> CGFloat {
        font?.lineHeight ?? 15
    }
    #elseif canImport(AppKit)
    static func defaultHeight(for font: NSFont?) -> CGFloat {
        font?.lineHeight ?? 15
    }
    #endif
}
