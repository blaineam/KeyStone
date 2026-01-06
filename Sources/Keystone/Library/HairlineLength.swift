#if canImport(UIKit)
import UIKit

#if compiler(<5.9) || !os(visionOS)
let hairlineLength = 1 / UIScreen.main.scale
#else
let hairlineLength: CGFloat = 1
#endif

#elseif canImport(AppKit)
import AppKit

let hairlineLength: CGFloat = {
    if let screen = NSScreen.main {
        return 1 / screen.backingScaleFactor
    }
    return 1
}()
#endif
