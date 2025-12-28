//
//  KeystoneConfiguration.swift
//  Keystone
//

import SwiftUI

/// Configuration options for the Keystone code editor.
@MainActor
public final class KeystoneConfiguration: ObservableObject {
    // MARK: - Appearance Settings

    /// The font size for the editor text.
    @Published public var fontSize: CGFloat = 14

    /// The line height multiplier. 1.0 is normal, higher values add more spacing.
    @Published public var lineHeightMultiplier: CGFloat = 1.2

    /// Whether to show line numbers in the gutter.
    @Published public var showLineNumbers: Bool = true

    /// Whether to highlight the line containing the cursor.
    @Published public var highlightCurrentLine: Bool = true

    /// Whether to show invisible characters (spaces, tabs, line endings).
    @Published public var showInvisibleCharacters: Bool = false

    /// Whether to wrap long lines.
    @Published public var lineWrapping: Bool = true

    /// Whether to show code folding indicators in the gutter.
    /// Note: May impact scroll performance on iOS for large files.
    @Published public var showCodeFolding: Bool = true

    // MARK: - Behavior Settings

    /// Whether to automatically insert matching pairs (brackets, quotes).
    @Published public var autoInsertPairs: Bool = true

    /// Whether to highlight matching brackets.
    @Published public var highlightMatchingBrackets: Bool = true

    /// Whether the Tab key inserts a tab/indent or navigates focus.
    @Published public var tabKeyInsertsTab: Bool = true

    // MARK: - Indentation Settings

    /// The indentation settings (auto-detected from file content).
    @Published public var indentation: IndentationSettings = IndentationSettings()

    // MARK: - Line Ending Settings

    /// The line ending type (auto-detected from file content).
    @Published public var lineEnding: LineEnding = .lf

    // MARK: - Theme

    /// The syntax highlighting theme.
    @Published public var theme: KeystoneTheme = .default

    // MARK: - Character Pairs

    /// Character pairs for auto-insertion.
    public static let characterPairs: [Character: Character] = [
        "(": ")",
        "[": "]",
        "{": "}",
        "\"": "\"",
        "'": "'",
        "`": "`"
    ]

    // MARK: - Persistence Keys

    private enum Keys {
        static let fontSize = "keystone.fontSize"
        static let lineHeightMultiplier = "keystone.lineHeightMultiplier"
        static let showLineNumbers = "keystone.showLineNumbers"
        static let highlightCurrentLine = "keystone.highlightCurrentLine"
        static let showInvisibleCharacters = "keystone.showInvisibleCharacters"
        static let lineWrapping = "keystone.lineWrapping"
        static let showCodeFolding = "keystone.showCodeFolding"
        static let autoInsertPairs = "keystone.autoInsertPairs"
        static let highlightMatchingBrackets = "keystone.highlightMatchingBrackets"
        static let tabKeyInsertsTab = "keystone.tabKeyInsertsTab"
        static let themeName = "keystone.themeName"
        static let indentUseTabs = "keystone.indentUseTabs"
        static let indentWidth = "keystone.indentWidth"
    }

    // MARK: - Initialization

    public init() {
        loadFromUserDefaults()
    }

    // MARK: - Persistence

    /// Loads settings from UserDefaults.
    public func loadFromUserDefaults() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: Keys.fontSize) != nil {
            fontSize = CGFloat(defaults.double(forKey: Keys.fontSize))
        }
        if defaults.object(forKey: Keys.lineHeightMultiplier) != nil {
            lineHeightMultiplier = CGFloat(defaults.double(forKey: Keys.lineHeightMultiplier))
        }
        if defaults.object(forKey: Keys.showLineNumbers) != nil {
            showLineNumbers = defaults.bool(forKey: Keys.showLineNumbers)
        }
        if defaults.object(forKey: Keys.highlightCurrentLine) != nil {
            highlightCurrentLine = defaults.bool(forKey: Keys.highlightCurrentLine)
        }
        if defaults.object(forKey: Keys.showInvisibleCharacters) != nil {
            showInvisibleCharacters = defaults.bool(forKey: Keys.showInvisibleCharacters)
        }
        if defaults.object(forKey: Keys.lineWrapping) != nil {
            lineWrapping = defaults.bool(forKey: Keys.lineWrapping)
        }
        if defaults.object(forKey: Keys.showCodeFolding) != nil {
            showCodeFolding = defaults.bool(forKey: Keys.showCodeFolding)
        }
        if defaults.object(forKey: Keys.autoInsertPairs) != nil {
            autoInsertPairs = defaults.bool(forKey: Keys.autoInsertPairs)
        }
        if defaults.object(forKey: Keys.highlightMatchingBrackets) != nil {
            highlightMatchingBrackets = defaults.bool(forKey: Keys.highlightMatchingBrackets)
        }
        if defaults.object(forKey: Keys.tabKeyInsertsTab) != nil {
            tabKeyInsertsTab = defaults.bool(forKey: Keys.tabKeyInsertsTab)
        }
        if let themeName = defaults.string(forKey: Keys.themeName) {
            theme = KeystoneTheme.theme(named: themeName) ?? .system
        }
        if defaults.object(forKey: Keys.indentUseTabs) != nil {
            indentation.type = defaults.bool(forKey: Keys.indentUseTabs) ? .tabs : .spaces
        }
        if defaults.object(forKey: Keys.indentWidth) != nil {
            indentation.width = defaults.integer(forKey: Keys.indentWidth)
        }
    }

    /// Saves current settings to UserDefaults.
    public func saveToUserDefaults() {
        let defaults = UserDefaults.standard

        defaults.set(Double(fontSize), forKey: Keys.fontSize)
        defaults.set(Double(lineHeightMultiplier), forKey: Keys.lineHeightMultiplier)
        defaults.set(showLineNumbers, forKey: Keys.showLineNumbers)
        defaults.set(highlightCurrentLine, forKey: Keys.highlightCurrentLine)
        defaults.set(showInvisibleCharacters, forKey: Keys.showInvisibleCharacters)
        defaults.set(lineWrapping, forKey: Keys.lineWrapping)
        defaults.set(showCodeFolding, forKey: Keys.showCodeFolding)
        defaults.set(autoInsertPairs, forKey: Keys.autoInsertPairs)
        defaults.set(highlightMatchingBrackets, forKey: Keys.highlightMatchingBrackets)
        defaults.set(tabKeyInsertsTab, forKey: Keys.tabKeyInsertsTab)
        defaults.set(KeystoneTheme.name(for: theme), forKey: Keys.themeName)
        defaults.set(indentation.type == .tabs, forKey: Keys.indentUseTabs)
        defaults.set(indentation.width, forKey: Keys.indentWidth)
    }

    // MARK: - Methods

    /// Detects and applies settings from the given file content.
    /// - Parameter text: The file content to analyze.
    public func detectSettings(from text: String) {
        lineEnding = LineEnding.detect(in: text)
        indentation = IndentationSettings.detect(from: text)
    }

    /// Creates a copy of this configuration.
    public func copy() -> KeystoneConfiguration {
        let config = KeystoneConfiguration()
        config.fontSize = fontSize
        config.lineHeightMultiplier = lineHeightMultiplier
        config.showLineNumbers = showLineNumbers
        config.highlightCurrentLine = highlightCurrentLine
        config.showInvisibleCharacters = showInvisibleCharacters
        config.lineWrapping = lineWrapping
        config.showCodeFolding = showCodeFolding
        config.autoInsertPairs = autoInsertPairs
        config.highlightMatchingBrackets = highlightMatchingBrackets
        config.tabKeyInsertsTab = tabKeyInsertsTab
        config.indentation = indentation
        config.lineEnding = lineEnding
        config.theme = theme
        return config
    }
}

// MARK: - Character Pair Handling

extension KeystoneConfiguration {
    /// Cached set of closing characters for O(1) lookup
    private static let closingChars: Set<Character> = Set(characterPairs.values)

    /// Determines if a character should trigger auto-insertion of its pair.
    /// Uses NSString for O(1) character access.
    public func shouldAutoInsertPair(for char: Character, in nsText: NSString, at position: Int) -> Character? {
        guard autoInsertPairs else { return nil }
        guard let closingChar = Self.characterPairs[char] else { return nil }

        // For quotes, we skip the expensive inside-string check for performance
        // The trade-off is occasional extra quote insertion, which user can delete
        return closingChar
    }

    /// Determines if typing a closing character should skip over an existing one.
    /// Uses NSString for O(1) character access.
    public func shouldSkipClosingPair(for char: Character, in nsText: NSString, at position: Int) -> Bool {
        guard autoInsertPairs else { return false }
        guard position < nsText.length else { return false }

        // O(1) character access using NSString
        let nextCharCode = nsText.character(at: position)
        guard let nextCharScalar = Unicode.Scalar(nextCharCode) else { return false }
        let nextChar = Character(nextCharScalar)

        // If we're typing a closing bracket and the next char is the same, skip it
        return Self.closingChars.contains(char) && nextChar == char
    }

    /// Determines if deleting should remove both characters of a pair.
    /// Uses NSString for O(1) character access.
    public func shouldDeletePair(in nsText: NSString, at position: Int) -> Bool {
        guard autoInsertPairs else { return false }
        guard position > 0 && position < nsText.length else { return false }

        // O(1) character access using NSString
        let prevCharCode = nsText.character(at: position - 1)
        let currCharCode = nsText.character(at: position)

        guard let prevScalar = Unicode.Scalar(prevCharCode),
              let currScalar = Unicode.Scalar(currCharCode) else { return false }

        let prevChar = Character(prevScalar)
        let currChar = Character(currScalar)

        // Check if we're between a pair
        if let expectedClose = Self.characterPairs[prevChar] {
            return currChar == expectedClose
        }

        return false
    }

    // MARK: - Legacy String-based methods (for compatibility)

    /// Legacy method - converts String to NSString internally
    public func shouldAutoInsertPair(for char: Character, in text: String, at position: Int) -> Character? {
        shouldAutoInsertPair(for: char, in: text as NSString, at: position)
    }

    /// Legacy method - converts String to NSString internally
    public func shouldSkipClosingPair(for char: Character, in text: String, at position: Int) -> Bool {
        shouldSkipClosingPair(for: char, in: text as NSString, at: position)
    }

    /// Legacy method - converts String to NSString internally
    public func shouldDeletePair(in text: String, at position: Int) -> Bool {
        shouldDeletePair(in: text as NSString, at: position)
    }
}
