//
//  CodeFolding.swift
//  Keystone
//
//  Code folding support for collapsible code regions.
//

import Foundation

/// Represents a foldable region in the code.
public struct FoldableRegion: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// The starting line number (1-based).
    public let startLine: Int
    /// The ending line number (1-based).
    public let endLine: Int
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
        type: FoldType,
        isFolded: Bool = false,
        preview: String = "..."
    ) {
        self.id = id
        self.startLine = startLine
        self.endLine = endLine
        self.type = type
        self.isFolded = isFolded
        self.preview = preview
    }

    /// The number of lines this region spans.
    public var lineCount: Int {
        endLine - startLine + 1
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

    public init() {}

    /// Analyzes the text and detects foldable regions.
    /// - Parameter text: The source code to analyze.
    public func analyze(_ text: String) {
        var newRegions: [FoldableRegion] = []
        let lines = text.components(separatedBy: .newlines)

        // Track bracket pairs for folding
        var braceStack: [(line: Int, column: Int)] = []
        var bracketStack: [(line: Int, column: Int)] = []
        var parenStack: [(line: Int, column: Int)] = []

        // Track multi-line comments
        var commentStart: Int?

        for (lineIndex, line) in lines.enumerated() {
            let lineNumber = lineIndex + 1

            // Check for multi-line comment start/end
            if line.contains("/*") && !line.contains("*/") {
                commentStart = lineNumber
            } else if let start = commentStart, line.contains("*/") {
                let preview = extractPreview(from: lines, startLine: start - 1)
                newRegions.append(FoldableRegion(
                    startLine: start,
                    endLine: lineNumber,
                    type: .comment,
                    preview: preview
                ))
                commentStart = nil
            }

            // Check for region markers
            if line.contains("// MARK:") || line.contains("#pragma mark") || line.contains("#region") {
                // Find the next marker or end of file
                for nextLine in (lineIndex + 1)..<lines.count {
                    let nextContent = lines[nextLine]
                    if nextContent.contains("// MARK:") || nextContent.contains("#pragma mark") ||
                       nextContent.contains("#region") || nextContent.contains("#endregion") {
                        if nextLine > lineIndex + 1 {
                            let preview = extractPreview(from: lines, startLine: lineIndex)
                            newRegions.append(FoldableRegion(
                                startLine: lineNumber,
                                endLine: nextLine,
                                type: .region,
                                preview: preview
                            ))
                        }
                        break
                    }
                }
            }

            // Track braces
            for (charIndex, char) in line.enumerated() {
                switch char {
                case "{":
                    braceStack.append((line: lineNumber, column: charIndex))
                case "}":
                    if let start = braceStack.popLast(), start.line < lineNumber {
                        let preview = extractPreview(from: lines, startLine: start.line - 1)
                        newRegions.append(FoldableRegion(
                            startLine: start.line,
                            endLine: lineNumber,
                            type: .braces,
                            preview: preview
                        ))
                    }
                case "[":
                    bracketStack.append((line: lineNumber, column: charIndex))
                case "]":
                    if let start = bracketStack.popLast(), start.line < lineNumber {
                        let preview = extractPreview(from: lines, startLine: start.line - 1)
                        newRegions.append(FoldableRegion(
                            startLine: start.line,
                            endLine: lineNumber,
                            type: .brackets,
                            preview: preview
                        ))
                    }
                case "(":
                    parenStack.append((line: lineNumber, column: charIndex))
                case ")":
                    if let start = parenStack.popLast(), start.line < lineNumber {
                        let preview = extractPreview(from: lines, startLine: start.line - 1)
                        newRegions.append(FoldableRegion(
                            startLine: start.line,
                            endLine: lineNumber,
                            type: .parentheses,
                            preview: preview
                        ))
                    }
                default:
                    break
                }
            }
        }

        // Sort by start line and filter out small regions
        regions = newRegions
            .filter { $0.lineCount >= 2 }
            .sorted { $0.startLine < $1.startLine }

        // Preserve fold state for existing regions
        let oldFoldedIds = foldedRegionIds
        foldedRegionIds = Set(regions.filter { region in
            oldFoldedIds.contains(region.id)
        }.map(\.id))
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

    /// Toggles the fold state of a region.
    /// - Parameter region: The region to toggle.
    public func toggleFold(_ region: FoldableRegion) {
        if foldedRegionIds.contains(region.id) {
            foldedRegionIds.remove(region.id)
        } else {
            foldedRegionIds.insert(region.id)
        }
    }

    /// Folds all regions.
    public func foldAll() {
        foldedRegionIds = Set(regions.map(\.id))
    }

    /// Unfolds all regions.
    public func unfoldAll() {
        foldedRegionIds.removeAll()
    }

    /// Checks if a line is hidden due to folding.
    /// - Parameter lineNumber: The 1-based line number.
    /// - Returns: True if the line is hidden.
    public func isLineHidden(_ lineNumber: Int) -> Bool {
        for region in regions {
            if foldedRegionIds.contains(region.id) &&
               lineNumber > region.startLine && lineNumber <= region.endLine {
                return true
            }
        }
        return false
    }

    /// Gets the region at a specific line, if any.
    /// - Parameter lineNumber: The 1-based line number.
    /// - Returns: The foldable region starting at this line, if any.
    public func region(atLine lineNumber: Int) -> FoldableRegion? {
        regions.first { $0.startLine == lineNumber }
    }

    /// Checks if a line has a foldable region starting.
    /// - Parameter lineNumber: The 1-based line number.
    /// - Returns: True if a foldable region starts at this line.
    public func hasFoldableRegion(atLine lineNumber: Int) -> Bool {
        regions.contains { $0.startLine == lineNumber }
    }

    /// Checks if a region is currently folded.
    /// - Parameter region: The region to check.
    /// - Returns: True if the region is folded.
    public func isFolded(_ region: FoldableRegion) -> Bool {
        foldedRegionIds.contains(region.id)
    }
}
