#if canImport(UIKit)
import UIKit

final class LineFragmentView: UIView, ReusableView {
    var renderer: LineFragmentRenderer? {
        didSet {
            if renderer !== oldValue {
                setNeedsDisplay()
            }
        }
    }
    override var frame: CGRect {
        didSet {
            if frame.size != oldValue.size {
                setNeedsDisplay()
            }
        }
    }

    private var isRenderInvalid = true

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        if let context = UIGraphicsGetCurrentContext() {
            renderer?.draw(to: context, inCanvasOfSize: bounds.size)
        }
    }

    func prepareForReuse() {
        renderer = nil
    }
}

#elseif canImport(AppKit)
import AppKit

final class LineFragmentView: NSView, ReusableView {
    var renderer: LineFragmentRenderer? {
        didSet {
            if renderer !== oldValue {
                needsDisplay = true
            }
        }
    }
    override var frame: CGRect {
        didSet {
            if frame.size != oldValue.size {
                needsDisplay = true
            }
        }
    }

    private var isRenderInvalid = true

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let context = NSGraphicsContext.current?.cgContext {
            renderer?.draw(to: context, inCanvasOfSize: bounds.size)
        }
    }

    // NSView has prepareForReuse() on macOS 12+
    override func prepareForReuse() {
        renderer = nil
    }

    func setNeedsLayout() {
        needsLayout = true
    }

    // UIView-compatible setNeedsDisplay() with no arguments
    func setNeedsDisplay() {
        needsDisplay = true
    }
}
#endif
