//
//  Indentation.swift
//  Keystone
//

import Foundation

/// Represents the type of indentation used in code.
public enum IndentationType: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Tab character indentation
    case tabs = "Tabs"
    /// Space character indentation
    case spaces = "Spaces"

    public var id: String { rawValue }

    /// Detects the indentation type and width used in the given text.
    /// - Parameter text: The text to analyze.
    /// - Returns: A tuple containing the detected indentation type and width.
    public static func detect(in text: String) -> (type: IndentationType, width: Int) {
        var tabLines = 0
        var spaceLines = 0
        var detectedWidths: [Int: Int] = [:] // width -> count

        for line in text.components(separatedBy: .newlines) {
            guard !line.isEmpty else { continue }

            if line.hasPrefix("\t") {
                tabLines += 1
            } else if line.hasPrefix(" ") {
                spaceLines += 1
                var count = 0
                for char in line {
                    if char == " " { count += 1 }
                    else { break }
                }
                if count > 0 {
                    detectedWidths[count, default: 0] += 1
                }
            }
        }

        let usesTabs = tabLines > spaceLines

        // Detect most common width
        var width = 4
        if !usesTabs {
            // Find the GCD of common widths to detect indent level
            let sortedWidths = detectedWidths.keys.sorted()
            if let smallest = sortedWidths.first, smallest > 0 {
                width = smallest
                // Check for common widths
                if sortedWidths.contains(2) && !sortedWidths.contains(where: { $0 % 2 != 0 }) {
                    width = 2
                }
                if sortedWidths.contains(4) && !sortedWidths.contains(where: { $0 % 4 != 0 }) {
                    width = 4
                }
            }
        }

        return (usesTabs ? .tabs : .spaces, width)
    }
}

/// Represents the indentation settings for the editor.
public struct IndentationSettings: Equatable, Codable, Sendable {
    /// The type of indentation (tabs or spaces).
    public var type: IndentationType
    /// The width of indentation in spaces (or equivalent for tabs).
    public var width: Int

    /// Creates indentation settings with the specified type and width.
    public init(type: IndentationType = .spaces, width: Int = 4) {
        self.type = type
        self.width = width
    }

    /// The string representation of a single indentation level.
    public var indentString: String {
        switch type {
        case .tabs:
            return "\t"
        case .spaces:
            return String(repeating: " ", count: width)
        }
    }

    /// Detects and creates settings from the given text.
    public static func detect(from text: String) -> IndentationSettings {
        let (type, width) = IndentationType.detect(in: text)
        return IndentationSettings(type: type, width: width)
    }

    /// Converts the indentation in the given text to use these settings.
    /// - Parameter text: The text to convert.
    /// - Returns: The text with converted indentation.
    public static func convert(_ text: String, to settings: IndentationSettings) -> String {
        // Detect current indentation
        let current = detect(from: text)

        // If already using the target settings, return as-is
        if current.type == settings.type && (current.type == .tabs || current.width == settings.width) {
            return text
        }

        let lines = text.components(separatedBy: "\n")
        var result: [String] = []

        for line in lines {
            var leadingWhitespace = ""
            var indentLevel = 0
            var contentStart = line.startIndex

            // Count indentation levels in the line
            for char in line {
                if char == "\t" {
                    indentLevel += 1
                    contentStart = line.index(after: contentStart)
                } else if char == " " {
                    leadingWhitespace.append(char)
                    contentStart = line.index(after: contentStart)
                } else {
                    break
                }
            }

            // Calculate total indent levels from spaces
            let spaceWidth = current.type == .spaces ? current.width : settings.width
            if !leadingWhitespace.isEmpty {
                indentLevel += leadingWhitespace.count / max(1, spaceWidth)
            }

            // Build new indentation
            let newIndent = String(repeating: settings.indentString, count: indentLevel)
            let content = String(line[contentStart...])
            result.append(newIndent + content)
        }

        return result.joined(separator: "\n")
    }
}
