#if canImport(UIKit)
import UIKit

final class LineNumberView: UIView, ReusableView {
    var textColor: UIColor {
        get { titleLabel.textColor }
        set { titleLabel.textColor = newValue }
    }
    var font: UIFont {
        get { titleLabel.font ?? .systemFont(ofSize: 14) }
        set { titleLabel.font = newValue }
    }
    var text: String? {
        get { titleLabel.text }
        set { titleLabel.text = newValue }
    }

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .right
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(titleLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = titleLabel.intrinsicContentSize
        titleLabel.frame = CGRect(x: 0, y: 0, width: bounds.width, height: size.height)
    }
}

#elseif canImport(AppKit)
import AppKit

final class LineNumberView: NSView, ReusableView {
    override var isFlipped: Bool { true }

    var textColor: NSColor {
        get { titleLabel.textColor ?? .textColor }
        set { titleLabel.textColor = newValue }
    }
    var font: NSFont {
        get { titleLabel.font ?? .systemFont(ofSize: 14) }
        set { titleLabel.font = newValue }
    }
    var text: String? {
        get { titleLabel.stringValue.isEmpty ? nil : titleLabel.stringValue }
        set { titleLabel.stringValue = newValue ?? "" }
    }

    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.alignment = .right
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        addSubview(titleLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let size = titleLabel.intrinsicContentSize
        titleLabel.frame = CGRect(x: 0, y: 0, width: bounds.width, height: size.height)
    }

    func setNeedsLayout() {
        needsLayout = true
    }
}
#endif
