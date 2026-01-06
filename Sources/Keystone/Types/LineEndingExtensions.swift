//
//  LineEndingExtensions.swift
//  Keystone
//
//  Extends Runestone's LineEnding with detection and conversion utilities.
//

import Foundation

// MARK: - LineEnding Extensions for Detection and Conversion

public extension LineEnding {
    /// A human-readable description of the line ending type.
    var displayName: String {
        switch self {
        case .lf: return "LF (Unix/macOS)"
        case .crlf: return "CRLF (Windows)"
        case .cr: return "CR (Classic Mac)"
        }
    }

    /// Detects the predominant line ending type used in the given text.
    /// - Parameter text: The text to analyze.
    /// - Returns: The detected line ending type (defaults to .lf if no line endings found).
    static func detect(in text: String) -> LineEnding {
        var lfCount = 0
        var crlfCount = 0
        var crCount = 0

        var i = text.startIndex
        while i < text.endIndex {
            let char = text[i]
            if char == "\r" {
                let nextIndex = text.index(after: i)
                if nextIndex < text.endIndex && text[nextIndex] == "\n" {
                    crlfCount += 1
                    i = nextIndex
                } else {
                    crCount += 1
                }
            } else if char == "\n" {
                lfCount += 1
            }
            i = text.index(after: i)
        }

        let total = lfCount + crlfCount + crCount
        if total == 0 { return .lf } // Default for empty/single-line files

        // Return the most common type
        if crlfCount >= lfCount && crlfCount >= crCount { return .crlf }
        if crCount > lfCount && crCount > crlfCount { return .cr }
        return .lf
    }

    /// Converts all line endings in the given text to the specified type.
    /// - Parameters:
    ///   - text: The text to convert.
    ///   - lineEnding: The target line ending type.
    /// - Returns: The text with converted line endings.
    static func convert(_ text: String, to lineEnding: LineEnding) -> String {
        // First normalize all line endings to LF
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        normalized = normalized.replacingOccurrences(of: "\r", with: "\n")

        // Then convert to target
        switch lineEnding {
        case .lf:
            return normalized
        case .crlf:
            return normalized.replacingOccurrences(of: "\n", with: "\r\n")
        case .cr:
            return normalized.replacingOccurrences(of: "\n", with: "\r")
        }
    }
}

// Make LineEnding conform to protocols needed by EnterSpace
extension LineEnding: Identifiable, Codable {
    public var id: String { rawValue }
}
