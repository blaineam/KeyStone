//
//  CommentToggle.swift
//  Keystone
//
//  Toggle comments on selected lines.
//

import Foundation

/// Result of a comment toggle operation with range information.
public struct CommentToggleResult {
    /// The range in the original text that was replaced.
    public let replacedRange: NSRange
    /// The replacement text for that range.
    public let replacementText: String
    /// The new cursor position after the operation.
    public let newCursorOffset: Int
}

/// Utility for toggling comments on lines of code.
public struct CommentToggle {

    /// Toggles comments on the given text for the specified lines.
    /// Returns the range that was replaced and the replacement text (for efficient partial updates).
    /// - Parameters:
    ///   - text: The full text content.
    ///   - selectedRange: The NSRange of the current selection/cursor.
    ///   - language: The programming language (determines comment syntax).
    /// - Returns: A CommentToggleResult with the replaced range and replacement text, or nil if commenting is not supported.
    public static func toggleCommentWithRange(
        text: String,
        selectedRange: NSRange,
        language: KeystoneLanguage
    ) -> CommentToggleResult? {
        // For HTML/XML, check if we're inside a <style> or <script> block
        if language == .html || language == .xml {
            if let embeddedLanguage = detectEmbeddedLanguage(text: text, at: selectedRange.location) {
                // Use the embedded language's comment syntax
                if let syntax = embeddedLanguage.commentSyntax {
                    if let lineComment = syntax.lineComment {
                        return toggleLineCommentsWithRange(text: text, selectedRange: selectedRange, commentPrefix: lineComment)
                    } else if let blockComment = syntax.blockComment {
                        return toggleBlockCommentsWithRange(text: text, selectedRange: selectedRange, blockStart: blockComment.start, blockEnd: blockComment.end)
                    }
                }
            }
        }

        guard let syntax = language.commentSyntax else {
            return nil // Language doesn't support comments
        }

        // Prefer line comments if available, otherwise use block comments
        if let lineComment = syntax.lineComment {
            return toggleLineCommentsWithRange(text: text, selectedRange: selectedRange, commentPrefix: lineComment)
        } else if let blockComment = syntax.blockComment {
            return toggleBlockCommentsWithRange(text: text, selectedRange: selectedRange, blockStart: blockComment.start, blockEnd: blockComment.end)
        }

        return nil
    }

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
        // For HTML/XML, check if we're inside a <style> or <script> block
        if language == .html || language == .xml {
            if let embeddedLanguage = detectEmbeddedLanguage(text: text, at: selectedRange.location) {
                // Use the embedded language's comment syntax
                if let syntax = embeddedLanguage.commentSyntax {
                    if let lineComment = syntax.lineComment {
                        return toggleLineComments(text: text, selectedRange: selectedRange, commentPrefix: lineComment)
                    } else if let blockComment = syntax.blockComment {
                        return toggleBlockComments(text: text, selectedRange: selectedRange, blockStart: blockComment.start, blockEnd: blockComment.end)
                    }
                }
            }
        }

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

    /// Detects if the cursor is inside an embedded language block (style or script) in HTML.
    /// - Parameters:
    ///   - text: The full text content.
    ///   - offset: The cursor offset to check.
    /// - Returns: The embedded language if inside a style/script block, nil otherwise.
    private static func detectEmbeddedLanguage(text: String, at offset: Int) -> KeystoneLanguage? {
        let nsText = text as NSString
        let textLength = nsText.length

        guard offset >= 0 && offset <= textLength else { return nil }

        // Search backwards from cursor to find opening tags
        let beforeCursor = offset > 0 ? nsText.substring(to: offset) : ""

        // Look for <style> or <script> tags (case insensitive)
        let stylePattern = "<style[^>]*>"
        let scriptPattern = "<script[^>]*>"
        let styleClosePattern = "</style>"
        let scriptClosePattern = "</script>"

        // Find the last opening style/script tag before cursor
        var lastStyleOpen: Range<String.Index>?
        var lastScriptOpen: Range<String.Index>?
        var lastStyleClose: Range<String.Index>?
        var lastScriptClose: Range<String.Index>?

        if let regex = try? NSRegularExpression(pattern: stylePattern, options: .caseInsensitive) {
            let matches = regex.matches(in: beforeCursor, range: NSRange(beforeCursor.startIndex..., in: beforeCursor))
            if let lastMatch = matches.last, let range = Range(lastMatch.range, in: beforeCursor) {
                lastStyleOpen = range
            }
        }

        if let regex = try? NSRegularExpression(pattern: scriptPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: beforeCursor, range: NSRange(beforeCursor.startIndex..., in: beforeCursor))
            if let lastMatch = matches.last, let range = Range(lastMatch.range, in: beforeCursor) {
                lastScriptOpen = range
            }
        }

        // Find closing tags before cursor
        if let range = beforeCursor.range(of: styleClosePattern, options: [.caseInsensitive, .backwards]) {
            lastStyleClose = range
        }

        if let range = beforeCursor.range(of: scriptClosePattern, options: [.caseInsensitive, .backwards]) {
            lastScriptClose = range
        }

        // Check if we're inside a style block
        if let styleOpen = lastStyleOpen {
            let styleOpenEnd = beforeCursor.distance(from: beforeCursor.startIndex, to: styleOpen.upperBound)
            let isClosedBefore = lastStyleClose.map { beforeCursor.distance(from: beforeCursor.startIndex, to: $0.lowerBound) > styleOpenEnd } ?? false

            if !isClosedBefore {
                // We're after an unclosed <style> tag - check if there's a </style> after cursor
                let afterCursor = offset < textLength ? nsText.substring(from: offset) : ""
                if afterCursor.range(of: styleClosePattern, options: .caseInsensitive) != nil {
                    return .css
                }
            }
        }

        // Check if we're inside a script block
        if let scriptOpen = lastScriptOpen {
            let scriptOpenEnd = beforeCursor.distance(from: beforeCursor.startIndex, to: scriptOpen.upperBound)
            let isClosedBefore = lastScriptClose.map { beforeCursor.distance(from: beforeCursor.startIndex, to: $0.lowerBound) > scriptOpenEnd } ?? false

            if !isClosedBefore {
                // We're after an unclosed <script> tag - check if there's a </script> after cursor
                let afterCursor = offset < textLength ? nsText.substring(from: offset) : ""
                if afterCursor.range(of: scriptClosePattern, options: .caseInsensitive) != nil {
                    return .javascript
                }
            }
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
        var lineStartOffsets: [Int] = []

        for (index, line) in lines.enumerated() {
            let lineStart = currentOffset
            lineStartOffsets.append(lineStart)
            let lineEnd = currentOffset + line.count

            // Check if this line overlaps with the selection
            // For zero-length selection (cursor), check if cursor is within or at end of line
            let selectionEnd = selectedRange.location + selectedRange.length
            if selectedRange.length == 0 {
                // Cursor only - find the line containing the cursor
                if selectedRange.location >= lineStart && selectedRange.location <= lineEnd {
                    affectedLineIndices.append(index)
                }
            } else {
                // Selection - find all overlapping lines
                if lineEnd >= selectedRange.location && lineStart < selectionEnd {
                    affectedLineIndices.append(index)
                }
            }

            currentOffset = lineEnd + 1 // +1 for newline
        }

        // If no lines found, return original
        if affectedLineIndices.isEmpty {
            return (text, selectedRange)
        }

        // Check if all affected NON-EMPTY lines are already commented
        // Empty/whitespace-only lines don't count toward the "all commented" check
        var commentedCount = 0
        var nonEmptyCount = 0

        for index in affectedLineIndices {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                nonEmptyCount += 1
                if trimmed.hasPrefix(commentPrefix) {
                    commentedCount += 1
                }
            }
        }

        // If all non-empty lines are commented, we uncomment; otherwise we comment
        let shouldUncomment = nonEmptyCount > 0 && commentedCount == nonEmptyCount

        // Determine the minimum indentation level for consistent commenting
        var minIndent = Int.max
        if !shouldUncomment {
            for index in affectedLineIndices {
                let line = lines[index]
                if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    let indent = line.prefix(while: { $0.isWhitespace }).count
                    minIndent = min(minIndent, indent)
                }
            }
            if minIndent == Int.max { minIndent = 0 }
        }

        // Track how much the cursor position should shift
        let originalCursorOffset = selectedRange.location
        var cursorDelta = 0
        var cursorLineProcessed = false

        // Build new lines
        var newLines = lines

        for index in affectedLineIndices {
            let line = lines[index]
            let lineStart = lineStartOffsets[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if shouldUncomment {
                // Remove comment if this line has one
                if trimmed.hasPrefix(commentPrefix) {
                    let leadingWhitespace = String(line.prefix(while: { $0.isWhitespace }))
                    var uncommented = String(trimmed.dropFirst(commentPrefix.count))
                    var removedLength = commentPrefix.count

                    // Remove one space after comment prefix if present
                    if uncommented.hasPrefix(" ") {
                        uncommented = String(uncommented.dropFirst())
                        removedLength += 1
                    }

                    newLines[index] = leadingWhitespace + uncommented

                    // Adjust cursor if it's on or after the comment on this line
                    if !cursorLineProcessed && originalCursorOffset >= lineStart {
                        let commentStartInLine = leadingWhitespace.count
                        let cursorPositionInLine = originalCursorOffset - lineStart

                        if cursorPositionInLine > commentStartInLine {
                            // Cursor is after the comment prefix
                            cursorDelta -= min(removedLength, cursorPositionInLine - commentStartInLine)
                        }
                        cursorLineProcessed = true
                    }
                }
            } else {
                // Add comment
                if trimmed.isEmpty {
                    // Empty line - don't add comment, preserve as-is
                    // (or optionally add just the comment prefix at minIndent)
                } else {
                    // Insert comment at the minimum indentation level
                    let currentIndent = line.prefix(while: { $0.isWhitespace }).count
                    let indentToUse = min(currentIndent, minIndent)
                    let indent = String(line.prefix(indentToUse))
                    let rest = String(line.dropFirst(indentToUse))
                    let addedLength = commentPrefix.count + 1 // +1 for space

                    newLines[index] = indent + commentPrefix + " " + rest

                    // Adjust cursor if it's on or after the insert point on this line
                    if !cursorLineProcessed && originalCursorOffset >= lineStart {
                        let insertPoint = lineStart + indentToUse
                        if originalCursorOffset >= insertPoint {
                            cursorDelta += addedLength
                        }
                        cursorLineProcessed = true
                    }
                }
            }
        }

        let newText = newLines.joined(separator: "\n")

        // Calculate new cursor position
        let newCursorOffset = max(0, originalCursorOffset + cursorDelta)
        let clampedOffset = min(newCursorOffset, newText.count)

        // Return with cursor at new position (no selection to avoid jumping)
        return (newText, NSRange(location: clampedOffset, length: 0))
    }

    /// Toggles line comments and returns the affected range for efficient partial updates.
    private static func toggleLineCommentsWithRange(
        text: String,
        selectedRange: NSRange,
        commentPrefix: String
    ) -> CommentToggleResult? {
        let lines = text.components(separatedBy: "\n")

        // Find which lines are affected by the selection
        var currentOffset = 0
        var affectedLineIndices: [Int] = []
        var lineStartOffsets: [Int] = []

        for (index, line) in lines.enumerated() {
            let lineStart = currentOffset
            lineStartOffsets.append(lineStart)
            let lineEnd = currentOffset + line.count

            let selectionEnd = selectedRange.location + selectedRange.length
            if selectedRange.length == 0 {
                if selectedRange.location >= lineStart && selectedRange.location <= lineEnd {
                    affectedLineIndices.append(index)
                }
            } else {
                if lineEnd >= selectedRange.location && lineStart < selectionEnd {
                    affectedLineIndices.append(index)
                }
            }

            currentOffset = lineEnd + 1
        }

        if affectedLineIndices.isEmpty {
            return nil
        }

        // Calculate the range of affected lines
        let firstLineIndex = affectedLineIndices.first!
        let lastLineIndex = affectedLineIndices.last!
        let rangeStart = lineStartOffsets[firstLineIndex]
        let rangeEnd = lineStartOffsets[lastLineIndex] + lines[lastLineIndex].count

        // Check if all affected NON-EMPTY lines are already commented
        var commentedCount = 0
        var nonEmptyCount = 0

        for index in affectedLineIndices {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                nonEmptyCount += 1
                if trimmed.hasPrefix(commentPrefix) {
                    commentedCount += 1
                }
            }
        }

        let shouldUncomment = nonEmptyCount > 0 && commentedCount == nonEmptyCount

        // Determine the minimum indentation level for consistent commenting
        var minIndent = Int.max
        if !shouldUncomment {
            for index in affectedLineIndices {
                let line = lines[index]
                if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    let indent = line.prefix(while: { $0.isWhitespace }).count
                    minIndent = min(minIndent, indent)
                }
            }
            if minIndent == Int.max { minIndent = 0 }
        }

        // Build the replacement text for just the affected lines
        var newLinesForRange: [String] = []

        for index in affectedLineIndices {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if shouldUncomment {
                if trimmed.hasPrefix(commentPrefix) {
                    let leadingWhitespace = String(line.prefix(while: { $0.isWhitespace }))
                    var uncommented = String(trimmed.dropFirst(commentPrefix.count))
                    if uncommented.hasPrefix(" ") {
                        uncommented = String(uncommented.dropFirst())
                    }
                    newLinesForRange.append(leadingWhitespace + uncommented)
                } else {
                    newLinesForRange.append(line)
                }
            } else {
                if trimmed.isEmpty {
                    newLinesForRange.append(line)
                } else {
                    let currentIndent = line.prefix(while: { $0.isWhitespace }).count
                    let indentToUse = min(currentIndent, minIndent)
                    let indent = String(line.prefix(indentToUse))
                    let rest = String(line.dropFirst(indentToUse))
                    newLinesForRange.append(indent + commentPrefix + " " + rest)
                }
            }
        }

        let replacementText = newLinesForRange.joined(separator: "\n")
        let replacedRange = NSRange(location: rangeStart, length: rangeEnd - rangeStart)

        // Keep cursor at current position (will be adjusted by text view)
        return CommentToggleResult(
            replacedRange: replacedRange,
            replacementText: replacementText,
            newCursorOffset: selectedRange.location
        )
    }

    /// Toggles block comments and returns the affected range for efficient partial updates.
    private static func toggleBlockCommentsWithRange(
        text: String,
        selectedRange: NSRange,
        blockStart: String,
        blockEnd: String
    ) -> CommentToggleResult? {
        let lines = text.components(separatedBy: "\n")

        var currentOffset = 0
        var affectedLineIndices: [Int] = []
        var lineStartOffsets: [Int] = []

        for (index, line) in lines.enumerated() {
            let lineStart = currentOffset
            lineStartOffsets.append(lineStart)
            let lineEnd = currentOffset + line.count

            let selectionEnd = selectedRange.location + selectedRange.length
            if selectedRange.length == 0 {
                if selectedRange.location >= lineStart && selectedRange.location <= lineEnd {
                    affectedLineIndices.append(index)
                }
            } else {
                if lineEnd >= selectedRange.location && lineStart < selectionEnd {
                    affectedLineIndices.append(index)
                }
            }

            currentOffset = lineEnd + 1
        }

        if affectedLineIndices.isEmpty {
            return nil
        }

        let firstLineIndex = affectedLineIndices.first!
        let lastLineIndex = affectedLineIndices.last!
        let rangeStart = lineStartOffsets[firstLineIndex]
        let rangeEnd = lineStartOffsets[lastLineIndex] + lines[lastLineIndex].count

        let affectedText = affectedLineIndices.map { lines[$0] }.joined(separator: "\n")
        let trimmed = affectedText.trimmingCharacters(in: .whitespacesAndNewlines)

        let isCommented = trimmed.hasPrefix(blockStart) && trimmed.hasSuffix(blockEnd)

        let newAffected: String
        if isCommented {
            // Remove block comments
            var temp = affectedText
            if let endRange = temp.range(of: " " + blockEnd, options: .backwards) {
                temp.removeSubrange(endRange)
            } else if let endRange = temp.range(of: blockEnd, options: .backwards) {
                temp.removeSubrange(endRange)
            }
            if let startRange = temp.range(of: blockStart + " ") {
                temp.removeSubrange(startRange)
            } else if let startRange = temp.range(of: blockStart) {
                temp.removeSubrange(startRange)
            }
            newAffected = temp
        } else {
            // Add block comments
            if affectedLineIndices.count == 1 {
                let line = lines[affectedLineIndices[0]]
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                let leadingSpace = String(line.prefix(while: { $0.isWhitespace }))
                newAffected = leadingSpace + blockStart + " " + trimmedLine + " " + blockEnd
            } else {
                var newLines: [String] = []
                for (i, lineIndex) in affectedLineIndices.enumerated() {
                    let line = lines[lineIndex]
                    if i == 0 {
                        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                        let leadingSpace = String(line.prefix(while: { $0.isWhitespace }))
                        newLines.append(leadingSpace + blockStart + " " + trimmedLine)
                    } else if i == affectedLineIndices.count - 1 {
                        newLines.append(line + " " + blockEnd)
                    } else {
                        newLines.append(line)
                    }
                }
                newAffected = newLines.joined(separator: "\n")
            }
        }

        return CommentToggleResult(
            replacedRange: NSRange(location: rangeStart, length: rangeEnd - rangeStart),
            replacementText: newAffected,
            newCursorOffset: selectedRange.location
        )
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

            let selectionEnd = selectedRange.location + selectedRange.length
            if selectedRange.length == 0 {
                if selectedRange.location >= lineStart && selectedRange.location <= lineEnd {
                    affectedLineIndices.append(index)
                }
            } else {
                if lineEnd >= selectedRange.location && lineStart < selectionEnd {
                    affectedLineIndices.append(index)
                }
            }

            currentOffset = lineEnd + 1
        }

        if affectedLineIndices.isEmpty {
            return (text, selectedRange)
        }

        // Get the full range of affected lines
        var lineRangeStart = 0
        for i in 0..<affectedLineIndices.first! {
            lineRangeStart += lines[i].count + 1
        }

        var lineRangeLength = 0
        for i in affectedLineIndices {
            lineRangeLength += lines[i].count
            if i < affectedLineIndices.last! {
                lineRangeLength += 1 // newline between affected lines
            }
        }

        // Get the text of affected lines
        let affectedText = affectedLineIndices.map { lines[$0] }.joined(separator: "\n")
        let trimmed = affectedText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if already wrapped in block comments
        let isCommented = trimmed.hasPrefix(blockStart) && trimmed.hasSuffix(blockEnd)

        let originalCursorOffset = selectedRange.location

        if isCommented {
            // Remove block comments - simple approach: find and remove markers with optional surrounding space
            var newAffected = affectedText

            // Remove block end (with optional preceding space)
            if let endRange = newAffected.range(of: " " + blockEnd, options: .backwards) {
                newAffected.removeSubrange(endRange)
            } else if let endRange = newAffected.range(of: blockEnd, options: .backwards) {
                newAffected.removeSubrange(endRange)
            }

            // Remove block start (with optional trailing space)
            if let startRange = newAffected.range(of: blockStart + " ") {
                newAffected.removeSubrange(startRange)
            } else if let startRange = newAffected.range(of: blockStart) {
                newAffected.removeSubrange(startRange)
            }

            let newText = nsText.replacingCharacters(
                in: NSRange(location: lineRangeStart, length: lineRangeLength),
                with: newAffected
            )

            // Keep cursor roughly in same position
            let lengthDiff = affectedText.count - newAffected.count
            let newCursorOffset = max(lineRangeStart, originalCursorOffset - lengthDiff)
            return (newText, NSRange(location: min(newCursorOffset, newText.count), length: 0))
        }

        // Add block comments
        // For single line, wrap inline: /* content */
        // For multi-line, put on separate lines or inline depending on style
        let newAffected: String
        if affectedLineIndices.count == 1 {
            // Single line - inline comment
            let line = lines[affectedLineIndices[0]]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            let leadingSpace = String(line.prefix(while: { $0.isWhitespace }))
            newAffected = leadingSpace + blockStart + " " + trimmedLine + " " + blockEnd
        } else {
            // Multi-line - wrap first and last
            var newLines: [String] = []
            for (i, lineIndex) in affectedLineIndices.enumerated() {
                let line = lines[lineIndex]
                if i == 0 {
                    let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                    let leadingSpace = String(line.prefix(while: { $0.isWhitespace }))
                    newLines.append(leadingSpace + blockStart + " " + trimmedLine)
                } else if i == affectedLineIndices.count - 1 {
                    newLines.append(line + " " + blockEnd)
                } else {
                    newLines.append(line)
                }
            }
            newAffected = newLines.joined(separator: "\n")
        }

        let newText = nsText.replacingCharacters(
            in: NSRange(location: lineRangeStart, length: lineRangeLength),
            with: newAffected
        )

        // Adjust cursor for added comment markers
        let lengthDiff = newAffected.count - affectedText.count
        let newCursorOffset = originalCursorOffset + (originalCursorOffset > lineRangeStart ? lengthDiff : 0)
        return (newText, NSRange(location: min(newCursorOffset, newText.count), length: 0))
    }
}
