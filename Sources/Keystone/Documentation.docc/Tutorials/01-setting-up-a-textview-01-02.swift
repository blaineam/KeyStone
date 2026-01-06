#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "TextCompanion"
    }
}
