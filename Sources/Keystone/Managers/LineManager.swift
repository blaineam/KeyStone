//
//  LineManager.swift
//  Keystone
//
//  Efficient line tracking for O(1) lookups, inspired by Runestone framework.
//  Maintains a cache of line positions for fast line-to-offset and offset-to-line conversions.
//

import Foundation

/// Represents a single line in the document
public struct DocumentLine {
    /// The line number (1-based)
    public let number: Int
    /// The starting character offset of this line
    public let startOffset: Int
    /// The length of this line (including newline character if present)
    public let length: Int
    /// The length of the line content (excluding newline)
    public let contentLength: Int

    /// The ending character offset of this line (exclusive)
    public var endOffset: Int {
        startOffset + length
    }

    /// The range of this line in the document
    public var range: NSRange {
        NSRange(location: startOffset, length: length)
    }

    /// The range of visible content (excluding newline)
    public var contentRange: NSRange {
        NSRange(location: startOffset, length: contentLength)
    }
}

/// Manages line information for efficient O(1) lookups
///
/// Instead of scanning the entire document to find line positions,
/// this class maintains a cache of line start offsets that's updated
/// incrementally when text changes.
public class LineManager {
    /// Cached line start offsets - index i contains the start offset of line i+1
    private var lineStartOffsets: [Int] = [0]

    /// Cached line lengths
    private var lineLengths: [Int] = []

    /// Total number of lines
    public var lineCount: Int {
        lineStartOffsets.count
    }

    /// The total character count of the document
    public private(set) var totalLength: Int = 0

    // MARK: - Initialization

    public init() {}

    /// Rebuilds the entire line cache from the given text
    /// Call this when the document is first loaded or after major changes
    public func rebuild(from text: String) {
        lineStartOffsets = [0]
        lineLengths = []
        totalLength = text.utf16.count

        guard !text.isEmpty else {
            lineLengths = [0]
            return
        }

        var currentOffset = 0
        var lineStart = 0

        for char in text {
            currentOffset += char.utf16.count
            if char == "\n" || char == "\r" {
                // Handle \r\n as single newline
                if char == "\r" && currentOffset < totalLength {
                    let nextIndex = text.index(text.startIndex, offsetBy: currentOffset)
                    if nextIndex < text.endIndex && text[nextIndex] == "\n" {
                        currentOffset += 1
                    }
                }
                lineLengths.append(currentOffset - lineStart)
                lineStart = currentOffset
                if currentOffset < totalLength {
                    lineStartOffsets.append(currentOffset)
                }
            }
        }

        // Add final line if text doesn't end with newline
        if lineStart <= totalLength {
            lineLengths.append(totalLength - lineStart)
        }
    }

    /// Rebuilds using NSString for better performance with large texts
    public func rebuild(from nsString: NSString) {
        lineStartOffsets = [0]
        lineLengths = []
        totalLength = nsString.length

        guard totalLength > 0 else {
            lineLengths = [0]
            return
        }

        var lineStart = 0
        var index = 0

        while index < totalLength {
            let char = nsString.character(at: index)
            index += 1

            if char == 0x0A || char == 0x0D { // \n or \r
                // Handle \r\n as single newline
                if char == 0x0D && index < totalLength && nsString.character(at: index) == 0x0A {
                    index += 1
                }
                lineLengths.append(index - lineStart)
                lineStart = index
                if index < totalLength {
                    lineStartOffsets.append(index)
                }
            }
        }

        // Add final line
        if lineStart <= totalLength {
            lineLengths.append(totalLength - lineStart)
        }
    }

    // MARK: - O(1) Lookups (after cache is built)

    /// Returns the line containing the given character offset
    /// Uses binary search for O(log n) complexity
    public func lineContaining(offset: Int) -> DocumentLine? {
        guard offset >= 0 && offset <= totalLength else { return nil }
        guard !lineStartOffsets.isEmpty else { return nil }

        // Binary search to find the line
        var low = 0
        var high = lineStartOffsets.count - 1

        while low < high {
            let mid = (low + high + 1) / 2
            if lineStartOffsets[mid] <= offset {
                low = mid
            } else {
                high = mid - 1
            }
        }

        return line(at: low + 1) // Convert to 1-based
    }

    /// Returns the line at the given 1-based line number
    public func line(at lineNumber: Int) -> DocumentLine? {
        let index = lineNumber - 1
        guard index >= 0 && index < lineStartOffsets.count else { return nil }

        let startOffset = lineStartOffsets[index]
        let length = index < lineLengths.count ? lineLengths[index] : 0

        // Content length excludes trailing newline
        var contentLength = length
        if contentLength > 0 && index < lineLengths.count {
            // Check for trailing newline
            if contentLength >= 2 {
                // Could be \r\n
                contentLength = max(0, length - (length > 1 ? 1 : 0))
            } else if contentLength >= 1 {
                contentLength = max(0, length - 1)
            }
        }

        return DocumentLine(
            number: lineNumber,
            startOffset: startOffset,
            length: length,
            contentLength: min(contentLength, length)
        )
    }

    /// Returns the starting offset of the given line (1-based)
    public func startOffset(forLine lineNumber: Int) -> Int? {
        let index = lineNumber - 1
        guard index >= 0 && index < lineStartOffsets.count else { return nil }
        return lineStartOffsets[index]
    }

    /// Returns lines in the given offset range
    public func lines(in range: NSRange) -> [DocumentLine] {
        guard let firstLine = lineContaining(offset: range.location) else { return [] }
        guard let lastLine = lineContaining(offset: max(0, range.location + range.length - 1)) else {
            return [firstLine]
        }

        var result: [DocumentLine] = []
        for lineNum in firstLine.number...lastLine.number {
            if let line = line(at: lineNum) {
                result.append(line)
            }
        }
        return result
    }

    /// Returns the range of lines visible in the given viewport
    public func visibleLineRange(viewportStart: Int, viewportEnd: Int) -> ClosedRange<Int>? {
        guard let firstLine = lineContaining(offset: viewportStart),
              let lastLine = lineContaining(offset: min(viewportEnd, max(0, totalLength - 1))) else {
            return nil
        }
        return firstLine.number...lastLine.number
    }

    // MARK: - Incremental Updates

    /// Updates the line cache after text is inserted
    /// - Parameters:
    ///   - range: The range where text was inserted (location = insertion point, length = 0)
    ///   - insertedText: The text that was inserted
    public func didInsert(at location: Int, text insertedText: String) {
        let insertedLength = insertedText.utf16.count
        guard insertedLength > 0 else { return }

        totalLength += insertedLength

        // Find the line where insertion occurred
        guard let affectedLine = lineContaining(offset: location) else {
            // Inserting at end
            rebuild(from: NSString(string: insertedText))
            return
        }

        let lineIndex = affectedLine.number - 1

        // Count newlines in inserted text
        var newLines: [Int] = []
        var offset = 0
        for char in insertedText {
            offset += char.utf16.count
            if char == "\n" || char == "\r" {
                newLines.append(location + offset)
            }
        }

        if newLines.isEmpty {
            // No new lines - just update the length of current line
            if lineIndex < lineLengths.count {
                lineLengths[lineIndex] += insertedLength
            }
            // Update all subsequent line offsets
            for i in (lineIndex + 1)..<lineStartOffsets.count {
                lineStartOffsets[i] += insertedLength
            }
        } else {
            // New lines were added - need to rebuild from this point
            // For simplicity, rebuild the whole cache (could be optimized)
            // A full implementation would splice in the new lines
            rebuildNeeded = true
        }
    }

    /// Updates the line cache after text is deleted
    public func didDelete(range: NSRange) {
        guard range.length > 0 else { return }
        totalLength -= range.length

        // For simplicity, mark as needing rebuild
        // A full implementation would update incrementally
        rebuildNeeded = true
    }

    /// Flag indicating cache needs full rebuild
    public private(set) var rebuildNeeded = false

    /// Clears the rebuild needed flag
    public func clearRebuildFlag() {
        rebuildNeeded = false
    }
}

// MARK: - Line Height Cache

/// Caches line heights for efficient viewport calculations
public class LineHeightCache {
    /// Default line height when not measured
    public var defaultLineHeight: CGFloat = 17.0

    /// Cached heights for each line (1-indexed internally as 0-indexed array)
    private var lineHeights: [CGFloat] = []

    /// Cumulative heights up to each line (for fast offset lookups)
    private var cumulativeHeights: [CGFloat] = [0]

    /// Total height of all lines
    public var totalHeight: CGFloat {
        cumulativeHeights.last ?? 0
    }

    /// Number of cached lines
    public var lineCount: Int {
        lineHeights.count
    }

    // MARK: - Building Cache

    /// Rebuilds the cache for the given number of lines with default height
    public func rebuild(lineCount: Int, defaultHeight: CGFloat) {
        self.defaultLineHeight = defaultHeight
        lineHeights = Array(repeating: defaultHeight, count: lineCount)
        rebuildCumulativeHeights()
    }

    /// Updates the height of a specific line
    public func setHeight(_ height: CGFloat, forLine lineNumber: Int) {
        let index = lineNumber - 1
        guard index >= 0 && index < lineHeights.count else { return }

        let oldHeight = lineHeights[index]
        guard oldHeight != height else { return }

        lineHeights[index] = height

        // Update cumulative heights from this point forward
        let diff = height - oldHeight
        for i in (index + 1)..<cumulativeHeights.count {
            cumulativeHeights[i] += diff
        }
    }

    /// Returns the height of the given line
    public func height(forLine lineNumber: Int) -> CGFloat {
        let index = lineNumber - 1
        guard index >= 0 && index < lineHeights.count else { return defaultLineHeight }
        return lineHeights[index]
    }

    /// Returns the Y offset for the given line
    public func yOffset(forLine lineNumber: Int) -> CGFloat {
        let index = lineNumber - 1
        guard index >= 0 && index < cumulativeHeights.count else { return 0 }
        return cumulativeHeights[index]
    }

    /// Returns the line at the given Y offset
    public func lineAt(yOffset: CGFloat) -> Int {
        guard !cumulativeHeights.isEmpty else { return 1 }

        // Binary search
        var low = 0
        var high = cumulativeHeights.count - 1

        while low < high {
            let mid = (low + high + 1) / 2
            if cumulativeHeights[mid] <= yOffset {
                low = mid
            } else {
                high = mid - 1
            }
        }

        return low + 1 // Convert to 1-based line number
    }

    /// Returns the range of lines visible in the given viewport
    public func visibleLines(viewportTop: CGFloat, viewportBottom: CGFloat) -> ClosedRange<Int> {
        let firstLine = lineAt(yOffset: viewportTop)
        let lastLine = lineAt(yOffset: viewportBottom)
        return firstLine...max(firstLine, lastLine)
    }

    // MARK: - Private

    private func rebuildCumulativeHeights() {
        cumulativeHeights = [0]
        var cumulative: CGFloat = 0
        for height in lineHeights {
            cumulative += height
            cumulativeHeights.append(cumulative)
        }
    }
}
