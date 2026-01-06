#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class GutterBackgroundView: RSBaseView {
    var hairlineWidth: CGFloat = 1 {
        didSet {
            if hairlineWidth != oldValue {
                setNeedsLayout()
            }
        }
    }
    var hairlineColor: RunestoneColor? {
        get {
            hairlineView.backgroundColor
        }
        set {
            hairlineView.backgroundColor = newValue
        }
    }

    private let hairlineView = RSBaseView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(hairlineView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func performLayout() {
        hairlineView.frame = CGRect(x: bounds.width - hairlineWidth, y: 0, width: hairlineWidth, height: bounds.height)
    }
}
