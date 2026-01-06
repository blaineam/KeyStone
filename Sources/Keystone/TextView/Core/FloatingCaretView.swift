#if canImport(UIKit)
import UIKit

final class FloatingCaretView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = floor(bounds.width / 2)
    }
}
#elseif canImport(AppKit)
import AppKit

final class FloatingCaretView: NSView {
    override func layout() {
        super.layout()
        wantsLayer = true
        layer?.cornerRadius = floor(bounds.width / 2)
    }
}
#endif
