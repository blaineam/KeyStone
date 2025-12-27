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

    /// Maximum distance to search for matching bracket (performance limit)
    private static let maxSearchDistance = 5000

    /// Finds the matching bracket for the character at the given position.
    /// Uses NSString for O(1) character access.
    /// - Parameters:
    ///   - text: The text content.
    ///   - position: The character offset to check.
    /// - Returns: A `BracketMatch` if a matching bracket is found, otherwise `nil`.
    public static func findMatch(in text: String, at position: Int) -> BracketMatch? {
        let nsText = text as NSString
        guard position >= 0 && position < nsText.length else { return nil }

        let charCode = nsText.character(at: position)
        guard let scalar = Unicode.Scalar(charCode) else { return nil }
        let char = Character(scalar)

        // Check if we're on a bracket
        for pair in bracketPairs {
            if char == pair.open {
                // Find closing bracket
                if let closePos = findClosingBracket(in: nsText, from: position, open: pair.open, close: pair.close) {
                    return BracketMatch(openPosition: position, closePosition: closePos, bracketType: pair.open)
                }
            } else if char == pair.close {
                // Find opening bracket
                if let openPos = findOpeningBracket(in: nsText, from: position, open: pair.open, close: pair.close) {
                    return BracketMatch(openPosition: openPos, closePosition: position, bracketType: pair.open)
                }
            }
        }

        return nil
    }

    /// Finds the closest enclosing bracket pair for the given position.
    /// Uses NSString for O(1) character access.
    /// - Parameters:
    ///   - text: The text content.
    ///   - position: The character offset.
    /// - Returns: A `BracketMatch` for the enclosing brackets, or `nil` if none found.
    public static func findEnclosingPair(in text: String, at position: Int) -> BracketMatch? {
        let nsText = text as NSString
        let length = nsText.length
        guard position >= 0 && position <= length else { return nil }

        // Search backwards for an unmatched opening bracket
        for pair in bracketPairs {
            var depth = 0
            var pos = position - 1
            let searchLimit = max(0, position - maxSearchDistance)

            while pos >= searchLimit {
                let charCode = nsText.character(at: pos)
                guard let scalar = Unicode.Scalar(charCode) else {
                    pos -= 1
                    continue
                }
                let char = Character(scalar)

                if char == pair.close { depth += 1 }
                else if char == pair.open {
                    if depth == 0 {
                        // Found unmatched opening bracket
                        if let closePos = findClosingBracket(in: nsText, from: pos, open: pair.open, close: pair.close) {
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

    /// Finds the closing bracket matching the opening bracket at the given position.
    /// Uses NSString for O(1) character access.
    private static func findClosingBracket(in nsText: NSString, from position: Int, open: Character, close: Character) -> Int? {
        var depth = 1
        var pos = position + 1
        let length = nsText.length
        let searchLimit = min(length, position + maxSearchDistance)
        let openCode = open.utf16.first!
        let closeCode = close.utf16.first!

        while pos < searchLimit && depth > 0 {
            let charCode = nsText.character(at: pos)

            if charCode == openCode { depth += 1 }
            else if charCode == closeCode { depth -= 1 }

            if depth == 0 { return pos }
            pos += 1
        }

        return nil
    }

    /// Finds the opening bracket matching the closing bracket at the given position.
    /// Uses NSString for O(1) character access.
    private static func findOpeningBracket(in nsText: NSString, from position: Int, open: Character, close: Character) -> Int? {
        var depth = 1
        var pos = position - 1
        let searchLimit = max(0, position - maxSearchDistance)
        let openCode = open.utf16.first!
        let closeCode = close.utf16.first!

        while pos >= searchLimit && depth > 0 {
            let charCode = nsText.character(at: pos)

            if charCode == closeCode { depth += 1 }
            else if charCode == openCode { depth -= 1 }

            if depth == 0 { return pos }
            pos -= 1
        }

        return nil
    }
}
