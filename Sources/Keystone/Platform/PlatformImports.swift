//
//  PlatformImports.swift
//  Runestone
//
//  Cross-platform type aliases for UIKit/AppKit compatibility.
//

import Foundation
import CoreGraphics
import CoreText

#if canImport(UIKit)
import UIKit

// MARK: - Type Aliases (iOS/Catalyst)

public typealias PlatformView = UIView
public typealias PlatformScrollView = UIScrollView
public typealias PlatformColor = UIColor
public typealias PlatformFont = UIFont
public typealias PlatformImage = UIImage
public typealias PlatformBezierPath = UIBezierPath
public typealias PlatformEdgeInsets = UIEdgeInsets
public typealias PlatformGestureRecognizer = UIGestureRecognizer
public typealias PlatformTapGestureRecognizer = UITapGestureRecognizer
public typealias PlatformPanGestureRecognizer = UIPanGestureRecognizer
public typealias PlatformLongPressGestureRecognizer = UILongPressGestureRecognizer
public typealias PlatformPasteboard = UIPasteboard
public typealias PlatformApplication = UIApplication

// MARK: - Extensions for Compatibility

extension UIView {
    var platformBackgroundColor: UIColor? {
        get { backgroundColor }
        set { backgroundColor = newValue }
    }

    func platformSetNeedsDisplay() {
        setNeedsDisplay()
    }

    func platformSetNeedsLayout() {
        setNeedsLayout()
    }

    func platformLayoutIfNeeded() {
        layoutIfNeeded()
    }
}

extension UIScrollView {
    var platformContentOffset: CGPoint {
        get { contentOffset }
        set { contentOffset = newValue }
    }

    var platformContentSize: CGSize {
        get { contentSize }
        set { contentSize = newValue }
    }

    var platformContentInset: UIEdgeInsets {
        get { contentInset }
        set { contentInset = newValue }
    }
}

extension UIColor {
    static var platformTextColor: UIColor {
        .label
    }

    static var platformBackgroundColor: UIColor {
        .systemBackground
    }

    static var platformSecondaryLabelColor: UIColor {
        .secondaryLabel
    }
}

extension UIFont {
    static func platformMonospacedSystemFont(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// Line height is native on UIFont
    var platformLineHeight: CGFloat {
        lineHeight
    }
}

#elseif canImport(AppKit)
import AppKit

// MARK: - Type Aliases (macOS)

public typealias PlatformView = NSView
public typealias PlatformScrollView = NSScrollView
public typealias PlatformColor = NSColor
public typealias PlatformFont = NSFont
public typealias PlatformImage = NSImage
public typealias PlatformBezierPath = NSBezierPath
public typealias PlatformEdgeInsets = NSEdgeInsets
public typealias PlatformGestureRecognizer = NSGestureRecognizer
public typealias PlatformTapGestureRecognizer = NSClickGestureRecognizer
public typealias PlatformPanGestureRecognizer = NSPanGestureRecognizer
// Note: NSPressGestureRecognizer is the macOS equivalent of long press
public typealias PlatformLongPressGestureRecognizer = NSPressGestureRecognizer
public typealias PlatformPasteboard = NSPasteboard
public typealias PlatformApplication = NSApplication

// MARK: - Extensions for Compatibility

extension NSView {
    var platformBackgroundColor: NSColor? {
        get {
            guard let layer = layer else { return nil }
            guard let cgColor = layer.backgroundColor else { return nil }
            return NSColor(cgColor: cgColor)
        }
        set {
            wantsLayer = true
            layer?.backgroundColor = newValue?.cgColor
        }
    }


    func platformSetNeedsDisplay() {
        needsDisplay = true
    }

    func platformSetNeedsLayout() {
        needsLayout = true
    }

    func platformLayoutIfNeeded() {
        layoutSubtreeIfNeeded()
    }

}

extension NSScrollView {
    var platformContentOffset: CGPoint {
        get { contentView.bounds.origin }
        set { contentView.scroll(to: newValue) }
    }

    var platformContentSize: CGSize {
        get { documentView?.frame.size ?? .zero }
        set {
            documentView?.setFrameSize(newValue)
        }
    }

    var platformContentInset: NSEdgeInsets {
        get { contentInsets }
        set { contentInsets = newValue }
    }
}

extension NSColor {
    static var platformTextColor: NSColor {
        .textColor
    }

    static var platformBackgroundColor: NSColor {
        .textBackgroundColor
    }

    static var platformSecondaryLabelColor: NSColor {
        .secondaryLabelColor
    }
}

extension NSFont {
    static func platformMonospacedSystemFont(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// NSFont doesn't have lineHeight directly - calculate from metrics
    var lineHeight: CGFloat {
        ceil(ascender - descender + leading)
    }

    var platformLineHeight: CGFloat {
        lineHeight
    }
}

// NSEdgeInsets.zero and NSBezierPath extensions are defined in PlatformKit.swift

#endif

// MARK: - Cross-Platform Helpers

public enum Platform {
    #if os(iOS)
    public static let isiOS = true
    public static let isMacOS = false
    #elseif os(macOS)
    public static let isiOS = false
    public static let isMacOS = true
    #endif
}

// MARK: - Coordinate System Helpers

extension CGRect {
    /// Converts a rect from UIKit coordinates (origin at top-left) to AppKit coordinates (origin at bottom-left)
    func flippedVertically(in containerHeight: CGFloat) -> CGRect {
        CGRect(x: origin.x, y: containerHeight - origin.y - height, width: width, height: height)
    }
}

extension CGPoint {
    /// Converts a point from UIKit coordinates to AppKit coordinates
    func flippedVertically(in containerHeight: CGFloat) -> CGPoint {
        CGPoint(x: x, y: containerHeight - y)
    }
}
