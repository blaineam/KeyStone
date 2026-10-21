//
//  CodeFoldingManager.swift
//  Keystone
//
//  Code folding functionality for the editor using TreeSitter syntax analysis.
//

import Foundation
import Combine

/// Represents a foldable region in the code.
public struct FoldableRegion: Identifiable, Equatable {
    public let id = UUID()

    /// The starting line of the foldable region (0-indexed).
    public let startLine: Int

    /// The ending line of the foldable region (0-indexed).
    public let endLine: Int

    /// The type of foldable region.
    public let type: FoldableRegionType

    /// Whether this region is currently folded.
    public var isFolded: Bool = false

    /// The character range this region spans.
    public let range: NSRange

    /// Preview text to show when folded (e.g., first line).
    public let previewText: String

    /// The number of lines in this region.
    public var lineCount: Int {
        endLine - startLine + 1
    }

    /// The number of hidden lines when folded.
    public var hiddenLineCount: Int {
        max(0, lineCount - 1)
    }

    public init(startLine: Int, endLine: Int, type: FoldableRegionType, range: NSRange, previewText: String) {
        self.startLine = startLine
        self.endLine = endLine
        self.type = type
        self.range = range
        self.previewText = previewText
    }

    public static func == (lhs: FoldableRegion, rhs: FoldableRegion) -> Bool {
        lhs.startLine == rhs.startLine &&
        lhs.endLine == rhs.endLine &&
        lhs.type == rhs.type &&
        lhs.range == rhs.range
    }
}

/// Types of foldable regions.
public enum FoldableRegionType: String, CaseIterable {
    case function
    case classDefinition = "class"
    case structDefinition = "struct"
    case enumDefinition = "enum"
    case ifStatement = "if"
    case forLoop = "for"
    case whileLoop = "while"
    case switchStatement = "switch"
    case block
    case comment
    case imports
    case other

    /// Display name for the region type.
    public var displayName: String {
        switch self {
        case .function: return "Function"
        case .classDefinition: return "Class"
        case .structDefinition: return "Struct"
        case .enumDefinition: return "Enum"
        case .ifStatement: return "If Statement"
        case .forLoop: return "For Loop"
        case .whileLoop: return "While Loop"
        case .switchStatement: return "Switch Statement"
        case .block: return "Block"
        case .comment: return "Comment"
        case .imports: return "Imports"
        case .other: return "Block"
        }
    }
}

/// Manages code folding operations in the editor.
public final class CodeFoldingManager: ObservableObject {
    // MARK: - Published State

    /// All detected foldable regions.
    @Published public private(set) var regions: [FoldableRegion] = []

    /// Set of folded region IDs.
    @Published public private(set) var foldedRegionIds: Set<UUID> = []

    /// Whether code folding is enabled.
    @Published public var isEnabled: Bool = true

    // MARK: - Caching

    /// Cached hidden lines set for O(1) lookup
    private var _hiddenLinesCache: Set<Int> = []
    private var _hiddenLinesCacheDirty = true

    /// Dictionary for O(1) region lookup by start line
    private var _regionsByStartLine: [Int: FoldableRegion] = [:]

    // MARK: - Computed Properties

    /// Regions that are currently folded.
    public var foldedRegions: [FoldableRegion] {
        regions.filter { foldedRegionIds.contains($0.id) }
    }

    /// Lines that are currently hidden due to folding (0-indexed).
    /// Uses cached Set for O(1) lookup.
    public var hiddenLines: Set<Int> {
        if _hiddenLinesCacheDirty {
            rebuildHiddenLinesCache()
        }
        return _hiddenLinesCache
    }

    private func rebuildHiddenLinesCache() {
        _hiddenLinesCache.removeAll()
        for region in regions {
            if foldedRegionIds.contains(region.id) {
                // Hide all lines except the first line of the fold (0-indexed)
                for line in (region.startLine + 1)...region.endLine {
                    _hiddenLinesCache.insert(line)
                }
            }
        }
        _hiddenLinesCacheDirty = false
    }

    private func invalidateHiddenLinesCache() {
        _hiddenLinesCacheDirty = true
    }

    // MARK: - Callbacks

    /// Called when folding state changes.
    public var onFoldingChanged: (() -> Void)?

    /// Called when regions are updated.
    public var onRegionsUpdated: (([FoldableRegion]) -> Void)?

    // MARK: - Initialization

    public init() {}

    // MARK: - Region Detection

    /// Generation counter so a slow background analysis can't overwrite a newer one.
    private var analysisGeneration = 0

    /// True once regions came from the syntax tree. The text heuristics in
    /// `analyzeText` are then ignored; the tree is more accurate and already paid for.
    public internal(set) var usesSyntaxTreeRegions = false

    /// Regions computed from the tree-sitter tree (by the language mode after each parse).
    func applySyntaxTreeRegions(_ detected: [FoldableRegion]) {
        usesSyntaxTreeRegions = true
        analysisGeneration += 1
        guard isEnabled else {
            applyDisabledState()
            return
        }
        apply(detectedRegions: detected)
    }

    /// Analyze text to find foldable regions.
    /// This is a simplified version - full implementation would use TreeSitter AST.
    public func analyzeText(_ text: String) {
        guard !usesSyntaxTreeRegions else { return }
        analysisGeneration += 1
        guard isEnabled else {
            applyDisabledState()
            return
        }
        apply(detectedRegions: Self.computeRegions(for: text))
    }

    /// Same as `analyzeText(_:)` but does the scan off the main thread and applies
    /// the result back on it. Superseded results are dropped. Use for big buffers.
    public func analyzeTextInBackground(_ text: String) {
        guard !usesSyntaxTreeRegions else { return }
        analysisGeneration += 1
        let generation = analysisGeneration
        guard isEnabled else {
            applyDisabledState()
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let detected = Self.computeRegions(for: text)
            DispatchQueue.main.async {
                guard let self, self.analysisGeneration == generation, self.isEnabled else { return }
                self.apply(detectedRegions: detected)
            }
        }
    }

    private func applyDisabledState() {
        regions = []
        _regionsByStartLine.removeAll()
        foldedRegionIds.removeAll()
        invalidateHiddenLinesCache()
    }

    private func apply(detectedRegions incoming: [FoldableRegion]) {
        var detectedRegions = incoming

        // Preserve fold state for matching regions
        if !foldedRegionIds.isEmpty {
            var existingByLines: [LineSpan: FoldableRegion] = [:]
            for region in regions {
                let key = LineSpan(start: region.startLine, end: region.endLine)
                if existingByLines[key] == nil { existingByLines[key] = region }
            }
            for i in detectedRegions.indices {
                let key = LineSpan(start: detectedRegions[i].startLine, end: detectedRegions[i].endLine)
                if let existingRegion = existingByLines[key], foldedRegionIds.contains(existingRegion.id) {
                    foldedRegionIds.remove(existingRegion.id)
                    foldedRegionIds.insert(detectedRegions[i].id)
                }
            }
        }

        regions = detectedRegions

        // Build O(1) lookup dictionary (keep first/innermost region if duplicates exist)
        _regionsByStartLine.removeAll()
        for region in regions {
            if _regionsByStartLine[region.startLine] == nil {
                _regionsByStartLine[region.startLine] = region
            }
        }

        invalidateHiddenLinesCache()
        onRegionsUpdated?(regions)
    }

    private struct LineSpan: Hashable {
        let start: Int
        let end: Int
    }

    /// Pure, linear-time region scan. Safe to call from any thread.
    static func computeRegions(for text: String) -> [FoldableRegion] {
        var detectedRegions: [FoldableRegion] = []
        let lines = text.components(separatedBy: .newlines)

        // UTF-16 start offset of every line, computed once. Region ranges are
        // NSRanges, and looking offsets up here keeps the scan O(N) instead of
        // re-walking the file for every region.
        var lineStarts = [Int](repeating: 0, count: lines.count + 1)
        for (i, line) in lines.enumerated() {
            lineStarts[i + 1] = lineStarts[i] + line.utf16.count + 1 // +1 for newline
        }

        // Region type + preview depend only on the opening line; minified files
        // open thousands of regions on the same enormous line.
        var openingLineInfo: [Int: (type: FoldableRegionType, preview: String)] = [:]
        func info(forLine index: Int) -> (type: FoldableRegionType, preview: String) {
            if let cached = openingLineInfo[index] { return cached }
            let head = String(lines[index].prefix(1000)).trimmingCharacters(in: .whitespaces)
            let value = (detectRegionType(head), String(head.prefix(50)))
            openingLineInfo[index] = value
            return value
        }

        // Separate stacks for {} and [] to ensure proper matching
        var braceStack: [Int] = []
        var bracketStack: [Int] = []

        for (lineIndex, line) in lines.enumerated() {
            let lineLength = lineStarts[lineIndex + 1] - lineStarts[lineIndex] - 1
            for unit in line.utf16 {
                switch unit {
                case 0x7B: // {
                    braceStack.append(lineIndex)
                case 0x7D: // }
                    if let openLine = braceStack.popLast(), lineIndex > openLine {
                        let opening = info(forLine: openLine)
                        detectedRegions.append(FoldableRegion(
                            startLine: openLine,
                            endLine: lineIndex,
                            type: opening.type,
                            range: NSRange(location: lineStarts[openLine], length: lineStarts[lineIndex] + lineLength - lineStarts[openLine]),
                            previewText: opening.preview
                        ))
                    }
                case 0x5B: // [
                    bracketStack.append(lineIndex)
                case 0x5D: // ]
                    if let openLine = bracketStack.popLast(), lineIndex > openLine {
                        detectedRegions.append(FoldableRegion(
                            startLine: openLine,
                            endLine: lineIndex,
                            type: .block,  // Arrays/brackets are generic blocks
                            range: NSRange(location: lineStarts[openLine], length: lineStarts[lineIndex] + lineLength - lineStarts[openLine]),
                            previewText: info(forLine: openLine).preview
                        ))
                    }
                default:
                    break
                }
            }
        }

        detectMultiLineComments(lines: lines, lineStarts: lineStarts, into: &detectedRegions)
        detectImportBlocks(lines: lines, lineStarts: lineStarts, into: &detectedRegions)

        // Sort by start line
        detectedRegions.sort { $0.startLine < $1.startLine }
        return detectedRegions
    }

    // MARK: - Fold/Unfold Operations

    /// Toggle fold state of a region.
    public func toggleFold(for region: FoldableRegion) {
        if foldedRegionIds.contains(region.id) {
            unfold(region)
        } else {
            fold(region)
        }
    }

    /// Fold a region.
    public func fold(_ region: FoldableRegion) {
        guard regions.contains(where: { $0.id == region.id }) else { return }
        foldedRegionIds.insert(region.id)
        invalidateHiddenLinesCache()
        onFoldingChanged?()
    }

    /// Unfold a region.
    public func unfold(_ region: FoldableRegion) {
        foldedRegionIds.remove(region.id)
        invalidateHiddenLinesCache()
        onFoldingChanged?()
    }

    /// Fold all regions.
    public func foldAll() {
        foldedRegionIds = Set(regions.map { $0.id })
        invalidateHiddenLinesCache()
        onFoldingChanged?()
    }

    /// Unfold all regions.
    public func unfoldAll() {
        foldedRegionIds.removeAll()
        invalidateHiddenLinesCache()
        onFoldingChanged?()
    }

    /// Fold all regions of a specific type.
    public func foldAll(ofType type: FoldableRegionType) {
        let matchingIds = regions.filter { $0.type == type }.map { $0.id }
        foldedRegionIds.formUnion(matchingIds)
        invalidateHiddenLinesCache()
        onFoldingChanged?()
    }

    /// Get the foldable region at a specific line.
    public func region(atLine line: Int) -> FoldableRegion? {
        // Return the innermost (smallest) region containing this line
        regions
            .filter { $0.startLine <= line && $0.endLine >= line }
            .min(by: { $0.lineCount < $1.lineCount })
    }

    /// Get the foldable region starting at a specific line (0-indexed).
    /// Uses cached dictionary for O(1) lookup.
    public func regionStarting(atLine line: Int) -> FoldableRegion? {
        _regionsByStartLine[line]
    }

    /// Check if a line is hidden due to folding.
    public func isLineHidden(_ line: Int) -> Bool {
        hiddenLines.contains(line)
    }

    /// Clear all fold state.
    public func clear() {
        regions = []
        foldedRegionIds.removeAll()
        onFoldingChanged?()
    }

    // MARK: - Private Helpers

    private static func detectRegionType(_ trimmedLine: String) -> FoldableRegionType {
        let line = trimmedLine.lowercased()

        if line.contains("func ") || line.contains("function ") || line.contains("def ") {
            return .function
        } else if line.contains("class ") {
            return .classDefinition
        } else if line.contains("struct ") {
            return .structDefinition
        } else if line.contains("enum ") {
            return .enumDefinition
        } else if line.hasPrefix("if ") || line.hasPrefix("if(") || line.contains(" if ") {
            return .ifStatement
        } else if line.hasPrefix("for ") || line.hasPrefix("for(") {
            return .forLoop
        } else if line.hasPrefix("while ") || line.hasPrefix("while(") {
            return .whileLoop
        } else if line.hasPrefix("switch ") || line.hasPrefix("switch(") {
            return .switchStatement
        }

        return .block
    }

    private static func detectMultiLineComments(lines: [String], lineStarts: [Int], into regions: inout [FoldableRegion]) {
        // Detect /* */ style comments
        var inComment = false
        var commentStart = 0

        for (index, line) in lines.enumerated() {
            if !inComment && line.contains("/*") {
                inComment = true
                commentStart = index
            }
            if inComment && line.contains("*/") {
                if index > commentStart {
                    let startLoc = lineStarts[commentStart]
                    let endLoc = lineStarts[index] + line.utf16.count
                    let region = FoldableRegion(
                        startLine: commentStart,
                        endLine: index,
                        type: .comment,
                        range: NSRange(location: startLoc, length: endLoc - startLoc),
                        previewText: "/* ... */"
                    )
                    regions.append(region)
                }
                inComment = false
            }
        }
    }

    private static func detectImportBlocks(lines: [String], lineStarts: [Int], into regions: inout [FoldableRegion]) {
        var importStart: Int?
        var importEnd: Int?

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Check for import statements (Swift, Python, JS/TS, etc.)
            let isImport = trimmed.hasPrefix("import ") ||
                          trimmed.hasPrefix("from ") ||
                          trimmed.hasPrefix("#include") ||
                          trimmed.hasPrefix("using ") ||
                          trimmed.hasPrefix("require(")

            if isImport {
                if importStart == nil {
                    importStart = index
                }
                importEnd = index
            } else if !trimmed.isEmpty && importStart != nil {
                // Non-empty, non-import line - end the import block
                if let start = importStart, let end = importEnd, end > start {
                    let startLoc = lineStarts[start]
                    let endLoc = lineStarts[end] + lines[end].utf16.count
                    let region = FoldableRegion(
                        startLine: start,
                        endLine: end,
                        type: .imports,
                        range: NSRange(location: startLoc, length: endLoc - startLoc),
                        previewText: "imports..."
                    )
                    regions.append(region)
                }
                importStart = nil
                importEnd = nil
            }
        }

        // Handle imports at end of file
        if let start = importStart, let end = importEnd, end > start {
            let startLoc = lineStarts[start]
            let endLoc = lineStarts[end] + lines[end].utf16.count
            let region = FoldableRegion(
                startLine: start,
                endLine: end,
                type: .imports,
                range: NSRange(location: startLoc, length: endLoc - startLoc),
                previewText: "imports..."
            )
            regions.append(region)
        }
    }
}
