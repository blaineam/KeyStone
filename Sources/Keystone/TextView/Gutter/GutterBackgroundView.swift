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

    /// Change markers for the visible lines, in this view's coordinates.
    var changeMarkerRects: [(rect: CGRect, color: RunestoneColor)] = [] {
        didSet {
            if changeMarkerRects.map(\.rect) != oldValue.map(\.rect) || changeMarkerRects.map(\.color) != oldValue.map(\.color) {
                #if canImport(UIKit)
                setNeedsDisplay()
                #else
                needsDisplay = true
                #endif
            }
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

    override func draw(_ dirtyRect: CGRect) {
        super.draw(dirtyRect)
        guard !changeMarkerRects.isEmpty else { return }
        #if canImport(UIKit)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        #else
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        #endif
        for marker in changeMarkerRects where marker.rect.intersects(dirtyRect) {
            context.setFillColor(marker.color.cgColor)
            context.fill(marker.rect)
        }
    }
}
