//
//  PlatformKit.swift
//  Runestone
//
//  Unified cross-platform imports and type aliases for UIKit/AppKit compatibility.
//  Import this file instead of UIKit/AppKit for cross-platform code.
//

import Foundation
import CoreGraphics
import CoreText

// MARK: - Platform Detection

#if os(iOS) || os(tvOS)
public let isRunningOniOS = true
public let isRunningOnMacOS = false
#elseif os(macOS)
public let isRunningOniOS = false
public let isRunningOnMacOS = true
#endif

// MARK: - UIKit Platform

#if canImport(UIKit)
import UIKit

// Type aliases for cross-platform compatibility
public typealias RunestoneView = UIView
public typealias RunestoneScrollView = UIScrollView
public typealias RunestoneColor = UIColor
public typealias RunestoneFont = UIFont
public typealias RunestoneImage = UIImage
public typealias RunestoneBezierPath = UIBezierPath
public typealias RunestoneEdgeInsets = UIEdgeInsets
public typealias RunestoneLayoutPriority = UILayoutPriority
public typealias RunestoneApplication = UIApplication
public typealias RunestoneResponder = UIResponder
public typealias RunestonePasteboard = UIPasteboard

// Gesture recognizers
public typealias RunestoneGestureRecognizer = UIGestureRecognizer
public typealias RunestoneTapGestureRecognizer = UITapGestureRecognizer
public typealias RunestonePanGestureRecognizer = UIPanGestureRecognizer
public typealias RunestoneLongPressGestureRecognizer = UILongPressGestureRecognizer

// Text input types - these are iOS-specific
public typealias RunestoneTextPosition = UITextPosition
public typealias RunestoneTextRange = UITextRange
public typealias RunestoneTextInput = UITextInput
public typealias RunestoneTextLayoutDirection = UITextLayoutDirection
public typealias RunestoneTextStorageDirection = UITextStorageDirection
public typealias RunestoneTextSelectionRect = UITextSelectionRect

// Extensions
extension UIColor {
    public static var runestoneText: UIColor { .label }
    public static var runestoneBackground: UIColor { .systemBackground }
    public static var runestoneSecondaryLabel: UIColor { .secondaryLabel }
    public static var runestoneSeparator: UIColor { .separator }
}

extension UIView {
    public func runestoneSetNeedsDisplay() { setNeedsDisplay() }
    public func runestoneSetNeedsLayout() { setNeedsLayout() }
    public func runestoneLayoutIfNeeded() { layoutIfNeeded() }
}

extension UIScrollView {
    public var runestoneContentOffset: CGPoint {
        get { contentOffset }
        set { contentOffset = newValue }
    }
    public var runestoneContentSize: CGSize {
        get { contentSize }
        set { contentSize = newValue }
    }
}

// MARK: - AppKit Platform

#elseif canImport(AppKit)
import AppKit

// Type aliases for cross-platform compatibility
public typealias RunestoneView = NSView
public typealias RunestoneScrollView = NSScrollView
public typealias RunestoneColor = NSColor
public typealias RunestoneFont = NSFont
public typealias RunestoneImage = NSImage
public typealias RunestoneBezierPath = NSBezierPath
public typealias RunestoneEdgeInsets = NSEdgeInsets
public typealias RunestoneLayoutPriority = NSLayoutConstraint.Priority
public typealias RunestoneApplication = NSApplication
public typealias RunestoneResponder = NSResponder
public typealias RunestonePasteboard = NSPasteboard

// Gesture recognizers
public typealias RunestoneGestureRecognizer = NSGestureRecognizer
public typealias RunestoneTapGestureRecognizer = NSClickGestureRecognizer
public typealias RunestonePanGestureRecognizer = NSPanGestureRecognizer
public typealias RunestoneLongPressGestureRecognizer = NSPressGestureRecognizer

// Text input types - macOS uses different types, we'll create abstractions
// These are defined in TextInputAbstraction.swift

// Extensions
extension NSColor {
    public static var runestoneText: NSColor { .textColor }
    public static var runestoneBackground: NSColor { .textBackgroundColor }
    public static var runestoneSecondaryLabel: NSColor { .secondaryLabelColor }
    public static var runestoneSeparator: NSColor { .separatorColor }
}

extension NSView {
    public var alpha: CGFloat {
        get { alphaValue }
        set { alphaValue = newValue }
    }

    public var backgroundColor: NSColor? {
        get {
            guard let layer = layer, let cgColor = layer.backgroundColor else { return nil }
            return NSColor(cgColor: cgColor)
        }
        set {
            wantsLayer = true
            layer?.backgroundColor = newValue?.cgColor
        }
    }

    public func runestoneSetNeedsDisplay() { needsDisplay = true }
    public func runestoneSetNeedsLayout() { needsLayout = true }
    public func runestoneLayoutIfNeeded() { layoutSubtreeIfNeeded() }
}

extension NSScrollView {
    public var runestoneContentOffset: CGPoint {
        get { contentView.bounds.origin }
        set { contentView.scroll(to: newValue) }
    }
    public var runestoneContentSize: CGSize {
        get { documentView?.frame.size ?? .zero }
        set { documentView?.setFrameSize(newValue) }
    }
}

// NSFont.lineHeight is defined in PlatformImports.swift

extension NSEdgeInsets {
    public static var zero: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
}

extension NSBezierPath {
    public var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo: path.move(to: points[0])
            case .lineTo: path.addLine(to: points[0])
            case .curveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath()
            case .cubicCurveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo: path.addQuadCurve(to: points[1], control: points[0])
            @unknown default: break
            }
        }
        return path
    }

    public func addLine(to point: CGPoint) { line(to: point) }
    public func addCurve(to endPoint: CGPoint, controlPoint1: CGPoint, controlPoint2: CGPoint) {
        curve(to: endPoint, controlPoint1: controlPoint1, controlPoint2: controlPoint2)
    }
}

#endif

// MARK: - Cross-Platform Utilities

/// Helper to run platform-specific code
public func runOnMainThread(_ block: @escaping () -> Void) {
    if Thread.isMainThread {
        block()
    } else {
        DispatchQueue.main.async(execute: block)
    }
}

// MARK: - Cross-Platform View Base Class

#if canImport(UIKit)
import UIKit

/// Base view class with cross-platform layout method naming
open class RSBaseView: UIView {
    /// Cross-platform layout method - override this in subclasses
    open func performLayout() {
        // Override in subclasses
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        performLayout()
    }
}

/// Cross-platform label using UILabel on iOS
public typealias RSLabel = UILabel

#elseif canImport(AppKit)
import AppKit

/// Base view class with cross-platform layout method naming
open class RSBaseView: NSView {
    /// Use flipped coordinates (origin at top-left like iOS)
    open override var isFlipped: Bool { true }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Cross-platform layout method - override this in subclasses
    open func performLayout() {
        // Override in subclasses
    }

    open override func layout() {
        super.layout()
        performLayout()
    }

    /// UIView compatibility
    public func setNeedsLayout() {
        needsLayout = true
    }

    /// UIView compatibility
    public func setNeedsDisplay() {
        needsDisplay = true
    }
}

/// Cross-platform label using NSTextField on macOS
public class RSLabel: NSTextField {
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBezeled = false
        drawsBackground = false
        isEditable = false
        isSelectable = false
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// UILabel compatibility - text property
    public var text: String? {
        get { stringValue.isEmpty ? nil : stringValue }
        set { stringValue = newValue ?? "" }
    }

    /// UILabel compatibility - font property (uses the inherited font)
}

#endif
