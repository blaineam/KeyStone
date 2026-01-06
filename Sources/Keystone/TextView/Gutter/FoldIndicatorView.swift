#if canImport(UIKit)
import UIKit

final class FoldIndicatorView: UIView, ReusableView {
    var isFolded: Bool = false {
        didSet {
            if isFolded != oldValue {
                updateAppearance()
            }
        }
    }
    var indicatorColor: UIColor = .systemGray {
        didSet {
            if indicatorColor != oldValue {
                updateAppearance()
            }
        }
    }
    var onTap: (() -> Void)?

    private let button: UIButton = {
        let btn = UIButton(type: .system)
        btn.contentMode = .center
        return btn
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        addSubview(button)
        button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        updateAppearance()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        button.frame = bounds
    }

    @objc private func buttonTapped() {
        onTap?()
    }

    private func updateAppearance() {
        let config = UIImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        let imageName = isFolded ? "chevron.right" : "chevron.down"
        let image = UIImage(systemName: imageName, withConfiguration: config)
        button.setImage(image, for: .normal)
        button.tintColor = indicatorColor
    }
}

#elseif canImport(AppKit)
import AppKit

final class FoldIndicatorView: NSView, ReusableView {
    var isFolded: Bool = false {
        didSet {
            if isFolded != oldValue {
                updateAppearance()
            }
        }
    }
    var indicatorColor: NSColor = .secondaryLabelColor {
        didSet {
            if indicatorColor != oldValue {
                updateAppearance()
            }
        }
    }
    var onTap: (() -> Void)?

    private let button: NSButton = {
        let btn = NSButton()
        btn.isBordered = false
        btn.bezelStyle = .inline
        btn.setButtonType(.momentaryChange)
        return btn
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        addSubview(button)
        button.target = self
        button.action = #selector(buttonClicked)
        updateAppearance()
    }

    override func layout() {
        super.layout()
        button.frame = bounds
    }

    @objc private func buttonClicked() {
        onTap?()
    }

    private func updateAppearance() {
        let imageName = isFolded ? "chevron.right" : "chevron.down"
        if let image = NSImage(systemSymbolName: imageName, accessibilityDescription: isFolded ? "Expand" : "Collapse") {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
            button.contentTintColor = indicatorColor
        }
    }

    func setNeedsLayout() {
        needsLayout = true
    }
}
#endif
