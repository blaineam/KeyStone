//
//  LineEnding.swift
//  Keystone
//

import Foundation

/// Represents the type of line ending used in a text file.
public enum LineEnding: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Unix-style line ending (LF - `\n`)
    case lf = "LF"
    /// Windows-style line ending (CRLF - `\r\n`)
    case crlf = "CRLF"
    /// Classic Mac-style line ending (CR - `\r`)
    case cr = "CR"
    /// Mixed line endings detected in the file
    case mixed = "Mixed"

    public var id: String { rawValue }

    /// The actual character(s) used for this line ending type.
    public var symbol: String {
        switch self {
        case .lf: return "\n"
        case .crlf: return "\r\n"
        case .cr: return "\r"
        case .mixed: return "\n"
        }
    }

    /// A human-readable description of the line ending type.
    public var displayName: String {
        switch self {
        case .lf: return "LF (Unix/macOS)"
        case .crlf: return "CRLF (Windows)"
        case .cr: return "CR (Classic Mac)"
        case .mixed: return "Mixed"
        }
    }

    /// Detects the predominant line ending type used in the given text.
    /// - Parameter text: The text to analyze.
    /// - Returns: The detected line ending type.
    public static func detect(in text: String) -> LineEnding {
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

        // If more than 90% are one type, use that
        if crlfCount > 0 && Double(crlfCount) / Double(total) > 0.9 { return .crlf }
        if lfCount > 0 && Double(lfCount) / Double(total) > 0.9 { return .lf }
        if crCount > 0 && Double(crCount) / Double(total) > 0.9 { return .cr }

        // Otherwise return the most common type or mixed
        if crlfCount > lfCount && crlfCount > crCount { return .crlf }
        if crCount > lfCount && crCount > crlfCount { return .cr }
        if lfCount == crlfCount || lfCount == crCount { return .mixed }
        return .lf
    }

    /// Converts all line endings in the given text to the specified type.
    /// - Parameters:
    ///   - text: The text to convert.
    ///   - lineEnding: The target line ending type.
    /// - Returns: The text with converted line endings.
    public static func convert(_ text: String, to lineEnding: LineEnding) -> String {
        // First normalize all line endings to LF
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        normalized = normalized.replacingOccurrences(of: "\r", with: "\n")

        // Then convert to target
        switch lineEnding {
        case .lf, .mixed:
            return normalized
        case .crlf:
            return normalized.replacingOccurrences(of: "\n", with: "\r\n")
        case .cr:
            return normalized.replacingOccurrences(of: "\n", with: "\r")
        }
    }
}
