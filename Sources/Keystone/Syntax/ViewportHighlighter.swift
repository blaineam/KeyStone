//
//  ViewportHighlighter.swift
//  Keystone
//
//  Viewport-based and incremental syntax highlighting.
//  Only highlights visible content and tracks changes for incremental updates.
//

import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Tracks which lines have been highlighted and need re-highlighting
public class HighlightTracker {
    /// Lines that have been highlighted (line number -> version)
    private var highlightedLines: [Int: Int] = [:]

    /// Current document version (increments on each change)
    private var documentVersion = 0

    /// Lines that are dirty and need re-highlighting
    private var dirtyLines: Set<Int> = []

    /// The range of lines that were last highlighted
    public private(set) var lastHighlightedRange: ClosedRange<Int>?

    // MARK: - Version Management

    /// Marks the document as changed, incrementing version
    public func documentDidChange() {
        documentVersion += 1
    }

    /// Marks specific lines as dirty (need re-highlighting)
    public func markLinesDirty(_ lines: ClosedRange<Int>) {
        for line in lines {
            dirtyLines.insert(line)
        }
    }

    /// Marks all lines as dirty
    public func markAllDirty() {
        highlightedLines.removeAll()
        dirtyLines.removeAll()
    }

    /// Checks if a line needs highlighting
    public func needsHighlighting(line: Int) -> Bool {
        if dirtyLines.contains(line) {
            return true
        }
        guard let version = highlightedLines[line] else {
            return true
        }
        return version < documentVersion
    }

    /// Marks a line as highlighted at current version
    public func markHighlighted(line: Int) {
        highlightedLines[line] = documentVersion
        dirtyLines.remove(line)
    }

    /// Marks a range of lines as highlighted
    public func markHighlighted(lines: ClosedRange<Int>) {
        for line in lines {
            markHighlighted(line: line)
        }
        lastHighlightedRange = lines
    }

    /// Returns lines that need highlighting in the given range
    public func linesNeedingHighlight(in range: ClosedRange<Int>) -> [Int] {
        return range.filter { needsHighlighting(line: $0) }
    }

    /// Clears highlight cache for lines that are far from the viewport
    /// This prevents memory from growing unbounded
    public func pruneCache(keepingLinesNear viewport: ClosedRange<Int>, buffer: Int = 100) {
        let keepRange = (viewport.lowerBound - buffer)...(viewport.upperBound + buffer)
        highlightedLines = highlightedLines.filter { keepRange.contains($0.key) }
    }
}

/// Viewport-aware syntax highlighter that only processes visible content
public class ViewportHighlighter {
    /// The underlying syntax highlighter
    public var highlighter: SyntaxHighlighter

    /// Line manager for efficient line lookups
    public let lineManager = LineManager()

    /// Tracks highlighting state
    public let tracker = HighlightTracker()

    /// Buffer lines to highlight above/below viewport
    public var viewportBuffer: Int = 20

    // MARK: - Initialization

    public init(highlighter: SyntaxHighlighter) {
        self.highlighter = highlighter
    }

    // MARK: - Document Updates

    /// Call when the document text changes completely
    public func documentDidLoad(text: String) {
        lineManager.rebuild(from: text)
        tracker.markAllDirty()
    }

    /// Call when text is inserted
    public func textDidInsert(at location: Int, text: String) {
        // Find affected lines
        if let affectedLine = lineManager.lineContaining(offset: location) {
            // Mark from affected line to end as dirty (newlines shift everything)
            let endLine = lineManager.lineCount
            tracker.markLinesDirty(affectedLine.number...endLine)
        }
        lineManager.didInsert(at: location, text: text)
        tracker.documentDidChange()
    }

    /// Call when text is deleted
    public func textDidDelete(range: NSRange) {
        if let affectedLine = lineManager.lineContaining(offset: range.location) {
            let endLine = lineManager.lineCount
            tracker.markLinesDirty(affectedLine.number...endLine)
        }
        lineManager.didDelete(range: range)
        tracker.documentDidChange()
    }

    // MARK: - Viewport Highlighting

    /// Highlights only the visible viewport plus buffer
    /// - Parameters:
    ///   - textStorage: The text storage to apply highlighting to
    ///   - text: The full document text
    ///   - viewportStart: Start character offset of visible area
    ///   - viewportEnd: End character offset of visible area
    /// - Returns: The range that was highlighted, or nil if nothing needed highlighting
    @discardableResult
    public func highlightViewport(
        textStorage: NSTextStorage,
        text: String,
        viewportStart: Int,
        viewportEnd: Int
    ) -> NSRange? {
        // Rebuild line manager if needed
        if lineManager.rebuildNeeded {
            lineManager.rebuild(from: text)
            lineManager.clearRebuildFlag()
        }

        // Find visible lines
        guard let firstLine = lineManager.lineContaining(offset: viewportStart),
              let lastLine = lineManager.lineContaining(offset: min(viewportEnd, max(0, text.utf16.count - 1))) else {
            return nil
        }

        // Expand range with buffer
        let startLine = max(1, firstLine.number - viewportBuffer)
        let endLine = min(lineManager.lineCount, lastLine.number + viewportBuffer)

        // Find lines that need highlighting
        let linesToHighlight = tracker.linesNeedingHighlight(in: startLine...endLine)

        guard !linesToHighlight.isEmpty else {
            return nil // Everything already highlighted
        }

        // Get the character range to highlight
        guard let rangeStart = lineManager.startOffset(forLine: linesToHighlight.first ?? startLine),
              let lastLineToHighlight = lineManager.line(at: linesToHighlight.last ?? endLine) else {
            return nil
        }

        let rangeEnd = min(lastLineToHighlight.endOffset, text.utf16.count)
        let highlightRange = NSRange(location: rangeStart, length: rangeEnd - rangeStart)

        // Extract the substring for this range
        guard highlightRange.location >= 0,
              highlightRange.location + highlightRange.length <= text.utf16.count else {
            return nil
        }

        let startIndex = text.utf16.index(text.utf16.startIndex, offsetBy: highlightRange.location)
        let endIndex = text.utf16.index(startIndex, offsetBy: highlightRange.length)

        guard let swiftStartIndex = startIndex.samePosition(in: text),
              let swiftEndIndex = endIndex.samePosition(in: text) else {
            return nil
        }

        let substring = String(text[swiftStartIndex..<swiftEndIndex])

        // Apply highlighting using the existing highlighter
        highlighter.highlightRange(textStorage: textStorage, text: substring, offset: highlightRange.location)

        // Mark lines as highlighted
        if let first = linesToHighlight.first, let last = linesToHighlight.last {
            tracker.markHighlighted(lines: first...last)
        }

        // Prune old cache entries
        tracker.pruneCache(keepingLinesNear: startLine...endLine)

        return highlightRange
    }

    /// Highlights incrementally changed lines only
    @discardableResult
    public func highlightIncrementally(
        textStorage: NSTextStorage,
        text: String,
        changedRange: NSRange
    ) -> NSRange? {
        // Find affected lines
        guard let firstLine = lineManager.lineContaining(offset: changedRange.location) else {
            return nil
        }

        let endOffset = changedRange.location + changedRange.length
        guard let lastLine = lineManager.lineContaining(offset: max(0, endOffset - 1)) else {
            return highlightLines(textStorage: textStorage, text: text, lines: firstLine.number...firstLine.number)
        }

        // Highlight the affected lines plus a small buffer for context
        let startLine = max(1, firstLine.number - 2)
        let endLine = min(lineManager.lineCount, lastLine.number + 2)

        return highlightLines(textStorage: textStorage, text: text, lines: startLine...endLine)
    }

    /// Highlights specific lines
    private func highlightLines(
        textStorage: NSTextStorage,
        text: String,
        lines: ClosedRange<Int>
    ) -> NSRange? {
        guard let startOffset = lineManager.startOffset(forLine: lines.lowerBound),
              let endLineInfo = lineManager.line(at: lines.upperBound) else {
            return nil
        }

        let range = NSRange(location: startOffset, length: endLineInfo.endOffset - startOffset)

        // Extract substring
        guard range.location >= 0, range.location + range.length <= text.utf16.count else {
            return nil
        }

        let startIndex = text.utf16.index(text.utf16.startIndex, offsetBy: range.location)
        let endIndex = text.utf16.index(startIndex, offsetBy: range.length)

        guard let swiftStartIndex = startIndex.samePosition(in: text),
              let swiftEndIndex = endIndex.samePosition(in: text) else {
            return nil
        }

        let substring = String(text[swiftStartIndex..<swiftEndIndex])

        highlighter.highlightRange(textStorage: textStorage, text: substring, offset: range.location)
        tracker.markHighlighted(lines: lines)

        return range
    }
}
