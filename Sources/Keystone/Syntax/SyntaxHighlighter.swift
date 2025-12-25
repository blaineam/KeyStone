//
//  SyntaxHighlighter.swift
//  Keystone
//

import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Handles syntax highlighting for code text.
public class SyntaxHighlighter {
    let language: KeystoneLanguage
    let theme: KeystoneTheme

    public init(language: KeystoneLanguage, theme: KeystoneTheme) {
        self.language = language
        self.theme = theme
    }

    /// Applies syntax highlighting to the given text storage.
    public func highlight(textStorage: NSTextStorage, text: String) {
        guard !text.isEmpty else { return }

        switch language {
        case .html, .xml:
            highlightHTML(textStorage: textStorage, text: text)
        case .css:
            highlightCSS(textStorage: textStorage, text: text)
        case .json:
            highlightJSON(textStorage: textStorage, text: text)
        case .conf:
            highlightConfig(textStorage: textStorage, text: text)
        case .markdown:
            highlightMarkdown(textStorage: textStorage, text: text)
        case .plainText:
            break // No highlighting
        default:
            highlightGeneric(textStorage: textStorage, text: text)
        }
    }

    // MARK: - Generic Highlighting

    private func highlightGeneric(textStorage: NSTextStorage, text: String) {
        // Keywords
        for keyword in language.keywords {
            applyPattern("\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b",
                        to: textStorage, in: text, color: PlatformColor(theme.keyword))
        }

        // Types
        for type in language.types {
            applyPattern("\\b\(NSRegularExpression.escapedPattern(for: type))\\b",
                        to: textStorage, in: text, color: PlatformColor(theme.type))
        }

        // Function calls
        applyPattern("\\b([a-zA-Z_][a-zA-Z0-9_]*)\\s*\\(", to: textStorage, in: text, color: PlatformColor(theme.function))

        // Strings (double quotes)
        applyPattern("\"[^\"\\\\]*(?:\\\\.[^\"\\\\]*)*\"", to: textStorage, in: text, color: PlatformColor(theme.string))
        // Strings (single quotes)
        applyPattern("'[^'\\\\]*(?:\\\\.[^'\\\\]*)*'", to: textStorage, in: text, color: PlatformColor(theme.string))
        // Template strings (backticks)
        applyPattern("`[^`]*`", to: textStorage, in: text, color: PlatformColor(theme.string))

        // Single-line comments
        applyPattern("//.*$", to: textStorage, in: text, color: PlatformColor(theme.comment), options: .anchorsMatchLines)

        // Hash comments (Python, Shell, etc.)
        if language == .python || language == .shell || language == .yaml || language == .ruby {
            applyPattern("#.*$", to: textStorage, in: text, color: PlatformColor(theme.comment), options: .anchorsMatchLines)
        }

        // Multi-line comments
        applyPattern("/\\*[\\s\\S]*?\\*/", to: textStorage, in: text, color: PlatformColor(theme.comment))

        // Numbers
        applyPattern("\\b\\d+\\.?\\d*([eE][+-]?\\d+)?\\b", to: textStorage, in: text, color: PlatformColor(theme.number))
        applyPattern("\\b0x[0-9a-fA-F]+\\b", to: textStorage, in: text, color: PlatformColor(theme.number))
    }

    // MARK: - HTML/XML Highlighting

    private func highlightHTML(textStorage: NSTextStorage, text: String) {
        // Tags
        applyPattern("</?\\s*([a-zA-Z][a-zA-Z0-9]*)", to: textStorage, in: text, color: PlatformColor(theme.tag))

        // Attributes
        applyPattern("\\s([a-zA-Z][a-zA-Z0-9-]*)\\s*=", to: textStorage, in: text, color: PlatformColor(theme.attribute))

        // Attribute values (strings)
        applyPattern("\"[^\"]*\"", to: textStorage, in: text, color: PlatformColor(theme.string))
        applyPattern("'[^']*'", to: textStorage, in: text, color: PlatformColor(theme.string))

        // Comments
        applyPattern("<!--[\\s\\S]*?-->", to: textStorage, in: text, color: PlatformColor(theme.comment))

        // DOCTYPE
        applyPattern("<!DOCTYPE[^>]*>", to: textStorage, in: text, color: PlatformColor(theme.comment))

        // Highlight CSS inside <style> tags
        highlightNestedLanguage(
            openPattern: "<style[^>]*>",
            closePattern: "</style>",
            in: text,
            textStorage: textStorage,
            highlightBlock: { range in
                self.highlightCSSInRange(range, textStorage: textStorage, text: text)
            }
        )

        // Highlight JavaScript inside <script> tags
        highlightNestedLanguage(
            openPattern: "<script[^>]*>",
            closePattern: "</script>",
            in: text,
            textStorage: textStorage,
            highlightBlock: { range in
                self.highlightJSInRange(range, textStorage: textStorage, text: text)
            }
        )
    }

    // MARK: - CSS Highlighting

    private func highlightCSS(textStorage: NSTextStorage, text: String) {
        highlightCSSInRange(NSRange(location: 0, length: text.count), textStorage: textStorage, text: text)
    }

    private func highlightCSSInRange(_ range: NSRange, textStorage: NSTextStorage, text: String) {
        // Selectors
        applyPatternInRange(range, pattern: "[.#]?[a-zA-Z_][a-zA-Z0-9_-]*(?=\\s*[\\{,])", to: textStorage, in: text, color: PlatformColor(theme.tag))

        // Properties
        applyPatternInRange(range, pattern: "([a-zA-Z-]+)\\s*:", to: textStorage, in: text, color: PlatformColor(theme.attribute))

        // Values
        applyPatternInRange(range, pattern: ":\\s*([^;{}]+)", to: textStorage, in: text, color: PlatformColor(theme.type))

        // Comments
        applyPatternInRange(range, pattern: "/\\*[\\s\\S]*?\\*/", to: textStorage, in: text, color: PlatformColor(theme.comment))

        // Strings
        applyPatternInRange(range, pattern: "\"[^\"]*\"", to: textStorage, in: text, color: PlatformColor(theme.string))
        applyPatternInRange(range, pattern: "'[^']*'", to: textStorage, in: text, color: PlatformColor(theme.string))

        // Numbers and units
        applyPatternInRange(range, pattern: "\\b\\d+(\\.\\d+)?(px|em|rem|%|vh|vw|pt|cm|mm)?\\b", to: textStorage, in: text, color: PlatformColor(theme.number))

        // Hex colors
        applyPatternInRange(range, pattern: "#[0-9a-fA-F]{3,8}\\b", to: textStorage, in: text, color: PlatformColor(theme.number))
    }

    // MARK: - JavaScript Highlighting (for nested in HTML)

    private func highlightJSInRange(_ range: NSRange, textStorage: NSTextStorage, text: String) {
        let jsKeywords = ["function", "var", "let", "const", "if", "else", "for", "while", "do",
                         "switch", "case", "default", "break", "continue", "return", "try", "catch",
                         "finally", "throw", "new", "delete", "typeof", "instanceof", "void", "this",
                         "class", "extends", "super", "import", "export", "from", "async", "await",
                         "true", "false", "null", "undefined"]

        for keyword in jsKeywords {
            applyPatternInRange(range, pattern: "\\b\(keyword)\\b", to: textStorage, in: text, color: PlatformColor(theme.keyword))
        }

        let jsTypes = ["Array", "Object", "String", "Number", "Boolean", "Function", "Symbol",
                      "Map", "Set", "Promise", "JSON", "Math", "Date", "RegExp", "Error",
                      "console", "window", "document"]

        for type in jsTypes {
            applyPatternInRange(range, pattern: "\\b\(type)\\b", to: textStorage, in: text, color: PlatformColor(theme.type))
        }

        // Function calls
        applyPatternInRange(range, pattern: "\\b([a-zA-Z_][a-zA-Z0-9_]*)\\s*\\(", to: textStorage, in: text, color: PlatformColor(theme.function))

        // Strings
        applyPatternInRange(range, pattern: "\"[^\"\\\\]*(?:\\\\.[^\"\\\\]*)*\"", to: textStorage, in: text, color: PlatformColor(theme.string))
        applyPatternInRange(range, pattern: "'[^'\\\\]*(?:\\\\.[^'\\\\]*)*'", to: textStorage, in: text, color: PlatformColor(theme.string))
        applyPatternInRange(range, pattern: "`[^`]*`", to: textStorage, in: text, color: PlatformColor(theme.string))

        // Comments
        applyPatternInRange(range, pattern: "//.*$", to: textStorage, in: text, color: PlatformColor(theme.comment), options: .anchorsMatchLines)
        applyPatternInRange(range, pattern: "/\\*[\\s\\S]*?\\*/", to: textStorage, in: text, color: PlatformColor(theme.comment))

        // Numbers
        applyPatternInRange(range, pattern: "\\b\\d+\\.?\\d*\\b", to: textStorage, in: text, color: PlatformColor(theme.number))
    }

    // MARK: - JSON Highlighting

    private func highlightJSON(textStorage: NSTextStorage, text: String) {
        // Keys (strings followed by colon)
        applyPattern("\"[^\"]*\"\\s*:", to: textStorage, in: text, color: PlatformColor(theme.attribute))

        // String values
        applyPattern(":\\s*\"[^\"]*\"", to: textStorage, in: text, color: PlatformColor(theme.string))

        // Numbers
        applyPattern(":\\s*-?\\d+\\.?\\d*([eE][+-]?\\d+)?", to: textStorage, in: text, color: PlatformColor(theme.number))

        // Booleans and null
        applyPattern("\\b(true|false|null)\\b", to: textStorage, in: text, color: PlatformColor(theme.keyword))
    }

    // MARK: - Config File Highlighting

    private func highlightConfig(textStorage: NSTextStorage, text: String) {
        // Comments (# or ;)
        applyPattern("^\\s*[#;].*$", to: textStorage, in: text, color: PlatformColor(theme.comment), options: .anchorsMatchLines)

        // Section headers [section]
        applyPattern("^\\s*\\[[^\\]]+\\]\\s*$", to: textStorage, in: text, color: PlatformColor(theme.tag), options: .anchorsMatchLines)

        // Keys (before = or :)
        applyPattern("^\\s*([a-zA-Z_][a-zA-Z0-9_.-]*)\\s*[=:]", to: textStorage, in: text, color: PlatformColor(theme.attribute), options: .anchorsMatchLines)

        // Strings
        applyPattern("\"[^\"]*\"", to: textStorage, in: text, color: PlatformColor(theme.string))
        applyPattern("'[^']*'", to: textStorage, in: text, color: PlatformColor(theme.string))

        // Numbers
        applyPattern("\\b\\d+(\\.\\d+)?\\b", to: textStorage, in: text, color: PlatformColor(theme.number))

        // Boolean values
        applyPattern("\\b(true|false|yes|no|on|off|enabled|disabled|none|auto)\\b", to: textStorage, in: text, color: PlatformColor(theme.keyword), options: .caseInsensitive)

        // Environment variables
        applyPattern("\\$\\{?[A-Z_][A-Z0-9_]*\\}?", to: textStorage, in: text, color: PlatformColor(theme.type))
    }

    // MARK: - Markdown Highlighting

    private func highlightMarkdown(textStorage: NSTextStorage, text: String) {
        // Headers
        applyPattern("^#{1,6}\\s.*$", to: textStorage, in: text, color: PlatformColor(theme.keyword), options: .anchorsMatchLines)

        // Bold
        applyPattern("\\*\\*[^*]+\\*\\*", to: textStorage, in: text, color: PlatformColor(theme.type))
        applyPattern("__[^_]+__", to: textStorage, in: text, color: PlatformColor(theme.type))

        // Italic
        applyPattern("\\*[^*]+\\*", to: textStorage, in: text, color: PlatformColor(theme.string))
        applyPattern("_[^_]+_", to: textStorage, in: text, color: PlatformColor(theme.string))

        // Code blocks
        applyPattern("```[\\s\\S]*?```", to: textStorage, in: text, color: PlatformColor(theme.function))

        // Inline code
        applyPattern("`[^`]+`", to: textStorage, in: text, color: PlatformColor(theme.function))

        // Links
        applyPattern("\\[[^\\]]+\\]\\([^)]+\\)", to: textStorage, in: text, color: PlatformColor(theme.attribute))

        // Block quotes
        applyPattern("^>.*$", to: textStorage, in: text, color: PlatformColor(theme.comment), options: .anchorsMatchLines)
    }

    // MARK: - Pattern Application Helpers

    private func applyPattern(_ pattern: String, to textStorage: NSTextStorage, in text: String, color: PlatformColor, options: NSRegularExpression.Options = []) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let range = NSRange(location: 0, length: (text as NSString).length)

        for match in regex.matches(in: text, options: [], range: range) {
            if match.range.location + match.range.length <= textStorage.length {
                textStorage.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }
    }

    private func applyPatternInRange(_ limitRange: NSRange, pattern: String, to textStorage: NSTextStorage, in text: String, color: PlatformColor, options: NSRegularExpression.Options = []) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }

        for match in regex.matches(in: text, options: [], range: limitRange) {
            if match.range.location + match.range.length <= textStorage.length {
                textStorage.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }
    }

    private func highlightNestedLanguage(openPattern: String, closePattern: String, in text: String, textStorage: NSTextStorage, highlightBlock: (NSRange) -> Void) {
        guard let openRegex = try? NSRegularExpression(pattern: openPattern, options: .caseInsensitive),
              let closeRegex = try? NSRegularExpression(pattern: closePattern, options: .caseInsensitive) else { return }

        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let openMatches = openRegex.matches(in: text, options: [], range: fullRange)

        for openMatch in openMatches {
            let searchStart = openMatch.range.location + openMatch.range.length
            let searchRange = NSRange(location: searchStart, length: fullRange.length - searchStart)

            if let closeMatch = closeRegex.firstMatch(in: text, options: [], range: searchRange) {
                let contentStart = searchStart
                let contentEnd = closeMatch.range.location
                let contentRange = NSRange(location: contentStart, length: contentEnd - contentStart)

                if contentRange.length > 0 && contentRange.location + contentRange.length <= textStorage.length {
                    highlightBlock(contentRange)
                }
            }
        }
    }
}
