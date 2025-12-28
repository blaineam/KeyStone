//
//  CommentToggle.swift
//  Keystone
//
//  Toggle comments on selected lines.
//

import Foundation

/// Utility for toggling comments on lines of code.
public struct CommentToggle {

    /// Toggles comments on the given text for the specified lines.
    /// - Parameters:
    ///   - text: The full text content.
    ///   - selectedRange: The NSRange of the current selection/cursor.
    ///   - language: The programming language (determines comment syntax).
    /// - Returns: A tuple with the new text and the new selection range, or nil if commenting is not supported.
    public static func toggleComment(
        text: String,
        selectedRange: NSRange,
        language: KeystoneLanguage
    ) -> (newText: String, newSelection: NSRange)? {
        guard let syntax = language.commentSyntax else {
            return nil // Language doesn't support comments
        }

        // Prefer line comments if available, otherwise use block comments
        if let lineComment = syntax.lineComment {
            return toggleLineComments(text: text, selectedRange: selectedRange, commentPrefix: lineComment)
        } else if let blockComment = syntax.blockComment {
            return toggleBlockComments(text: text, selectedRange: selectedRange, blockStart: blockComment.start, blockEnd: blockComment.end)
        }

        return nil
    }

    /// Toggles line comments (e.g., // or #) on selected lines.
    private static func toggleLineComments(
        text: String,
        selectedRange: NSRange,
        commentPrefix: String
    ) -> (newText: String, newSelection: NSRange) {
        let lines = text.components(separatedBy: "\n")

        // Find which lines are affected by the selection
        var currentOffset = 0
        var affectedLineIndices: [Int] = []

        for (index, line) in lines.enumerated() {
            let lineStart = currentOffset
            let lineEnd = currentOffset + line.count

            // Check if this line overlaps with the selection
            if lineEnd >= selectedRange.location &&
               lineStart <= selectedRange.location + selectedRange.length {
                affectedLineIndices.append(index)
            }

            currentOffset = lineEnd + 1 // +1 for newline
        }

        // If no lines found (shouldn't happen), return original
        if affectedLineIndices.isEmpty {
            return (text, selectedRange)
        }

        // Check if all affected lines are already commented
        let allCommented = affectedLineIndices.allSatisfy { index in
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix(commentPrefix)
        }

        // Determine the minimum indentation level for consistent commenting
        var minIndent = Int.max
        for index in affectedLineIndices {
            let line = lines[index]
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                let indent = line.prefix(while: { $0.isWhitespace }).count
                minIndent = min(minIndent, indent)
            }
        }
        if minIndent == Int.max { minIndent = 0 }

        // Build new lines
        var newLines = lines
        var lengthDelta = 0

        for index in affectedLineIndices {
            let line = lines[index]

            if allCommented {
                // Remove comment
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix(commentPrefix) {
                    let leadingWhitespace = String(line.prefix(while: { $0.isWhitespace }))
                    var uncommented = String(trimmed.dropFirst(commentPrefix.count))
                    // Remove one space after comment prefix if present
                    if uncommented.hasPrefix(" ") {
                        uncommented = String(uncommented.dropFirst())
                        lengthDelta -= 1
                    }
                    newLines[index] = leadingWhitespace + uncommented
                    lengthDelta -= commentPrefix.count
                }
            } else {
                // Add comment
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Empty or whitespace-only line - just add comment at min indent
                    let indent = String(repeating: " ", count: minIndent)
                    newLines[index] = indent + commentPrefix
                    lengthDelta += commentPrefix.count - line.count + minIndent
                } else {
                    // Insert comment at the minimum indentation level
                    let indent = String(line.prefix(minIndent))
                    let rest = String(line.dropFirst(minIndent))
                    newLines[index] = indent + commentPrefix + " " + rest
                    lengthDelta += commentPrefix.count + 1 // +1 for space
                }
            }
        }

        let newText = newLines.joined(separator: "\n")

        // Adjust selection to cover all modified lines
        var newSelectionStart = 0
        for i in 0..<affectedLineIndices.first! {
            newSelectionStart += newLines[i].count + 1
        }

        var newSelectionLength = 0
        for i in affectedLineIndices {
            newSelectionLength += newLines[i].count
            if i < affectedLineIndices.last! {
                newSelectionLength += 1 // newline
            }
        }

        return (newText, NSRange(location: newSelectionStart, length: newSelectionLength))
    }

    /// Toggles block comments (e.g., <!-- --> or /* */) on selected text.
    private static func toggleBlockComments(
        text: String,
        selectedRange: NSRange,
        blockStart: String,
        blockEnd: String
    ) -> (newText: String, newSelection: NSRange) {
        let nsText = text as NSString
        let lines = text.components(separatedBy: "\n")

        // Find which lines are affected by the selection
        var currentOffset = 0
        var affectedLineIndices: [Int] = []

        for (index, line) in lines.enumerated() {
            let lineStart = currentOffset
            let lineEnd = currentOffset + line.count

            // Check if this line overlaps with the selection
            if lineEnd >= selectedRange.location &&
               lineStart <= selectedRange.location + selectedRange.length {
                affectedLineIndices.append(index)
            }

            currentOffset = lineEnd + 1 // +1 for newline
        }

        // If no lines found, return original
        if affectedLineIndices.isEmpty {
            return (text, selectedRange)
        }

        // Get the full range of affected lines
        var lineRangeStart = 0
        for i in 0..<affectedLineIndices.first! {
            lineRangeStart += lines[i].count + 1
        }

        var lineRangeEnd = lineRangeStart
        for i in affectedLineIndices {
            lineRangeEnd += lines[i].count
            if i < lines.count - 1 {
                lineRangeEnd += 1 // newline
            }
        }

        // Get the text of affected lines
        let affectedText = affectedLineIndices.map { lines[$0] }.joined(separator: "\n")
        let trimmed = affectedText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if already commented
        if trimmed.hasPrefix(blockStart) && trimmed.hasSuffix(blockEnd) {
            // Try to remove block comments
            // Find the block comment markers in the affected text
            if affectedText.range(of: blockStart) != nil,
               let endRange = affectedText.range(of: blockEnd, options: .backwards) {
                var newAffected = affectedText
                // Remove end first (so indices don't shift)
                newAffected.removeSubrange(endRange)
                if let newStartRange = newAffected.range(of: blockStart) {
                    newAffected.removeSubrange(newStartRange)
                }

                let newText = nsText.replacingCharacters(
                    in: NSRange(location: lineRangeStart, length: lineRangeEnd - lineRangeStart),
                    with: newAffected
                )

                return (newText, NSRange(location: lineRangeStart, length: newAffected.count))
            }
        }

        // Add block comments
        // Determine minimum indentation
        var minIndent = Int.max
        for index in affectedLineIndices {
            let line = lines[index]
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                let indent = line.prefix(while: { $0.isWhitespace }).count
                minIndent = min(minIndent, indent)
            }
        }
        if minIndent == Int.max { minIndent = 0 }

        var newLines: [String] = []

        for (i, lineIndex) in affectedLineIndices.enumerated() {
            let line = lines[lineIndex]
            if i == 0 {
                // First line: add block start
                let leadingSpace = String(line.prefix(minIndent))
                let rest = String(line.dropFirst(minIndent))
                newLines.append(leadingSpace + blockStart + " " + rest)
            } else if i == affectedLineIndices.count - 1 {
                // Last line: add block end
                newLines.append(line + " " + blockEnd)
            } else {
                newLines.append(line)
            }
        }

        // Handle single line case
        if affectedLineIndices.count == 1 {
            let line = lines[affectedLineIndices[0]]
            let leadingSpace = String(line.prefix(minIndent))
            let rest = String(line.dropFirst(minIndent))
            newLines = [leadingSpace + blockStart + " " + rest + " " + blockEnd]
        }

        let newAffected = newLines.joined(separator: "\n")
        let newText = nsText.replacingCharacters(
            in: NSRange(location: lineRangeStart, length: lineRangeEnd - lineRangeStart),
            with: newAffected
        )

        return (newText, NSRange(location: lineRangeStart, length: newAffected.count))
    }
}
