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
        keyword: Color = Color(red: 0.988, green: 0.373, blue: 0.639),
        type: Color = Color(red: 0.365, green: 0.847, blue: 1.0),
        string: Color = Color(red: 0.988, green: 0.416, blue: 0.365),
        comment: Color = Color(red: 0.424, green: 0.475, blue: 0.525),
        number: Color = Color(red: 0.816, green: 0.749, blue: 0.412),
        function: Color = Color(red: 0.855, green: 0.788, blue: 0.506),
        tag: Color = Color(red: 0.404, green: 0.718, blue: 0.643),
        attribute: Color = Color(red: 0.698, green: 0.506, blue: 0.922),
        background: Color = .clear,
        text: Color = .primary,
        gutterBackground: Color = Color.gray.opacity(0.1),
        lineNumber: Color = .secondary,
        currentLineHighlight: Color = Color.gray.opacity(0.1),
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

    /// The default theme with a balanced color palette.
    public static let `default` = KeystoneTheme()

    /// A Monokai-inspired theme with vibrant colors.
    public static let monokai = KeystoneTheme(
        keyword: Color(red: 0.976, green: 0.149, blue: 0.447),
        type: Color(red: 0.400, green: 0.851, blue: 0.937),
        string: Color(red: 0.902, green: 0.859, blue: 0.455),
        comment: Color(red: 0.459, green: 0.443, blue: 0.369),
        number: Color(red: 0.682, green: 0.506, blue: 1.0),
        function: Color(red: 0.651, green: 0.886, blue: 0.184),
        tag: Color(red: 0.976, green: 0.149, blue: 0.447),
        attribute: Color(red: 0.651, green: 0.886, blue: 0.184),
        background: Color(red: 0.153, green: 0.157, blue: 0.133),
        text: Color(red: 0.973, green: 0.973, blue: 0.949)
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
        background: Color(red: 0.000, green: 0.169, blue: 0.212),
        text: Color(red: 0.514, green: 0.580, blue: 0.588)
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
        background: Color(red: 0.992, green: 0.965, blue: 0.890),
        text: Color(red: 0.396, green: 0.482, blue: 0.514)
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
        background: .white,
        text: Color(red: 0.145, green: 0.161, blue: 0.176)
    )

    /// An Xcode-inspired theme.
    public static let xcode = KeystoneTheme(
        keyword: Color(red: 0.608, green: 0.137, blue: 0.576),
        type: Color(red: 0.106, green: 0.282, blue: 0.494),
        string: Color(red: 0.769, green: 0.102, blue: 0.086),
        comment: Color(red: 0.384, green: 0.451, blue: 0.384),
        number: Color(red: 0.106, green: 0.282, blue: 0.494),
        function: Color(red: 0.243, green: 0.302, blue: 0.349),
        tag: Color(red: 0.608, green: 0.137, blue: 0.576),
        attribute: Color(red: 0.384, green: 0.451, blue: 0.384),
        background: .white,
        text: .black
    )
}
