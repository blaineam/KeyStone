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

    /// Analyze text to find foldable regions.
    /// This is a simplified version - full implementation would use TreeSitter AST.
    public func analyzeText(_ text: String) {
        guard isEnabled else {
            regions = []
            _regionsByStartLine.removeAll()
            foldedRegionIds.removeAll()
            invalidateHiddenLinesCache()
            return
        }

        var detectedRegions: [FoldableRegion] = []
        let lines = text.components(separatedBy: .newlines)
        let nsText = text as NSString

        // Track brace and bracket-based folding
        // Separate stacks for {} and [] to ensure proper matching
        var braceStack: [(line: Int, location: Int)]  = []  // For {}
        var bracketStack: [(line: Int, location: Int)] = []  // For []
        var currentLocation = 0

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Track braces and brackets for block folding
            for (charIndex, char) in line.enumerated() {
                switch char {
                case "{":
                    braceStack.append((lineIndex, currentLocation + charIndex))
                case "}":
                    if let openBrace = braceStack.popLast() {
                        // Only create fold regions for multi-line blocks
                        if lineIndex > openBrace.line {
                            let regionType = detectRegionType(forLineAt: openBrace.line, in: lines)
                            let startLoc = lineLocation(forLine: openBrace.line, in: lines)
                            let endLoc = lineLocation(forLine: lineIndex, in: lines) + line.count
                            let range = NSRange(location: startLoc, length: endLoc - startLoc)
                            let preview = lines[openBrace.line].trimmingCharacters(in: .whitespaces)

                            let region = FoldableRegion(
                                startLine: openBrace.line,
                                endLine: lineIndex,
                                type: regionType,
                                range: range,
                                previewText: String(preview.prefix(50))
                            )
                            detectedRegions.append(region)
                        }
                    }
                case "[":
                    bracketStack.append((lineIndex, currentLocation + charIndex))
                case "]":
                    if let openBracket = bracketStack.popLast() {
                        // Only create fold regions for multi-line arrays/brackets
                        if lineIndex > openBracket.line {
                            let startLoc = lineLocation(forLine: openBracket.line, in: lines)
                            let endLoc = lineLocation(forLine: lineIndex, in: lines) + line.count
                            let range = NSRange(location: startLoc, length: endLoc - startLoc)
                            let preview = lines[openBracket.line].trimmingCharacters(in: .whitespaces)

                            let region = FoldableRegion(
                                startLine: openBracket.line,
                                endLine: lineIndex,
                                type: .block,  // Arrays/brackets are generic blocks
                                range: range,
                                previewText: String(preview.prefix(50))
                            )
                            detectedRegions.append(region)
                        }
                    }
                default:
                    break
                }
            }

            currentLocation += line.count + 1 // +1 for newline
        }

        // Detect multi-line comments
        detectMultiLineComments(in: text, lines: lines, into: &detectedRegions)

        // Detect import blocks
        detectImportBlocks(in: lines, into: &detectedRegions)

        // Sort by start line
        detectedRegions.sort { $0.startLine < $1.startLine }

        // Preserve fold state for matching regions
        for i in detectedRegions.indices {
            if let existingRegion = regions.first(where: {
                $0.startLine == detectedRegions[i].startLine &&
                $0.endLine == detectedRegions[i].endLine
            }) {
                if foldedRegionIds.contains(existingRegion.id) {
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

    private func detectRegionType(forLineAt lineIndex: Int, in lines: [String]) -> FoldableRegionType {
        guard lineIndex < lines.count else { return .block }

        let line = lines[lineIndex].trimmingCharacters(in: .whitespaces).lowercased()

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

    private func detectMultiLineComments(in text: String, lines: [String], into regions: inout [FoldableRegion]) {
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
                    let startLoc = lineLocation(forLine: commentStart, in: lines)
                    let endLoc = lineLocation(forLine: index, in: lines) + line.count
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

    private func detectImportBlocks(in lines: [String], into regions: inout [FoldableRegion]) {
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
                    let startLoc = lineLocation(forLine: start, in: lines)
                    let endLoc = lineLocation(forLine: end, in: lines) + lines[end].count
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
            let startLoc = lineLocation(forLine: start, in: lines)
            let endLoc = lineLocation(forLine: end, in: lines) + lines[end].count
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

    private func lineLocation(forLine lineIndex: Int, in lines: [String]) -> Int {
        var location = 0
        for i in 0..<lineIndex {
            location += lines[i].count + 1 // +1 for newline
        }
        return location
    }
}
