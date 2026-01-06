#if canImport(UIKit)
import UIKit

final class IndexedRange: UITextRange {
    let range: NSRange
    override var start: UITextPosition {
        IndexedPosition(index: range.location)
    }
    override var end: UITextPosition {
        IndexedPosition(index: range.location + range.length)
    }
    override var isEmpty: Bool {
        range.length == 0
    }

    init(_ range: NSRange) {
        self.range = range
    }

    convenience init(location: Int, length: Int) {
        let range = NSRange(location: location, length: length)
        self.init(range)
    }
}
#elseif canImport(AppKit)
import AppKit

/// macOS equivalent of UITextRange with an NSRange
final class IndexedRange: NSObject {
    let range: NSRange
    var start: IndexedPosition {
        IndexedPosition(index: range.location)
    }
    var end: IndexedPosition {
        IndexedPosition(index: range.location + range.length)
    }
    var isEmpty: Bool {
        range.length == 0
    }

    init(_ range: NSRange) {
        self.range = range
        super.init()
    }

    convenience init(location: Int, length: Int) {
        let range = NSRange(location: location, length: length)
        self.init(range)
    }
}
#endif
