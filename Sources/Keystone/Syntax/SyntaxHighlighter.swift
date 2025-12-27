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
/// Uses TreeSitter for accurate parsing when available, falls back to regex.
public class SyntaxHighlighter {
    let language: KeystoneLanguage
    let theme: KeystoneTheme
    private var treeSitterHighlighter: TreeSitterHighlighter?

    public init(language: KeystoneLanguage, theme: KeystoneTheme) {
        self.language = language
        self.theme = theme

        // Initialize TreeSitter highlighter
        self.treeSitterHighlighter = TreeSitterHighlighter(language: language, theme: theme)
    }

    /// Applies syntax highlighting to a portion of the text storage.
    /// - Parameters:
    ///   - textStorage: The text storage to apply highlighting to.
    ///   - text: The substring to highlight.
    ///   - offset: The offset in the text storage where this substring starts.
    public func highlightRange(textStorage: NSTextStorage, text: String, offset: Int) {
        guard !text.isEmpty else { return }

        // For viewport highlighting, use regex-based approach (faster for partial updates)
        // TreeSitter requires full document parsing, so skip it for partial highlights
        switch language {
        case .html, .xml:
            highlightHTMLInRange(textStorage: textStorage, text: text, offset: offset)
        case .css:
            highlightCSSInOffset(textStorage: textStorage, text: text, offset: offset)
        case .json:
            highlightJSONInOffset(textStorage: textStorage, text: text, offset: offset)
        case .conf:
            highlightConfigInOffset(textStorage: textStorage, text: text, offset: offset)
        case .markdown:
            highlightMarkdownInOffset(textStorage: textStorage, text: text, offset: offset)
        case .plainText:
            break
        default:
            highlightGenericInOffset(textStorage: textStorage, text: text, offset: offset)
        }
    }

    /// Applies syntax highlighting to the given text storage.
    public func highlight(textStorage: NSTextStorage, text: String) {
        guard !text.isEmpty else { return }

        // Try TreeSitter first for supported languages
        if let tsHighlighter = treeSitterHighlighter, tsHighlighter.isTreeSitterAvailable {
            highlightWithTreeSitter(tsHighlighter, textStorage: textStorage, text: text)

            // For HTML, also apply nested language highlighting for style/script blocks
            // TreeSitter doesn't handle embedded languages well, so we supplement with regex
            if language == .html || language == .xml {
                highlightHTMLNestedLanguages(textStorage: textStorage, text: text)
            }
            return
        }

        // Fall back to regex-based highlighting
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

    // MARK: - TreeSitter Highlighting

    private func highlightWithTreeSitter(_ highlighter: TreeSitterHighlighter, textStorage: NSTextStorage, text: String) {
        let ranges = highlighter.parse(text)

        for range in ranges {
            guard range.start >= 0 && range.end <= text.utf8.count else { continue }

            // Convert byte offsets to NSRange
            let utf8 = text.utf8
            guard let startIndex = utf8.index(utf8.startIndex, offsetBy: range.start, limitedBy: utf8.endIndex),
                  let endIndex = utf8.index(utf8.startIndex, offsetBy: range.end, limitedBy: utf8.endIndex) else {
                continue
            }

            let startOffset = text.distance(from: text.startIndex, to: String.Index(startIndex, within: text) ?? text.startIndex)
            let endOffset = text.distance(from: text.startIndex, to: String.Index(endIndex, within: text) ?? text.endIndex)
            let nsRange = NSRange(location: startOffset, length: endOffset - startOffset)

            guard nsRange.location >= 0 && nsRange.location + nsRange.length <= textStorage.length else { continue }

            let color = highlighter.color(for: range.tokenType)
            textStorage.addAttribute(.foregroundColor, value: color, range: nsRange)
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

    /// Highlights CSS and JavaScript inside HTML style/script tags.
    /// Used as a supplement to TreeSitter which doesn't handle embedded languages well.
    private func highlightHTMLNestedLanguages(textStorage: NSTextStorage, text: String) {
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

    // MARK: - Offset-Based Pattern Application (for viewport highlighting)

    private func applyPatternWithOffset(_ pattern: String, to textStorage: NSTextStorage, in text: String, offset: Int, color: PlatformColor, options: NSRegularExpression.Options = []) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let range = NSRange(location: 0, length: (text as NSString).length)

        for match in regex.matches(in: text, options: [], range: range) {
            let adjustedRange = NSRange(location: match.range.location + offset, length: match.range.length)
            if adjustedRange.location + adjustedRange.length <= textStorage.length {
                textStorage.addAttribute(.foregroundColor, value: color, range: adjustedRange)
            }
        }
    }

    // MARK: - Offset-Based Language Highlighters

    private func highlightGenericInOffset(textStorage: NSTextStorage, text: String, offset: Int) {
        // Keywords
        for keyword in language.keywords {
            applyPatternWithOffset("\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b",
                        to: textStorage, in: text, offset: offset, color: PlatformColor(theme.keyword))
        }

        // Types
        for type in language.types {
            applyPatternWithOffset("\\b\(NSRegularExpression.escapedPattern(for: type))\\b",
                        to: textStorage, in: text, offset: offset, color: PlatformColor(theme.type))
        }

        // Function calls
        applyPatternWithOffset("\\b([a-zA-Z_][a-zA-Z0-9_]*)\\s*\\(", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.function))

        // Strings
        applyPatternWithOffset("\"[^\"\\\\]*(?:\\\\.[^\"\\\\]*)*\"", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.string))
        applyPatternWithOffset("'[^'\\\\]*(?:\\\\.[^'\\\\]*)*'", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.string))
        applyPatternWithOffset("`[^`]*`", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.string))

        // Comments
        applyPatternWithOffset("//.*$", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.comment), options: .anchorsMatchLines)
        if language == .python || language == .shell || language == .yaml || language == .ruby {
            applyPatternWithOffset("#.*$", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.comment), options: .anchorsMatchLines)
        }
        applyPatternWithOffset("/\\*[\\s\\S]*?\\*/", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.comment))

        // Numbers
        applyPatternWithOffset("\\b\\d+\\.?\\d*([eE][+-]?\\d+)?\\b", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.number))
        applyPatternWithOffset("\\b0x[0-9a-fA-F]+\\b", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.number))
    }

    private func highlightHTMLInRange(textStorage: NSTextStorage, text: String, offset: Int) {
        // Tags
        applyPatternWithOffset("</?\\s*([a-zA-Z][a-zA-Z0-9]*)", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.tag))
        // Attributes
        applyPatternWithOffset("\\s([a-zA-Z][a-zA-Z0-9-]*)\\s*=", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.attribute))
        // Strings
        applyPatternWithOffset("\"[^\"]*\"", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.string))
        applyPatternWithOffset("'[^']*'", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.string))
        // Comments
        applyPatternWithOffset("<!--[\\s\\S]*?-->", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.comment))
    }

    private func highlightCSSInOffset(textStorage: NSTextStorage, text: String, offset: Int) {
        applyPatternWithOffset("[.#]?[a-zA-Z_][a-zA-Z0-9_-]*(?=\\s*[\\{,])", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.tag))
        applyPatternWithOffset("([a-zA-Z-]+)\\s*:", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.attribute))
        applyPatternWithOffset(":\\s*([^;{}]+)", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.type))
        applyPatternWithOffset("/\\*[\\s\\S]*?\\*/", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.comment))
        applyPatternWithOffset("\"[^\"]*\"", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.string))
        applyPatternWithOffset("'[^']*'", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.string))
        applyPatternWithOffset("\\b\\d+(\\.\\d+)?(px|em|rem|%|vh|vw|pt|cm|mm)?\\b", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.number))
        applyPatternWithOffset("#[0-9a-fA-F]{3,8}\\b", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.number))
    }

    private func highlightJSONInOffset(textStorage: NSTextStorage, text: String, offset: Int) {
        applyPatternWithOffset("\"[^\"]*\"\\s*:", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.attribute))
        applyPatternWithOffset(":\\s*\"[^\"]*\"", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.string))
        applyPatternWithOffset(":\\s*-?\\d+\\.?\\d*([eE][+-]?\\d+)?", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.number))
        applyPatternWithOffset("\\b(true|false|null)\\b", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.keyword))
    }

    private func highlightConfigInOffset(textStorage: NSTextStorage, text: String, offset: Int) {
        applyPatternWithOffset("^\\s*[#;].*$", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.comment), options: .anchorsMatchLines)
        applyPatternWithOffset("^\\s*\\[[^\\]]+\\]\\s*$", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.tag), options: .anchorsMatchLines)
        applyPatternWithOffset("^\\s*([a-zA-Z_][a-zA-Z0-9_.-]*)\\s*[=:]", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.attribute), options: .anchorsMatchLines)
        applyPatternWithOffset("\"[^\"]*\"", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.string))
        applyPatternWithOffset("'[^']*'", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.string))
        applyPatternWithOffset("\\b\\d+(\\.\\d+)?\\b", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.number))
        applyPatternWithOffset("\\b(true|false|yes|no|on|off|enabled|disabled|none|auto)\\b", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.keyword), options: .caseInsensitive)
    }

    private func highlightMarkdownInOffset(textStorage: NSTextStorage, text: String, offset: Int) {
        applyPatternWithOffset("^#{1,6}\\s.*$", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.keyword), options: .anchorsMatchLines)
        applyPatternWithOffset("\\*\\*[^*]+\\*\\*", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.type))
        applyPatternWithOffset("__[^_]+__", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.type))
        applyPatternWithOffset("\\*[^*]+\\*", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.string))
        applyPatternWithOffset("_[^_]+_", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.string))
        applyPatternWithOffset("```[\\s\\S]*?```", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.function))
        applyPatternWithOffset("`[^`]+`", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.function))
        applyPatternWithOffset("\\[[^\\]]+\\]\\([^)]+\\)", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.attribute))
        applyPatternWithOffset("^>.*$", to: textStorage, in: text, offset: offset, color: PlatformColor(theme.comment), options: .anchorsMatchLines)
    }
}
