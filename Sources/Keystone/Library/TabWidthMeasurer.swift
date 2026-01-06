#if canImport(UIKit)
import UIKit
typealias MeasurerFont = UIFont
#elseif canImport(AppKit)
import AppKit
typealias MeasurerFont = NSFont
#endif

enum TabWidthMeasurer {
    static func tabWidth(tabLength: Int, font: MeasurerFont) -> CGFloat {
        let str = String(repeating: " ", count: tabLength)
        let maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        #if canImport(UIKit)
        let options: NSStringDrawingOptions = [.usesFontLeading, .usesLineFragmentOrigin]
        #else
        let options: NSString.DrawingOptions = [.usesFontLeading, .usesLineFragmentOrigin]
        #endif
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let bounds = str.boundingRect(with: maxSize, options: options, attributes: attributes, context: nil)
        return round(bounds.size.width)
    }
}
