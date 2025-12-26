//
//  PlatformTypes.swift
//  Keystone
//

import SwiftUI

#if os(iOS)
import UIKit
public typealias PlatformColor = UIColor
public typealias PlatformFont = UIFont
public typealias PlatformView = UIView
public typealias PlatformTextView = UITextView
public typealias PlatformScrollView = UIScrollView
public typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
public typealias PlatformColor = NSColor
public typealias PlatformFont = NSFont
public typealias PlatformView = NSView
public typealias PlatformTextView = NSTextView
public typealias PlatformScrollView = NSScrollView
public typealias PlatformImage = NSImage
#endif

// MARK: - Cross-Platform Color Extensions

extension PlatformColor {
    /// Creates a platform color from SwiftUI Color.
    /// Uses native initializers to preserve dynamic light/dark mode behavior.
    public convenience init(_ color: Color) {
        #if os(iOS)
        // Use UIColor's native Color initializer which preserves dynamic colors
        let uiColor = UIColor(color)
        self.init(cgColor: uiColor.cgColor)
        #else
        // Use NSColor's native Color initializer which preserves dynamic colors
        let nsColor = NSColor(color)
        self.init(cgColor: nsColor.cgColor)!
        #endif
    }

    /// Creates a dynamic platform color that adapts to light/dark mode.
    public static func dynamicColor(light: Color, dark: Color) -> PlatformColor {
        #if os(iOS)
        return UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        }
        #else
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(dark)
                : NSColor(light)
        }
        #endif
    }
}

// MARK: - Cross-Platform Font Creation

extension PlatformFont {
    /// Creates a monospaced system font of the given size.
    public static func keystoneMonospaced(size: CGFloat, weight: Weight = .regular) -> PlatformFont {
        return .monospacedSystemFont(ofSize: size, weight: weight)
    }
}

// MARK: - Cross-Platform Color Constants

extension Color {
    /// The default editor background color.
    public static var keystoneBackground: Color {
        #if os(iOS)
        return Color(UIColor.systemBackground)
        #else
        return Color(NSColor.textBackgroundColor)
        #endif
    }

    /// The default gutter background color.
    public static var keystoneGutter: Color {
        #if os(iOS)
        return Color(UIColor.secondarySystemBackground)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }
}

// MARK: - Invisible Character Symbols

public enum InvisibleCharacters {
    /// The symbol used to display spaces.
    public static let space = "·"
    /// The symbol used to display tabs.
    public static let tab = "→"
    /// The symbol used to display line feed (LF).
    public static let lineFeed = "¬"
    /// The symbol used to display carriage return (CR).
    public static let carriageReturn = "←"

    /// Renders invisible characters in the given text for display purposes.
    /// Note: This creates a new string with visible representations.
    public static func render(_ text: String, showSpaces: Bool = true, showTabs: Bool = true) -> String {
        var result = text
        if showTabs {
            result = result.replacingOccurrences(of: "\t", with: tab)
        }
        if showSpaces {
            result = result.replacingOccurrences(of: " ", with: space)
        }
        return result
    }
}
