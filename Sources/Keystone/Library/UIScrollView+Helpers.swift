#if canImport(UIKit)
import UIKit

extension UIScrollView {
    var minimumContentOffset: CGPoint {
        CGPoint(x: adjustedContentInset.left * -1, y: adjustedContentInset.top * -1)
    }

    var maximumContentOffset: CGPoint {
        let maxX = max(contentSize.width - bounds.width + adjustedContentInset.right, adjustedContentInset.left * -1)
        let maxY = max(contentSize.height - bounds.height + adjustedContentInset.bottom, adjustedContentInset.top * -1)
        return CGPoint(x: maxX, y: maxY)
    }
}
#elseif canImport(AppKit)
import AppKit

extension NSScrollView {
    var minimumContentOffset: CGPoint {
        CGPoint(x: contentInsets.left * -1, y: contentInsets.top * -1)
    }

    var maximumContentOffset: CGPoint {
        let maxX = max((documentView?.frame.width ?? 0) - bounds.width + contentInsets.right, contentInsets.left * -1)
        let maxY = max((documentView?.frame.height ?? 0) - bounds.height + contentInsets.bottom, contentInsets.top * -1)
        return CGPoint(x: maxX, y: maxY)
    }
}
#endif
