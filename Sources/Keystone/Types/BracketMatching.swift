//
//  BracketMatching.swift
//  Keystone
//

import Foundation

/// Represents a matched pair of brackets.
public struct BracketMatch: Equatable, Sendable {
    /// The character offset of the opening bracket.
    public let openPosition: Int
    /// The character offset of the closing bracket.
    public let closePosition: Int
    /// The type of bracket (opening character).
    public let bracketType: Character

    public init(openPosition: Int, closePosition: Int, bracketType: Character) {
        self.openPosition = openPosition
        self.closePosition = closePosition
        self.bracketType = bracketType
    }
}

/// Handles bracket matching logic for the editor.
public struct BracketMatcher: Sendable {
    /// The pairs of brackets to match.
    public static let bracketPairs: [(open: Character, close: Character)] = [
        ("(", ")"),
        ("[", "]"),
        ("{", "}")
    ]

    /// Finds the matching bracket for the character at the given position.
    /// - Parameters:
    ///   - text: The text content.
    ///   - position: The character offset to check.
    /// - Returns: A `BracketMatch` if a matching bracket is found, otherwise `nil`.
    public static func findMatch(in text: String, at position: Int) -> BracketMatch? {
        guard position >= 0 && position < text.count else { return nil }

        let index = text.index(text.startIndex, offsetBy: position)
        let char = text[index]

        // Check if we're on a bracket
        for pair in bracketPairs {
            if char == pair.open {
                // Find closing bracket
                if let closePos = findClosingBracket(in: text, from: position, open: pair.open, close: pair.close) {
                    return BracketMatch(openPosition: position, closePosition: closePos, bracketType: pair.open)
                }
            } else if char == pair.close {
                // Find opening bracket
                if let openPos = findOpeningBracket(in: text, from: position, open: pair.open, close: pair.close) {
                    return BracketMatch(openPosition: openPos, closePosition: position, bracketType: pair.open)
                }
            }
        }

        return nil
    }

    /// Finds the closest enclosing bracket pair for the given position.
    /// - Parameters:
    ///   - text: The text content.
    ///   - position: The character offset.
    /// - Returns: A `BracketMatch` for the enclosing brackets, or `nil` if none found.
    public static func findEnclosingPair(in text: String, at position: Int) -> BracketMatch? {
        // Search backwards for an unmatched opening bracket
        for pair in bracketPairs {
            var depth = 0
            var pos = position - 1

            while pos >= 0 {
                let index = text.index(text.startIndex, offsetBy: pos)
                let char = text[index]

                if char == pair.close { depth += 1 }
                else if char == pair.open {
                    if depth == 0 {
                        // Found unmatched opening bracket
                        if let closePos = findClosingBracket(in: text, from: pos, open: pair.open, close: pair.close) {
                            if closePos >= position {
                                return BracketMatch(openPosition: pos, closePosition: closePos, bracketType: pair.open)
                            }
                        }
                    }
                    depth -= 1
                }
                pos -= 1
            }
        }

        return nil
    }

    private static func findClosingBracket(in text: String, from position: Int, open: Character, close: Character) -> Int? {
        var depth = 1
        var pos = position + 1

        while pos < text.count && depth > 0 {
            let index = text.index(text.startIndex, offsetBy: pos)
            let char = text[index]

            if char == open { depth += 1 }
            else if char == close { depth -= 1 }

            if depth == 0 { return pos }
            pos += 1
        }

        return nil
    }

    private static func findOpeningBracket(in text: String, from position: Int, open: Character, close: Character) -> Int? {
        var depth = 1
        var pos = position - 1

        while pos >= 0 && depth > 0 {
            let index = text.index(text.startIndex, offsetBy: pos)
            let char = text[index]

            if char == close { depth += 1 }
            else if char == open { depth -= 1 }

            if depth == 0 { return pos }
            pos -= 1
        }

        return nil
    }
}
