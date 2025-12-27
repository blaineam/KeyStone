//
//  KeystoneTheme.swift
//  Keystone
//

import SwiftUI

/// A theme for syntax highlighting and editor appearance.
public struct KeystoneTheme: Equatable, Sendable {
    // MARK: - Syntax Colors

    /// Color for language keywords (if, else, func, etc.).
    public var keyword: Color
    /// Color for type names (String, Int, etc.).
    public var type: Color
    /// Color for string literals.
    public var string: Color
    /// Color for comments.
    public var comment: Color
    /// Color for numeric literals.
    public var number: Color
    /// Color for function/method names.
    public var function: Color
    /// Color for HTML/XML tags.
    public var tag: Color
    /// Color for attributes.
    public var attribute: Color
    /// Color for operators.
    public var `operator`: Color
    /// Color for property names.
    public var property: Color

    // MARK: - Editor Colors

    /// The editor background color.
    public var background: Color
    /// The main text color.
    public var text: Color
    /// The line number gutter background color.
    public var gutterBackground: Color
    /// The line number text color.
    public var lineNumber: Color
    /// The current line highlight color.
    public var currentLineHighlight: Color
    /// The selection highlight color.
    public var selection: Color
    /// The matching bracket highlight color.
    public var matchingBracket: Color
    /// The search match highlight color.
    public var searchMatch: Color
    /// The current search match highlight color.
    public var currentSearchMatch: Color
    /// The invisible character color.
    public var invisibleCharacter: Color

    // MARK: - Initialization

    public init(
        keyword: Color = .pink,
        type: Color = .cyan,
        string: Color = .orange,
        comment: Color = .gray,
        number: Color = .yellow,
        function: Color = .blue,
        tag: Color = .teal,
        attribute: Color = .purple,
        operator: Color = .primary,
        property: Color = .cyan,
        background: Color = Color(light: .white, dark: Color(red: 0.11, green: 0.11, blue: 0.12)),
        text: Color = .primary,
        gutterBackground: Color = Color(light: Color.gray.opacity(0.08), dark: Color.gray.opacity(0.15)),
        lineNumber: Color = .secondary,
        currentLineHighlight: Color = Color(light: Color.blue.opacity(0.05), dark: Color.blue.opacity(0.1)),
        selection: Color = Color.accentColor.opacity(0.3),
        matchingBracket: Color = Color.blue.opacity(0.3),
        searchMatch: Color = Color.yellow.opacity(0.3),
        currentSearchMatch: Color = Color.orange.opacity(0.5),
        invisibleCharacter: Color = Color.gray.opacity(0.3)
    ) {
        self.keyword = keyword
        self.type = type
        self.string = string
        self.comment = comment
        self.number = number
        self.function = function
        self.tag = tag
        self.attribute = attribute
        self.operator = `operator`
        self.property = property
        self.background = background
        self.text = text
        self.gutterBackground = gutterBackground
        self.lineNumber = lineNumber
        self.currentLineHighlight = currentLineHighlight
        self.selection = selection
        self.matchingBracket = matchingBracket
        self.searchMatch = searchMatch
        self.currentSearchMatch = currentSearchMatch
        self.invisibleCharacter = invisibleCharacter
    }

    // MARK: - Built-in Themes

    /// System adaptive theme - automatically adjusts to light/dark mode.
    public static let system = KeystoneTheme(
        // Keywords: bright pink/magenta for visibility
        keyword: Color(light: Color(red: 0.608, green: 0.137, blue: 0.576), dark: Color(red: 1.0, green: 0.42, blue: 0.68)),
        // Types: bright cyan for clear contrast
        type: Color(light: Color(red: 0.106, green: 0.282, blue: 0.494), dark: Color(red: 0.45, green: 0.90, blue: 1.0)),
        // Strings: bright orange/coral
        string: Color(light: Color(red: 0.769, green: 0.102, blue: 0.086), dark: Color(red: 1.0, green: 0.55, blue: 0.45)),
        // Comments: lighter gray for readability
        comment: Color(light: Color(red: 0.384, green: 0.451, blue: 0.384), dark: Color(red: 0.55, green: 0.60, blue: 0.65)),
        // Numbers: bright gold/yellow
        number: Color(light: Color(red: 0.106, green: 0.282, blue: 0.494), dark: Color(red: 0.90, green: 0.82, blue: 0.45)),
        // Functions: bright yellow/cream
        function: Color(light: Color(red: 0.243, green: 0.302, blue: 0.349), dark: Color(red: 0.92, green: 0.85, blue: 0.55)),
        // Tags: bright teal/green
        tag: Color(light: Color(red: 0.129, green: 0.459, blue: 0.263), dark: Color(red: 0.45, green: 0.80, blue: 0.70)),
        // Attributes: bright purple
        attribute: Color(light: Color(red: 0.384, green: 0.451, blue: 0.384), dark: Color(red: 0.78, green: 0.58, blue: 0.98)),
        // Operators: white for max visibility
        operator: Color(light: .black, dark: .white),
        // Properties: bright cyan (same as types)
        property: Color(light: Color(red: 0.106, green: 0.282, blue: 0.494), dark: Color(red: 0.45, green: 0.90, blue: 1.0)),
        // Editor colors
        background: Color(light: .white, dark: Color(red: 0.12, green: 0.12, blue: 0.14)),
        text: Color(light: .black, dark: Color(white: 0.95)),
        gutterBackground: Color(light: Color(white: 0.96), dark: Color(white: 0.16)),
        lineNumber: Color(light: Color(white: 0.45), dark: Color(white: 0.65)),
        currentLineHighlight: Color(light: Color.blue.opacity(0.06), dark: Color.white.opacity(0.06)),
        invisibleCharacter: Color(light: Color(white: 0.8), dark: Color(white: 0.40))
    )

    /// The default theme (alias for system).
    public static let `default` = system

    /// A Monokai-inspired dark theme.
    public static let monokai = KeystoneTheme(
        keyword: Color(red: 0.976, green: 0.149, blue: 0.447),
        type: Color(red: 0.400, green: 0.851, blue: 0.937),
        string: Color(red: 0.902, green: 0.859, blue: 0.455),
        comment: Color(red: 0.459, green: 0.443, blue: 0.369),
        number: Color(red: 0.682, green: 0.506, blue: 1.0),
        function: Color(red: 0.651, green: 0.886, blue: 0.184),
        tag: Color(red: 0.976, green: 0.149, blue: 0.447),
        attribute: Color(red: 0.651, green: 0.886, blue: 0.184),
        operator: Color(red: 0.976, green: 0.149, blue: 0.447),
        property: Color(red: 0.400, green: 0.851, blue: 0.937),
        background: Color(red: 0.153, green: 0.157, blue: 0.133),
        text: Color(red: 0.973, green: 0.973, blue: 0.949),
        gutterBackground: Color(red: 0.12, green: 0.12, blue: 0.10),
        lineNumber: Color(red: 0.459, green: 0.443, blue: 0.369),
        currentLineHighlight: Color.white.opacity(0.05),
        invisibleCharacter: Color(red: 0.459, green: 0.443, blue: 0.369).opacity(0.6)
    )

    /// A Solarized Dark theme.
    public static let solarizedDark = KeystoneTheme(
        keyword: Color(red: 0.522, green: 0.600, blue: 0.000),
        type: Color(red: 0.149, green: 0.545, blue: 0.824),
        string: Color(red: 0.165, green: 0.631, blue: 0.596),
        comment: Color(red: 0.396, green: 0.482, blue: 0.514),
        number: Color(red: 0.827, green: 0.212, blue: 0.510),
        function: Color(red: 0.149, green: 0.545, blue: 0.824),
        tag: Color(red: 0.710, green: 0.537, blue: 0.000),
        attribute: Color(red: 0.576, green: 0.631, blue: 0.631),
        operator: Color(red: 0.522, green: 0.600, blue: 0.000),
        property: Color(red: 0.149, green: 0.545, blue: 0.824),
        background: Color(red: 0.000, green: 0.169, blue: 0.212),
        text: Color(red: 0.514, green: 0.580, blue: 0.588),
        gutterBackground: Color(red: 0.000, green: 0.149, blue: 0.192),
        lineNumber: Color(red: 0.396, green: 0.482, blue: 0.514),
        currentLineHighlight: Color.white.opacity(0.03),
        invisibleCharacter: Color(red: 0.396, green: 0.482, blue: 0.514).opacity(0.5)
    )

    /// A Solarized Light theme.
    public static let solarizedLight = KeystoneTheme(
        keyword: Color(red: 0.522, green: 0.600, blue: 0.000),
        type: Color(red: 0.149, green: 0.545, blue: 0.824),
        string: Color(red: 0.165, green: 0.631, blue: 0.596),
        comment: Color(red: 0.576, green: 0.631, blue: 0.631),
        number: Color(red: 0.827, green: 0.212, blue: 0.510),
        function: Color(red: 0.149, green: 0.545, blue: 0.824),
        tag: Color(red: 0.710, green: 0.537, blue: 0.000),
        attribute: Color(red: 0.396, green: 0.482, blue: 0.514),
        operator: Color(red: 0.522, green: 0.600, blue: 0.000),
        property: Color(red: 0.149, green: 0.545, blue: 0.824),
        background: Color(red: 0.992, green: 0.965, blue: 0.890),
        text: Color(red: 0.396, green: 0.482, blue: 0.514),
        gutterBackground: Color(red: 0.972, green: 0.945, blue: 0.870),
        lineNumber: Color(red: 0.576, green: 0.631, blue: 0.631),
        currentLineHighlight: Color.black.opacity(0.03),
        invisibleCharacter: Color(red: 0.576, green: 0.631, blue: 0.631).opacity(0.5)
    )

    /// A GitHub-inspired light theme.
    public static let github = KeystoneTheme(
        keyword: Color(red: 0.839, green: 0.227, blue: 0.400),
        type: Color(red: 0.110, green: 0.341, blue: 0.620),
        string: Color(red: 0.031, green: 0.369, blue: 0.565),
        comment: Color(red: 0.424, green: 0.478, blue: 0.537),
        number: Color(red: 0.031, green: 0.369, blue: 0.565),
        function: Color(red: 0.435, green: 0.259, blue: 0.757),
        tag: Color(red: 0.129, green: 0.459, blue: 0.263),
        attribute: Color(red: 0.110, green: 0.341, blue: 0.620),
        operator: Color(red: 0.839, green: 0.227, blue: 0.400),
        property: Color(red: 0.110, green: 0.341, blue: 0.620),
        background: .white,
        text: Color(red: 0.145, green: 0.161, blue: 0.176),
        gutterBackground: Color(red: 0.96, green: 0.97, blue: 0.98),
        lineNumber: Color(red: 0.424, green: 0.478, blue: 0.537),
        currentLineHighlight: Color(red: 1.0, green: 0.98, blue: 0.9),
        invisibleCharacter: Color(red: 0.424, green: 0.478, blue: 0.537).opacity(0.4)
    )

    /// An Xcode-inspired theme (light).
    public static let xcode = KeystoneTheme(
        keyword: Color(red: 0.608, green: 0.137, blue: 0.576),
        type: Color(red: 0.106, green: 0.282, blue: 0.494),
        string: Color(red: 0.769, green: 0.102, blue: 0.086),
        comment: Color(red: 0.384, green: 0.451, blue: 0.384),
        number: Color(red: 0.106, green: 0.282, blue: 0.494),
        function: Color(red: 0.243, green: 0.302, blue: 0.349),
        tag: Color(red: 0.608, green: 0.137, blue: 0.576),
        attribute: Color(red: 0.384, green: 0.451, blue: 0.384),
        operator: Color(red: 0.0, green: 0.0, blue: 0.0),
        property: Color(red: 0.243, green: 0.302, blue: 0.349),
        background: .white,
        text: .black,
        gutterBackground: Color(red: 0.95, green: 0.95, blue: 0.95),
        lineNumber: Color(red: 0.5, green: 0.5, blue: 0.5),
        currentLineHighlight: Color(red: 0.9, green: 0.95, blue: 1.0),
        invisibleCharacter: Color(white: 0.75)
    )

    /// An Xcode Dark theme.
    public static let xcodeDark = KeystoneTheme(
        keyword: Color(red: 0.988, green: 0.373, blue: 0.639),
        type: Color(red: 0.365, green: 0.847, blue: 1.0),
        string: Color(red: 0.988, green: 0.416, blue: 0.365),
        comment: Color(red: 0.424, green: 0.475, blue: 0.525),
        number: Color(red: 0.816, green: 0.749, blue: 0.412),
        function: Color(red: 0.855, green: 0.788, blue: 0.506),
        tag: Color(red: 0.988, green: 0.373, blue: 0.639),
        attribute: Color(red: 0.698, green: 0.506, blue: 0.922),
        operator: .white,
        property: Color(red: 0.855, green: 0.788, blue: 0.506),
        background: Color(red: 0.11, green: 0.11, blue: 0.12),
        text: .white,
        gutterBackground: Color(red: 0.09, green: 0.09, blue: 0.10),
        lineNumber: Color(red: 0.424, green: 0.475, blue: 0.525),
        currentLineHighlight: Color.white.opacity(0.05),
        invisibleCharacter: Color(red: 0.424, green: 0.475, blue: 0.525).opacity(0.6)
    )

    /// A Dracula theme.
    public static let dracula = KeystoneTheme(
        keyword: Color(red: 1.0, green: 0.475, blue: 0.776),
        type: Color(red: 0.545, green: 0.914, blue: 0.992),
        string: Color(red: 0.945, green: 0.980, blue: 0.549),
        comment: Color(red: 0.384, green: 0.447, blue: 0.643),
        number: Color(red: 0.741, green: 0.576, blue: 0.976),
        function: Color(red: 0.314, green: 0.980, blue: 0.482),
        tag: Color(red: 1.0, green: 0.475, blue: 0.776),
        attribute: Color(red: 0.314, green: 0.980, blue: 0.482),
        operator: Color(red: 1.0, green: 0.475, blue: 0.776),
        property: Color(red: 0.545, green: 0.914, blue: 0.992),
        background: Color(red: 0.157, green: 0.165, blue: 0.212),
        text: Color(red: 0.973, green: 0.973, blue: 0.949),
        gutterBackground: Color(red: 0.137, green: 0.145, blue: 0.192),
        lineNumber: Color(red: 0.384, green: 0.447, blue: 0.643),
        currentLineHighlight: Color.white.opacity(0.05),
        invisibleCharacter: Color(red: 0.384, green: 0.447, blue: 0.643).opacity(0.6)
    )

    /// A One Dark theme (Atom-inspired).
    public static let oneDark = KeystoneTheme(
        keyword: Color(red: 0.780, green: 0.467, blue: 0.863),
        type: Color(red: 0.894, green: 0.714, blue: 0.329),
        string: Color(red: 0.596, green: 0.765, blue: 0.396),
        comment: Color(red: 0.365, green: 0.404, blue: 0.459),
        number: Color(red: 0.824, green: 0.529, blue: 0.396),
        function: Color(red: 0.380, green: 0.686, blue: 0.937),
        tag: Color(red: 0.894, green: 0.420, blue: 0.420),
        attribute: Color(red: 0.824, green: 0.529, blue: 0.396),
        operator: Color(red: 0.667, green: 0.733, blue: 0.816),
        property: Color(red: 0.894, green: 0.420, blue: 0.420),
        background: Color(red: 0.157, green: 0.173, blue: 0.204),
        text: Color(red: 0.667, green: 0.733, blue: 0.816),
        gutterBackground: Color(red: 0.137, green: 0.153, blue: 0.184),
        lineNumber: Color(red: 0.365, green: 0.404, blue: 0.459),
        currentLineHighlight: Color.white.opacity(0.03),
        invisibleCharacter: Color(red: 0.365, green: 0.404, blue: 0.459).opacity(0.6)
    )

    /// All available themes for selection.
    public static let allThemes: [(name: String, theme: KeystoneTheme)] = [
        ("System", .system),
        ("Xcode Light", .xcode),
        ("Xcode Dark", .xcodeDark),
        ("GitHub", .github),
        ("Monokai", .monokai),
        ("Dracula", .dracula),
        ("One Dark", .oneDark),
        ("Solarized Light", .solarizedLight),
        ("Solarized Dark", .solarizedDark)
    ]

    /// Returns the theme with the given name, or nil if not found.
    public static func theme(named name: String) -> KeystoneTheme? {
        allThemes.first { $0.name == name }?.theme
    }

    /// Returns the name of the given theme, or "System" if not found.
    public static func name(for theme: KeystoneTheme) -> String {
        allThemes.first { $0.theme == theme }?.name ?? "System"
    }
}

// MARK: - Color Extension for Light/Dark Mode

public extension Color {
    /// Creates a color that adapts to light and dark mode.
    init(light: Color, dark: Color) {
        #if os(iOS)
        self.init(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
        #elseif os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(dark)
                : NSColor(light)
        })
        #endif
    }

    /// Background color for status bar.
    static var keystoneStatusBar: Color {
        Color(light: Color(white: 0.95), dark: Color(white: 0.15))
    }
}
