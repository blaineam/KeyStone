#if canImport(UIKit)
import UIKit

final class PageGuideView: UIView {
    var hairlineWidth: CGFloat {
        didSet {
            if hairlineWidth != oldValue {
                setNeedsLayout()
            }
        }
    }
    var hairlineColor: UIColor? {
        get {
            hairlineView.backgroundColor
        }
        set {
            hairlineView.backgroundColor = newValue
        }
    }

    private let hairlineView = UIView()

    override init(frame: CGRect) {
        self.hairlineWidth = hairlineLength
        super.init(frame: frame)
        isUserInteractionEnabled = false
        hairlineView.isUserInteractionEnabled = false
        addSubview(hairlineView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hairlineView.frame = CGRect(x: 0, y: 0, width: hairlineWidth, height: bounds.height)
    }
}

#elseif canImport(AppKit)
import AppKit

final class PageGuideView: NSView {
    var hairlineWidth: CGFloat {
        didSet {
            if hairlineWidth != oldValue {
                needsLayout = true
            }
        }
    }
    var hairlineColor: NSColor? {
        get {
            guard let cgColor = hairlineView.layer?.backgroundColor else { return nil }
            return NSColor(cgColor: cgColor)
        }
        set {
            hairlineView.wantsLayer = true
            hairlineView.layer?.backgroundColor = newValue?.cgColor
        }
    }

    private let hairlineView = NSView()

    override init(frame: CGRect) {
        self.hairlineWidth = hairlineLength
        super.init(frame: frame)
        addSubview(hairlineView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        hairlineView.frame = CGRect(x: 0, y: 0, width: hairlineWidth, height: bounds.height)
    }
}
#endif
