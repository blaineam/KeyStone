//
//  CodeFolding.swift
//  Keystone
//
//  Code folding support for collapsible code regions.
//

import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Custom attribute keys for code folding
public extension NSAttributedString.Key {
    static let foldedContent = NSAttributedString.Key("KeystoneFoldedContent")
    static let foldedRegionId = NSAttributedString.Key("KeystoneFoldedRegionId")
    static let foldIndicatorRegionId = NSAttributedString.Key("KeystoneFoldIndicatorRegionId")
}

/// Represents a foldable region in the code.
public struct FoldableRegion: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// The starting line number (1-based).
    public let startLine: Int
    /// The ending line number (1-based).
    public let endLine: Int
    /// The character offset where the region starts.
    public let startOffset: Int
    /// The character offset where the region ends (exclusive).
    public let endOffset: Int
    /// The type of foldable region.
    public let type: FoldType
    /// Whether this region is currently folded.
    public var isFolded: Bool
    /// The preview text shown when folded.
    public let preview: String

    public init(
        id: UUID = UUID(),
        startLine: Int,
        endLine: Int,
        startOffset: Int = 0,
        endOffset: Int = 0,
        type: FoldType,
        isFolded: Bool = false,
        preview: String = "..."
    ) {
        self.id = id
        self.startLine = startLine
        self.endLine = endLine
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.type = type
        self.isFolded = isFolded
        self.preview = preview
    }

    /// The number of lines this region spans.
    public var lineCount: Int {
        endLine - startLine + 1
    }

    /// The character range to hide when folded (from end of first line to end of region)
    public var hiddenRange: NSRange {
        // We hide from after the first line's newline to the end of the region
        NSRange(location: startOffset, length: endOffset - startOffset)
    }
}

/// Types of foldable regions.
public enum FoldType: String, Sendable {
    case braces       // { }
    case brackets     // [ ]
    case parentheses  // ( )
    case comment      // Multi-line comments
    case imports      // Import statements
    case function     // Function/method body
    case `class`      // Class body
    case `struct`     // Struct body
    case region       // #region / #pragma mark
}

/// Manages code folding for an editor.
@MainActor
public class CodeFoldingManager: ObservableObject {
    /// All detected foldable regions.
    @Published public private(set) var regions: [FoldableRegion] = []

    /// Currently folded region IDs.
    @Published public private(set) var foldedRegionIds: Set<UUID> = []

    /// Whether folding is enabled (tied to showLineNumbers).
    @Published public var isEnabled: Bool = true

    /// Cache of line offsets for fast lookup.
    private var lineOffsets: [Int] = []

    /// The last analyzed text (to avoid re-analyzing unchanged text).
    private var lastAnalyzedText: String = ""

    /// Dictionary for O(1) region lookup by start line.
    private var regionsByStartLine: [Int: FoldableRegion] = [:]

    /// Set of hidden line numbers for O(1) lookup (rebuilt when fold state changes).
    private var hiddenLines: Set<Int> = []

    /// Whether hidden lines cache needs to be rebuilt.
    private var hiddenLinesCacheDirty = true

    public init() {}

    /// Analyzes the text and detects foldable regions.
    /// - Parameter text: The source code to analyze.
    public func analyze(_ text: String) {
        // Skip if text hasn't changed
        guard text != lastAnalyzedText else { return }
        lastAnalyzedText = text

        var newRegions: [FoldableRegion] = []
        let lines = text.components(separatedBy: .newlines)

        // Build line offset cache for fast offset lookups
        buildLineOffsets(from: text)

        // Track bracket pairs for folding with offsets
        var braceStack: [(line: Int, column: Int, offset: Int)] = []
        var bracketStack: [(line: Int, column: Int, offset: Int)] = []
        var parenStack: [(line: Int, column: Int, offset: Int)] = []

        // Track multi-line comments
        var commentStart: (line: Int, offset: Int)?

        var currentOffset = 0

        for (lineIndex, line) in lines.enumerated() {
            let lineNumber = lineIndex + 1
            let lineStartOffset = currentOffset

            // Check for multi-line comment start/end
            if line.contains("/*") && !line.contains("*/") {
                if let range = line.range(of: "/*") {
                    let commentOffset = lineStartOffset + line.distance(from: line.startIndex, to: range.lowerBound)
                    commentStart = (line: lineNumber, offset: commentOffset)
                }
            } else if let start = commentStart, line.contains("*/") {
                if let range = line.range(of: "*/") {
                    let endOffset = lineStartOffset + line.distance(from: line.startIndex, to: range.upperBound)
                    let preview = extractPreview(from: lines, startLine: start.line - 1)
                    newRegions.append(FoldableRegion(
                        startLine: start.line,
                        endLine: lineNumber,
                        startOffset: start.offset,
                        endOffset: endOffset,
                        type: .comment,
                        preview: preview
                    ))
                }
                commentStart = nil
            }

            // Check for region markers
            if line.contains("// MARK:") || line.contains("#pragma mark") || line.contains("#region") {
                // Find the next marker or end of file
                var searchOffset = currentOffset + line.count + 1 // +1 for newline
                for nextLineIndex in (lineIndex + 1)..<lines.count {
                    let nextContent = lines[nextLineIndex]
                    if nextContent.contains("// MARK:") || nextContent.contains("#pragma mark") ||
                       nextContent.contains("#region") || nextContent.contains("#endregion") {
                        if nextLineIndex > lineIndex + 1 {
                            let preview = extractPreview(from: lines, startLine: lineIndex)
                            newRegions.append(FoldableRegion(
                                startLine: lineNumber,
                                endLine: nextLineIndex,
                                startOffset: lineStartOffset,
                                endOffset: searchOffset,
                                type: .region,
                                preview: preview
                            ))
                        }
                        break
                    }
                    searchOffset += nextContent.count + 1
                }
            }

            // Track braces with offsets
            for (charIndex, char) in line.enumerated() {
                let charOffset = lineStartOffset + charIndex
                switch char {
                case "{":
                    braceStack.append((line: lineNumber, column: charIndex, offset: charOffset))
                case "}":
                    if let start = braceStack.popLast(), start.line < lineNumber {
                        let preview = extractPreview(from: lines, startLine: start.line - 1)
                        // Find end of current line for the hidden range
                        let lineEndOffset = lineStartOffset + line.count
                        newRegions.append(FoldableRegion(
                            startLine: start.line,
                            endLine: lineNumber,
                            startOffset: getEndOfLine(start.line),
                            endOffset: lineEndOffset,
                            type: .braces,
                            preview: preview
                        ))
                    }
                case "[":
                    bracketStack.append((line: lineNumber, column: charIndex, offset: charOffset))
                case "]":
                    if let start = bracketStack.popLast(), start.line < lineNumber {
                        let preview = extractPreview(from: lines, startLine: start.line - 1)
                        let lineEndOffset = lineStartOffset + line.count
                        newRegions.append(FoldableRegion(
                            startLine: start.line,
                            endLine: lineNumber,
                            startOffset: getEndOfLine(start.line),
                            endOffset: lineEndOffset,
                            type: .brackets,
                            preview: preview
                        ))
                    }
                case "(":
                    parenStack.append((line: lineNumber, column: charIndex, offset: charOffset))
                case ")":
                    if let start = parenStack.popLast(), start.line < lineNumber {
                        let preview = extractPreview(from: lines, startLine: start.line - 1)
                        let lineEndOffset = lineStartOffset + line.count
                        newRegions.append(FoldableRegion(
                            startLine: start.line,
                            endLine: lineNumber,
                            startOffset: getEndOfLine(start.line),
                            endOffset: lineEndOffset,
                            type: .parentheses,
                            preview: preview
                        ))
                    }
                default:
                    break
                }
            }

            currentOffset += line.count + 1 // +1 for newline
        }

        // Sort by start line and filter out small regions
        regions = newRegions
            .filter { $0.lineCount >= 2 }
            .sorted { $0.startLine < $1.startLine }

        // Build O(1) lookup dictionary (keep first region if duplicates exist)
        regionsByStartLine = [:]
        for region in regions {
            if regionsByStartLine[region.startLine] == nil {
                regionsByStartLine[region.startLine] = region
            }
        }

        // Preserve fold state for existing regions with same start/end lines
        let oldFoldedIds = foldedRegionIds
        var newFoldedIds = Set<UUID>()

        for region in regions {
            // Find matching old region by line numbers
            if let oldRegion = findPreviousRegion(startLine: region.startLine, endLine: region.endLine),
               oldFoldedIds.contains(oldRegion.id) {
                newFoldedIds.insert(region.id)
            }
        }
        foldedRegionIds = newFoldedIds
        hiddenLinesCacheDirty = true
    }

    /// Finds a region from the previous analysis with matching line numbers.
    private func findPreviousRegion(startLine: Int, endLine: Int) -> FoldableRegion? {
        regions.first { $0.startLine == startLine && $0.endLine == endLine }
    }

    /// Builds the line offset cache.
    private func buildLineOffsets(from text: String) {
        lineOffsets = [0] // Line 1 starts at offset 0
        var offset = 0
        for char in text {
            offset += 1
            if char == "\n" {
                lineOffsets.append(offset)
            }
        }
    }

    /// Gets the offset at the end of a line (before the newline).
    private func getEndOfLine(_ lineNumber: Int) -> Int {
        let lineIndex = lineNumber - 1
        guard lineIndex >= 0 && lineIndex < lineOffsets.count else { return 0 }

        let lineStart = lineOffsets[lineIndex]
        if lineIndex + 1 < lineOffsets.count {
            return lineOffsets[lineIndex + 1] - 1 // Before the newline
        } else {
            return lastAnalyzedText.count
        }
    }

    /// Gets the offset at the start of a line.
    public func getLineStartOffset(_ lineNumber: Int) -> Int {
        let lineIndex = lineNumber - 1
        guard lineIndex >= 0 && lineIndex < lineOffsets.count else { return 0 }
        return lineOffsets[lineIndex]
    }

    private func extractPreview(from lines: [String], startLine: Int) -> String {
        guard startLine >= 0 && startLine < lines.count else { return "..." }
        let line = lines[startLine].trimmingCharacters(in: .whitespaces)
        let maxLength = 40
        if line.count > maxLength {
            return String(line.prefix(maxLength)) + "..."
        }
        return line.isEmpty ? "..." : line
    }

    /// Rebuilds the hidden lines cache from current fold state.
    private func rebuildHiddenLinesCache() {
        hiddenLines.removeAll()
        for region in regions {
            if foldedRegionIds.contains(region.id) {
                // Lines after startLine up to and including endLine are hidden
                for line in (region.startLine + 1)...region.endLine {
                    hiddenLines.insert(line)
                }
            }
        }
        hiddenLinesCacheDirty = false
    }

    /// Toggles the fold state of a region.
    /// - Parameter region: The region to toggle.
    public func toggleFold(_ region: FoldableRegion) {
        if foldedRegionIds.contains(region.id) {
            foldedRegionIds.remove(region.id)
        } else {
            foldedRegionIds.insert(region.id)
        }
        hiddenLinesCacheDirty = true
    }

    /// Folds a specific region.
    /// - Parameter region: The region to fold.
    public func fold(_ region: FoldableRegion) {
        foldedRegionIds.insert(region.id)
        hiddenLinesCacheDirty = true
    }

    /// Unfolds a specific region.
    /// - Parameter region: The region to unfold.
    public func unfold(_ region: FoldableRegion) {
        foldedRegionIds.remove(region.id)
        hiddenLinesCacheDirty = true
    }

    /// Folds all regions.
    public func foldAll() {
        foldedRegionIds = Set(regions.map(\.id))
        hiddenLinesCacheDirty = true
    }

    /// Unfolds all regions.
    public func unfoldAll() {
        foldedRegionIds.removeAll()
        hiddenLinesCacheDirty = true
    }

    /// Checks if a line is hidden due to folding.
    /// Uses cached Set for O(1) lookup.
    /// - Parameter lineNumber: The 1-based line number.
    /// - Returns: True if the line is hidden.
    public func isLineHidden(_ lineNumber: Int) -> Bool {
        guard isEnabled else { return false }
        if hiddenLinesCacheDirty {
            rebuildHiddenLinesCache()
        }
        return hiddenLines.contains(lineNumber)
    }

    /// Checks if a character offset is inside a folded region.
    /// - Parameter offset: The character offset to check.
    /// - Returns: True if the offset is inside a folded (hidden) region.
    public func isOffsetHidden(_ offset: Int) -> Bool {
        guard isEnabled else { return false }
        for region in regions {
            if foldedRegionIds.contains(region.id) &&
               offset > region.startOffset && offset <= region.endOffset {
                return true
            }
        }
        return false
    }

    /// Gets the folded region containing the given offset, if any.
    /// - Parameter offset: The character offset to check.
    /// - Returns: The folded region containing this offset, or nil.
    public func foldedRegion(containingOffset offset: Int) -> FoldableRegion? {
        guard isEnabled else { return nil }
        for region in regions {
            if foldedRegionIds.contains(region.id) &&
               offset >= region.startOffset && offset <= region.endOffset {
                return region
            }
        }
        return nil
    }

    /// Unfolds any regions that contain the given offset.
    /// Useful for auto-unfolding when navigating to a search match.
    /// - Parameter offset: The character offset to unfold around.
    /// - Returns: True if any regions were unfolded.
    @discardableResult
    public func unfoldRegions(containingOffset offset: Int) -> Bool {
        var unfolded = false
        for region in regions {
            if foldedRegionIds.contains(region.id) &&
               offset >= region.startOffset && offset <= region.endOffset {
                foldedRegionIds.remove(region.id)
                unfolded = true
            }
        }
        if unfolded {
            hiddenLinesCacheDirty = true
        }
        return unfolded
    }

    /// Unfolds any regions that contain the given line.
    /// - Parameter lineNumber: The 1-based line number.
    /// - Returns: True if any regions were unfolded.
    @discardableResult
    public func unfoldRegions(containingLine lineNumber: Int) -> Bool {
        var unfolded = false
        for region in regions {
            if foldedRegionIds.contains(region.id) &&
               lineNumber >= region.startLine && lineNumber <= region.endLine {
                foldedRegionIds.remove(region.id)
                unfolded = true
            }
        }
        if unfolded {
            hiddenLinesCacheDirty = true
        }
        return unfolded
    }

    /// Gets the region at a specific line, if any.
    /// Uses cached dictionary for O(1) lookup.
    /// - Parameter lineNumber: The 1-based line number.
    /// - Returns: The foldable region starting at this line, if any.
    public func region(atLine lineNumber: Int) -> FoldableRegion? {
        guard isEnabled else { return nil }
        return regionsByStartLine[lineNumber]
    }

    /// Checks if a line has a foldable region starting.
    /// Uses cached dictionary for O(1) lookup.
    /// - Parameter lineNumber: The 1-based line number.
    /// - Returns: True if a foldable region starts at this line.
    public func hasFoldableRegion(atLine lineNumber: Int) -> Bool {
        guard isEnabled else { return false }
        return regionsByStartLine[lineNumber] != nil
    }

    /// Checks if a region is currently folded.
    /// - Parameter region: The region to check.
    /// - Returns: True if the region is folded.
    public func isFolded(_ region: FoldableRegion) -> Bool {
        foldedRegionIds.contains(region.id)
    }

    /// Gets all currently folded regions sorted by start offset.
    public var foldedRegions: [FoldableRegion] {
        regions.filter { foldedRegionIds.contains($0.id) }
            .sorted { $0.startOffset < $1.startOffset }
    }

    /// Calculates the character range that should be hidden for folded regions.
    /// Returns ranges sorted by start offset, with overlapping ranges merged.
    public var hiddenCharacterRanges: [NSRange] {
        guard isEnabled else { return [] }

        var ranges: [NSRange] = []
        for region in foldedRegions {
            // Hide from after the first line to the end of the region
            let range = region.hiddenRange
            if range.length > 0 {
                ranges.append(range)
            }
        }

        // Merge overlapping ranges
        return mergeRanges(ranges)
    }

    /// Merges overlapping or adjacent ranges.
    private func mergeRanges(_ ranges: [NSRange]) -> [NSRange] {
        guard !ranges.isEmpty else { return [] }

        let sorted = ranges.sorted { $0.location < $1.location }
        var merged: [NSRange] = []
        var current = sorted[0]

        for range in sorted.dropFirst() {
            if range.location <= current.location + current.length {
                // Overlapping or adjacent - extend current
                let newEnd = max(current.location + current.length, range.location + range.length)
                current = NSRange(location: current.location, length: newEnd - current.location)
            } else {
                merged.append(current)
                current = range
            }
        }
        merged.append(current)

        return merged
    }
}
