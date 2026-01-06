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
        searchMatch: Color = Color.yellow.opacity(0.5),
        currentSearchMatch: Color = Color.orange.opacity(0.7),
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
        keyword: Color(light: Color(red: 0.608, green: 0.137, blue: 0.576), dark: Color(red: 1.0, green: 0.42, blue: 0.68)),
        type: Color(light: Color(red: 0.106, green: 0.282, blue: 0.494), dark: Color(red: 0.45, green: 0.90, blue: 1.0)),
        string: Color(light: Color(red: 0.769, green: 0.102, blue: 0.086), dark: Color(red: 1.0, green: 0.55, blue: 0.45)),
        comment: Color(light: Color(red: 0.384, green: 0.451, blue: 0.384), dark: Color(red: 0.55, green: 0.60, blue: 0.65)),
        number: Color(light: Color(red: 0.106, green: 0.282, blue: 0.494), dark: Color(red: 0.90, green: 0.82, blue: 0.45)),
        function: Color(light: Color(red: 0.243, green: 0.302, blue: 0.349), dark: Color(red: 0.92, green: 0.85, blue: 0.55)),
        tag: Color(light: Color(red: 0.129, green: 0.459, blue: 0.263), dark: Color(red: 0.45, green: 0.80, blue: 0.70)),
        attribute: Color(light: Color(red: 0.384, green: 0.451, blue: 0.384), dark: Color(red: 0.78, green: 0.58, blue: 0.98)),
        operator: Color(light: .black, dark: .white),
        property: Color(light: Color(red: 0.106, green: 0.282, blue: 0.494), dark: Color(red: 0.45, green: 0.90, blue: 1.0)),
        background: Color(light: .white, dark: Color(red: 0.12, green: 0.12, blue: 0.14)),
        text: Color(light: .black, dark: Color(white: 0.95)),
        gutterBackground: Color(light: Color(white: 0.96), dark: Color(white: 0.16)),
        lineNumber: Color(light: Color(white: 0.45), dark: Color(white: 0.65)),
        currentLineHighlight: Color(light: Color.blue.opacity(0.08), dark: Color.white.opacity(0.10)),
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

    // MARK: - Light Themes

    /// An Xcode Light theme.
    public static let xcodeLight = KeystoneTheme(
        keyword: Color(red: 0.608, green: 0.137, blue: 0.576),
        type: Color(red: 0.110, green: 0.333, blue: 0.525),
        string: Color(red: 0.769, green: 0.102, blue: 0.086),
        comment: Color(red: 0.384, green: 0.451, blue: 0.384),
        number: Color(red: 0.110, green: 0.333, blue: 0.525),
        function: Color(red: 0.243, green: 0.302, blue: 0.349),
        tag: Color(red: 0.608, green: 0.137, blue: 0.576),
        attribute: Color(red: 0.384, green: 0.451, blue: 0.384),
        operator: Color(red: 0.0, green: 0.0, blue: 0.0),
        property: Color(red: 0.243, green: 0.302, blue: 0.349),
        background: .white,
        text: .black,
        gutterBackground: Color(white: 0.965),
        lineNumber: Color(white: 0.5),
        currentLineHighlight: Color(red: 0.929, green: 0.953, blue: 1.0),
        invisibleCharacter: Color(white: 0.8)
    )

    /// A Solarized Light theme.
    public static let solarizedLight = KeystoneTheme(
        keyword: Color(red: 0.522, green: 0.600, blue: 0.000),
        type: Color(red: 0.149, green: 0.545, blue: 0.824),
        string: Color(red: 0.165, green: 0.631, blue: 0.596),
        comment: Color(red: 0.576, green: 0.631, blue: 0.631),
        number: Color(red: 0.827, green: 0.212, blue: 0.510),
        function: Color(red: 0.149, green: 0.545, blue: 0.824),
        tag: Color(red: 0.522, green: 0.600, blue: 0.000),
        attribute: Color(red: 0.710, green: 0.537, blue: 0.000),
        operator: Color(red: 0.396, green: 0.482, blue: 0.514),
        property: Color(red: 0.149, green: 0.545, blue: 0.824),
        background: Color(red: 0.992, green: 0.965, blue: 0.890),
        text: Color(red: 0.396, green: 0.482, blue: 0.514),
        gutterBackground: Color(red: 0.933, green: 0.910, blue: 0.835),
        lineNumber: Color(red: 0.576, green: 0.631, blue: 0.631),
        currentLineHighlight: Color(red: 0.933, green: 0.910, blue: 0.835),
        invisibleCharacter: Color(red: 0.576, green: 0.631, blue: 0.631).opacity(0.5)
    )

    /// A GitHub Light theme.
    public static let githubLight = KeystoneTheme(
        keyword: Color(red: 0.839, green: 0.227, blue: 0.369),
        type: Color(red: 0.404, green: 0.306, blue: 0.773),
        string: Color(red: 0.012, green: 0.365, blue: 0.596),
        comment: Color(red: 0.341, green: 0.373, blue: 0.404),
        number: Color(red: 0.012, green: 0.365, blue: 0.596),
        function: Color(red: 0.404, green: 0.306, blue: 0.773),
        tag: Color(red: 0.129, green: 0.459, blue: 0.259),
        attribute: Color(red: 0.012, green: 0.365, blue: 0.596),
        operator: Color(red: 0.839, green: 0.227, blue: 0.369),
        property: Color(red: 0.012, green: 0.365, blue: 0.596),
        background: .white,
        text: Color(red: 0.145, green: 0.161, blue: 0.180),
        gutterBackground: Color(red: 0.969, green: 0.973, blue: 0.976),
        lineNumber: Color(red: 0.341, green: 0.373, blue: 0.404),
        currentLineHighlight: Color(red: 1.0, green: 0.992, blue: 0.910),
        invisibleCharacter: Color(red: 0.341, green: 0.373, blue: 0.404).opacity(0.4)
    )

    /// An Atom One Light theme.
    public static let oneLight = KeystoneTheme(
        keyword: Color(red: 0.659, green: 0.051, blue: 0.569),
        type: Color(red: 0.769, green: 0.388, blue: 0.039),
        string: Color(red: 0.314, green: 0.604, blue: 0.153),
        comment: Color(red: 0.627, green: 0.647, blue: 0.663),
        number: Color(red: 0.600, green: 0.408, blue: 0.071),
        function: Color(red: 0.247, green: 0.459, blue: 0.847),
        tag: Color(red: 0.886, green: 0.243, blue: 0.173),
        attribute: Color(red: 0.769, green: 0.388, blue: 0.039),
        operator: Color(red: 0.659, green: 0.051, blue: 0.569),
        property: Color(red: 0.886, green: 0.243, blue: 0.173),
        background: Color(red: 0.980, green: 0.980, blue: 0.980),
        text: Color(red: 0.227, green: 0.243, blue: 0.259),
        gutterBackground: Color(red: 0.953, green: 0.957, blue: 0.961),
        lineNumber: Color(red: 0.627, green: 0.647, blue: 0.663),
        currentLineHighlight: Color(red: 0.914, green: 0.925, blue: 0.937),
        invisibleCharacter: Color(red: 0.627, green: 0.647, blue: 0.663).opacity(0.5)
    )

    /// A Tomorrow Light theme.
    public static let tomorrowLight = KeystoneTheme(
        keyword: Color(red: 0.541, green: 0.384, blue: 0.647),
        type: Color(red: 0.302, green: 0.639, blue: 0.722),
        string: Color(red: 0.447, green: 0.624, blue: 0.302),
        comment: Color(red: 0.553, green: 0.576, blue: 0.600),
        number: Color(red: 0.961, green: 0.584, blue: 0.302),
        function: Color(red: 0.302, green: 0.529, blue: 0.749),
        tag: Color(red: 0.769, green: 0.306, blue: 0.318),
        attribute: Color(red: 0.961, green: 0.584, blue: 0.302),
        operator: Color(red: 0.294, green: 0.322, blue: 0.341),
        property: Color(red: 0.302, green: 0.529, blue: 0.749),
        background: .white,
        text: Color(red: 0.294, green: 0.322, blue: 0.341),
        gutterBackground: Color(red: 0.965, green: 0.969, blue: 0.973),
        lineNumber: Color(red: 0.553, green: 0.576, blue: 0.600),
        currentLineHighlight: Color(red: 0.937, green: 0.945, blue: 0.949),
        invisibleCharacter: Color(red: 0.553, green: 0.576, blue: 0.600).opacity(0.4)
    )

    // MARK: - Additional Dark Themes

    /// A Nord dark theme.
    public static let nord = KeystoneTheme(
        keyword: Color(red: 0.506, green: 0.631, blue: 0.757),
        type: Color(red: 0.565, green: 0.737, blue: 0.733),
        string: Color(red: 0.647, green: 0.741, blue: 0.549),
        comment: Color(red: 0.263, green: 0.298, blue: 0.369),
        number: Color(red: 0.706, green: 0.557, blue: 0.678),
        function: Color(red: 0.533, green: 0.753, blue: 0.816),
        tag: Color(red: 0.506, green: 0.631, blue: 0.757),
        attribute: Color(red: 0.565, green: 0.737, blue: 0.733),
        operator: Color(red: 0.506, green: 0.631, blue: 0.757),
        property: Color(red: 0.533, green: 0.753, blue: 0.816),
        background: Color(red: 0.180, green: 0.204, blue: 0.251),
        text: Color(red: 0.925, green: 0.937, blue: 0.957),
        gutterBackground: Color(red: 0.161, green: 0.184, blue: 0.231),
        lineNumber: Color(red: 0.263, green: 0.298, blue: 0.369),
        currentLineHighlight: Color.white.opacity(0.04),
        invisibleCharacter: Color(red: 0.263, green: 0.298, blue: 0.369).opacity(0.6)
    )

    /// A Gruvbox Dark theme.
    public static let gruvboxDark = KeystoneTheme(
        keyword: Color(red: 0.984, green: 0.286, blue: 0.204),
        type: Color(red: 0.984, green: 0.741, blue: 0.184),
        string: Color(red: 0.722, green: 0.733, blue: 0.149),
        comment: Color(red: 0.573, green: 0.514, blue: 0.455),
        number: Color(red: 0.820, green: 0.525, blue: 0.608),
        function: Color(red: 0.514, green: 0.647, blue: 0.596),
        tag: Color(red: 0.984, green: 0.286, blue: 0.204),
        attribute: Color(red: 0.984, green: 0.741, blue: 0.184),
        operator: Color(red: 0.984, green: 0.286, blue: 0.204),
        property: Color(red: 0.514, green: 0.647, blue: 0.596),
        background: Color(red: 0.157, green: 0.157, blue: 0.133),
        text: Color(red: 0.922, green: 0.859, blue: 0.698),
        gutterBackground: Color(red: 0.125, green: 0.125, blue: 0.106),
        lineNumber: Color(red: 0.573, green: 0.514, blue: 0.455),
        currentLineHighlight: Color.white.opacity(0.04),
        invisibleCharacter: Color(red: 0.573, green: 0.514, blue: 0.455).opacity(0.5)
    )

    /// All available themes for selection.
    public static let allThemes: [(name: String, theme: KeystoneTheme)] = [
        // Adaptive
        ("System", .system),
        // Light themes
        ("Xcode Light", .xcodeLight),
        ("GitHub Light", .githubLight),
        ("Solarized Light", .solarizedLight),
        ("One Light", .oneLight),
        ("Tomorrow", .tomorrowLight),
        // Dark themes
        ("Xcode Dark", .xcodeDark),
        ("Monokai", .monokai),
        ("Dracula", .dracula),
        ("Nord", .nord),
        ("Gruvbox Dark", .gruvboxDark)
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
