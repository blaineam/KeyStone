import Runestone
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

class TomorrowTheme: Theme {
    let font: UIFont = .monospacedSystemFont(ofSize: 14, weight: .regular)
    let lineNumberFont: UIFont = .monospacedSystemFont(ofSize: 14, weight: .regular)
}
