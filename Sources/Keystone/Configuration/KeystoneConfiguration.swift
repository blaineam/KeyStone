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

    // MARK: - Initialization

    public init() {}

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
    /// Determines if a character should trigger auto-insertion of its pair.
    /// - Parameters:
    ///   - char: The character being typed.
    ///   - text: The current text content.
    ///   - position: The current cursor position.
    /// - Returns: The closing character to insert, or nil if no auto-insertion should occur.
    public func shouldAutoInsertPair(for char: Character, in text: String, at position: Int) -> Character? {
        guard autoInsertPairs else { return nil }
        guard let closingChar = Self.characterPairs[char] else { return nil }

        // For quotes, check if we're already inside a string
        if char == "\"" || char == "'" || char == "`" {
            // Simple heuristic: count occurrences before cursor
            let textBefore = String(text.prefix(position))
            let count = textBefore.filter { $0 == char }.count
            // If odd number, we're inside a string - don't auto-insert
            if count % 2 != 0 { return nil }
        }

        return closingChar
    }

    /// Determines if typing a closing character should skip over an existing one.
    /// - Parameters:
    ///   - char: The character being typed.
    ///   - text: The current text content.
    ///   - position: The current cursor position.
    /// - Returns: True if the character should be skipped, false otherwise.
    public func shouldSkipClosingPair(for char: Character, in text: String, at position: Int) -> Bool {
        guard autoInsertPairs else { return false }
        guard position < text.count else { return false }

        let index = text.index(text.startIndex, offsetBy: position)
        let nextChar = text[index]

        // If we're typing a closing bracket and the next char is the same, skip it
        let closingChars = Set(Self.characterPairs.values)
        return closingChars.contains(char) && nextChar == char
    }

    /// Determines if deleting should remove both characters of a pair.
    /// - Parameters:
    ///   - text: The current text content.
    ///   - position: The current cursor position.
    /// - Returns: True if both characters of a pair should be deleted.
    public func shouldDeletePair(in text: String, at position: Int) -> Bool {
        guard autoInsertPairs else { return false }
        guard position > 0 && position < text.count else { return false }

        let prevIndex = text.index(text.startIndex, offsetBy: position - 1)
        let currIndex = text.index(text.startIndex, offsetBy: position)

        let prevChar = text[prevIndex]
        let currChar = text[currIndex]

        // Check if we're between a pair
        if let expectedClose = Self.characterPairs[prevChar] {
            return currChar == expectedClose
        }

        return false
    }
}
