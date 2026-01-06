#if canImport(UIKit)
import UIKit

final class IndexedPosition: UITextPosition {
    let index: Int

    init(index: Int) {
        self.index = index
    }
}
#elseif canImport(AppKit)
import AppKit

/// macOS equivalent of UITextPosition with an index
final class IndexedPosition: NSObject {
    let index: Int

    init(index: Int) {
        self.index = index
        super.init()
    }
}
#endif
