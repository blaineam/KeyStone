//
//  CursorPosition.swift
//  Keystone
//

import Foundation

/// Represents the current cursor position in the editor.
public struct CursorPosition: Equatable, Sendable {
    /// The current line number (1-based).
    public var line: Int
    /// The current column number (1-based).
    public var column: Int
    /// The length of the current selection, or 0 if no selection.
    public var selectionLength: Int
    /// The character offset from the beginning of the document.
    public var offset: Int

    /// Creates a cursor position with the specified values.
    public init(line: Int = 1, column: Int = 1, selectionLength: Int = 0, offset: Int = 0) {
        self.line = line
        self.column = column
        self.selectionLength = selectionLength
        self.offset = offset
    }

    /// Calculates the cursor position from a character offset in the given text.
    /// Uses NSString for O(1) character access instead of Swift String iteration.
    /// - Parameters:
    ///   - offset: The character offset from the beginning.
    ///   - text: The text content.
    ///   - selectionLength: Optional selection length.
    /// - Returns: The calculated cursor position.
    public static func from(offset: Int, in text: String, selectionLength: Int = 0) -> CursorPosition {
        let nsText = text as NSString
        let length = nsText.length
        let safeOffset = min(offset, length)

        var line = 1
        var column = 1
        let newlineCode: unichar = 0x0A // '\n'

        // Use NSString for O(1) character access at each position
        for i in 0..<safeOffset {
            if nsText.character(at: i) == newlineCode {
                line += 1
                column = 1
            } else {
                column += 1
            }
        }

        return CursorPosition(
            line: line,
            column: column,
            selectionLength: selectionLength,
            offset: offset
        )
    }

    /// Calculates the character offset from a line and column position.
    /// - Parameters:
    ///   - line: The target line number (1-based).
    ///   - column: The target column number (1-based).
    ///   - text: The text content.
    /// - Returns: The character offset, or nil if the position is invalid.
    public static func offset(line targetLine: Int, column targetColumn: Int, in text: String) -> Int? {
        guard targetLine >= 1 && targetColumn >= 1 else { return nil }

        var currentLine = 1
        var currentColumn = 1
        var offset = 0

        for (index, char) in text.enumerated() {
            if currentLine == targetLine && currentColumn == targetColumn {
                return index
            }

            if currentLine > targetLine {
                // Past target line - return start of target line
                return offset
            }

            if char == "\n" {
                if currentLine == targetLine {
                    // Requested column is past end of line
                    return index
                }
                currentLine += 1
                currentColumn = 1
            } else {
                currentColumn += 1
            }

            offset = index + 1
        }

        // Handle end of file
        if currentLine == targetLine {
            return min(offset, text.count)
        }

        return text.count
    }
}
