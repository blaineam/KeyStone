//
//  TreeSitterHighlighter.swift
//  Keystone
//
//  TreeSitter-based syntax highlighting with language grammar support.
//

import Foundation
@_implementationOnly import TreeSitter
@_implementationOnly import TreeSitterSwift
@_implementationOnly import TreeSitterPython
@_implementationOnly import TreeSitterJavaScript
@_implementationOnly import TreeSitterTypeScript
@_implementationOnly import TreeSitterJSON
@_implementationOnly import TreeSitterHTML
@_implementationOnly import TreeSitterCSS
@_implementationOnly import TreeSitterC
@_implementationOnly import TreeSitterCPP
@_implementationOnly import TreeSitterGo
@_implementationOnly import TreeSitterRust
@_implementationOnly import TreeSitterRuby
@_implementationOnly import TreeSitterBash
@_implementationOnly import TreeSitterYAML
@_implementationOnly import TreeSitterMarkdown

/// A syntax highlighter that uses TreeSitter for accurate parsing.
public class TreeSitterHighlighter {
    private var parser: OpaquePointer?
    private var tree: OpaquePointer?
    private let language: KeystoneLanguage
    private let theme: KeystoneTheme
    private var hasLanguage: Bool = false

    // Caching for performance - byte-based ranges from TreeSitter
    private var cachedRanges: [HighlightRange] = []
    private var cachedTextHash: Int = 0
    private let cacheLock = NSLock()

    // Pre-converted character ranges for fast highlighting (avoids O(n) conversions on main thread)
    private var cachedCharRanges: [(range: NSRange, tokenType: TokenType)] = []

    // Background parsing
    private static let parseQueue = DispatchQueue(label: "com.keystone.treesitter.parse", qos: .userInitiated)
    private var isParsing = false
    private var pendingParseText: String?
    private var pendingCompletion: (([(range: NSRange, tokenType: TokenType)]) -> Void)?

    // Embedded language parsers for HTML
    private var cssParser: OpaquePointer?
    private var jsParser: OpaquePointer?

    public init(language: KeystoneLanguage, theme: KeystoneTheme) {
        self.language = language
        self.theme = theme
        self.parser = ts_parser_new()

        // Set the language grammar
        if let parser = self.parser {
            self.hasLanguage = Self.setLanguage(parser: parser, language: language)
        }

        // Initialize embedded language parsers for HTML
        if language == .html {
            cssParser = ts_parser_new()
            jsParser = ts_parser_new()
            if let css = cssParser {
                _ = ts_parser_set_language(css, tree_sitter_css())
            }
            if let js = jsParser {
                _ = ts_parser_set_language(js, tree_sitter_javascript())
            }
        }
    }

    deinit {
        if let tree = tree {
            ts_tree_delete(tree)
        }
        if let parser = parser {
            ts_parser_delete(parser)
        }
        if let cssParser = cssParser {
            ts_parser_delete(cssParser)
        }
        if let jsParser = jsParser {
            ts_parser_delete(jsParser)
        }
    }

    /// Invalidates the cache, forcing a re-parse on next call
    public func invalidateCache() {
        cacheLock.lock()
        cachedTextHash = 0
        cachedRanges = []
        cachedCharRanges = []
        cacheLock.unlock()
    }

    /// Returns pre-converted character ranges for fast highlighting
    public func getCachedCharRanges() -> [(range: NSRange, tokenType: TokenType)] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedCharRanges
    }

    /// Returns whether TreeSitter parsing is available for this language
    public var isTreeSitterAvailable: Bool {
        hasLanguage
    }

    /// Returns cached ranges if available, otherwise returns empty array
    /// Use parseAsync to trigger background parsing
    public func getCachedRanges() -> [HighlightRange] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedRanges
    }

    /// Returns true if cache is valid for the given text
    public func hasCachedRanges(for text: String) -> Bool {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return text.hashValue == cachedTextHash && !cachedRanges.isEmpty
    }

    /// Parses text on a background thread and calls completion when done
    /// - Parameters:
    ///   - text: The source code to parse
    ///   - completion: Called on main thread when parsing completes with pre-converted character ranges
    public func parseAsync(_ text: String, completion: @escaping ([(range: NSRange, tokenType: TokenType)]) -> Void) {
        // Check cache first
        cacheLock.lock()
        let textHash = text.hashValue
        if textHash == cachedTextHash && !cachedCharRanges.isEmpty {
            let charRanges = cachedCharRanges
            cacheLock.unlock()
            DispatchQueue.main.async {
                completion(charRanges)
            }
            return
        }

        // Already parsing? Store pending request and completion
        if isParsing {
            pendingParseText = text
            pendingCompletion = completion
            cacheLock.unlock()
            return
        }

        isParsing = true
        cacheLock.unlock()

        // Parse on background thread
        Self.parseQueue.async { [weak self] in
            guard let self = self else { return }

            let ranges = self.parseSync(text)

            // Convert byte ranges to character ranges on background thread (expensive operation)
            let charRanges = self.convertToCharRanges(ranges, in: text)

            self.cacheLock.lock()
            self.cachedTextHash = textHash
            self.cachedRanges = ranges
            self.cachedCharRanges = charRanges
            self.isParsing = false

            // Check for pending parse request
            let pending = self.pendingParseText
            let pendingComp = self.pendingCompletion
            self.pendingParseText = nil
            self.pendingCompletion = nil
            self.cacheLock.unlock()

            DispatchQueue.main.async {
                completion(charRanges)
            }

            // Handle pending request if text changed while parsing
            if let pendingText = pending {
                let compToUse = pendingComp ?? completion
                if pendingText.hashValue != textHash {
                    self.parseAsync(pendingText, completion: compToUse)
                } else {
                    // Same text, just call the pending completion with cached results
                    DispatchQueue.main.async {
                        compToUse(charRanges)
                    }
                }
            }
        }
    }

    /// Converts byte-based ranges to character-based NSRanges (expensive, do on background thread)
    private func convertToCharRanges(_ ranges: [HighlightRange], in text: String) -> [(range: NSRange, tokenType: TokenType)] {
        // Build a byte-to-character offset mapping for efficient conversion
        // This is O(n) once instead of O(n) per range
        let utf8 = text.utf8
        var byteToCharOffset: [Int] = []
        byteToCharOffset.reserveCapacity(utf8.count + 1)

        var charOffset = 0
        for (byteIndex, _) in utf8.enumerated() {
            while byteToCharOffset.count <= byteIndex {
                byteToCharOffset.append(charOffset)
            }
            // Count characters (UTF-8 continuation bytes don't start new characters)
            let byte = utf8[utf8.index(utf8.startIndex, offsetBy: byteIndex)]
            if (byte & 0xC0) != 0x80 { // Not a continuation byte
                charOffset += 1
            }
        }
        // Add final entry for end of string
        byteToCharOffset.append(charOffset)

        var result: [(range: NSRange, tokenType: TokenType)] = []
        result.reserveCapacity(ranges.count)

        let utf8Count = utf8.count

        for range in ranges {
            guard range.start >= 0 && range.end <= utf8Count else { continue }
            guard range.start < byteToCharOffset.count && range.end <= byteToCharOffset.count else { continue }

            let startChar = byteToCharOffset[range.start]
            let endChar = range.end < byteToCharOffset.count ? byteToCharOffset[range.end] : charOffset

            let nsRange = NSRange(location: startChar, length: endChar - startChar)
            guard nsRange.length > 0 else { continue }

            result.append((range: nsRange, tokenType: range.tokenType))
        }

        return result
    }

    /// Synchronous parsing (called on background thread)
    private func parseSync(_ text: String) -> [HighlightRange] {
        guard let parser = parser, hasLanguage else { return [] }

        // Delete previous tree if exists
        if let oldTree = tree {
            ts_tree_delete(oldTree)
            self.tree = nil
        }

        // Parse the text
        let bytes = Array(text.utf8)
        tree = bytes.withUnsafeBufferPointer { buffer in
            ts_parser_parse_string(
                parser,
                nil,
                buffer.baseAddress,
                UInt32(buffer.count)
            )
        }

        guard let tree = tree else { return [] }

        // Walk the tree and extract highlight ranges
        let rootNode = ts_tree_root_node(tree)
        var ranges: [HighlightRange] = []
        walkTree(node: rootNode, in: text, ranges: &ranges)

        // For HTML, also parse embedded CSS and JavaScript
        if language == .html {
            parseEmbeddedLanguages(text: text, ranges: &ranges)
        }

        return ranges
    }

    /// Sets the TreeSitter language on the parser
    private static func setLanguage(parser: OpaquePointer, language: KeystoneLanguage) -> Bool {
        switch language {
        case .swift:
            return ts_parser_set_language(parser, tree_sitter_swift())
        case .python:
            return ts_parser_set_language(parser, tree_sitter_python())
        case .javascript:
            return ts_parser_set_language(parser, tree_sitter_javascript())
        case .typescript:
            return ts_parser_set_language(parser, tree_sitter_typescript())
        case .json:
            return ts_parser_set_language(parser, tree_sitter_json())
        case .html:
            return ts_parser_set_language(parser, tree_sitter_html())
        case .css:
            return ts_parser_set_language(parser, tree_sitter_css())
        case .c:
            return ts_parser_set_language(parser, tree_sitter_c())
        case .cpp:
            return ts_parser_set_language(parser, tree_sitter_cpp())
        case .go:
            return ts_parser_set_language(parser, tree_sitter_go())
        case .rust:
            return ts_parser_set_language(parser, tree_sitter_rust())
        case .ruby:
            return ts_parser_set_language(parser, tree_sitter_ruby())
        case .shell:
            return ts_parser_set_language(parser, tree_sitter_bash())
        case .yaml:
            return ts_parser_set_language(parser, tree_sitter_yaml())
        case .markdown:
            return ts_parser_set_language(parser, tree_sitter_markdown())
        default:
            return false
        }
    }

    /// Parses the given text and returns syntax highlighting ranges.
    /// This method parses synchronously if there's no cache, but caches results.
    /// For UI code, prefer using parseAsync to avoid blocking the main thread.
    /// - Parameter text: The source code to parse.
    /// - Returns: An array of highlight ranges with their associated token types.
    public func parse(_ text: String) -> [HighlightRange] {
        guard hasLanguage else { return [] }

        // Check cache first
        cacheLock.lock()
        let textHash = text.hashValue
        if textHash == cachedTextHash && !cachedRanges.isEmpty {
            let result = cachedRanges
            cacheLock.unlock()
            return result
        }
        cacheLock.unlock()

        // Parse synchronously (for backwards compatibility and tests)
        let ranges = parseSync(text)

        // Cache results
        cacheLock.lock()
        cachedTextHash = textHash
        cachedRanges = ranges
        cacheLock.unlock()

        return ranges
    }

    /// Parses embedded CSS in <style> tags and JavaScript in <script> tags
    private func parseEmbeddedLanguages(text: String, ranges: inout [HighlightRange]) {
        // Find <style> blocks and parse as CSS
        parseEmbeddedBlocks(text: text, tagName: "style", parser: cssParser, language: .css, ranges: &ranges)

        // Find <script> blocks and parse as JavaScript
        parseEmbeddedBlocks(text: text, tagName: "script", parser: jsParser, language: .javascript, ranges: &ranges)
    }

    private func parseEmbeddedBlocks(text: String, tagName: String, parser: OpaquePointer?, language: KeystoneLanguage, ranges: inout [HighlightRange]) {
        guard let parser = parser else { return }

        // Pattern to match opening and closing tags
        let openPattern = "<\(tagName)[^>]*>"
        let closePattern = "</\(tagName)>"

        guard let openRegex = try? NSRegularExpression(pattern: openPattern, options: .caseInsensitive),
              let closeRegex = try? NSRegularExpression(pattern: closePattern, options: .caseInsensitive) else {
            return
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        let openMatches = openRegex.matches(in: text, options: [], range: fullRange)
        let closeMatches = closeRegex.matches(in: text, options: [], range: fullRange)

        // Match opening tags with their corresponding closing tags
        for openMatch in openMatches {
            let openEnd = openMatch.range.location + openMatch.range.length

            // Find the next closing tag after this opening tag
            guard let closeMatch = closeMatches.first(where: { $0.range.location > openEnd }) else {
                continue
            }

            let contentStart = openEnd
            let contentEnd = closeMatch.range.location
            let contentLength = contentEnd - contentStart

            guard contentLength > 0 else { continue }

            // Extract the content between tags
            let contentRange = NSRange(location: contentStart, length: contentLength)
            let content = nsText.substring(with: contentRange)

            // Convert contentStart from UTF-16 to UTF-8 byte offset
            let swiftStartIndex = String.Index(utf16Offset: contentStart, in: text)
            guard swiftStartIndex < text.endIndex,
                  let utf8Index = swiftStartIndex.samePosition(in: text.utf8) else {
                continue
            }
            let byteOffset = text.utf8.distance(from: text.utf8.startIndex, to: utf8Index)

            // Parse the content with the appropriate language parser
            let contentBytes = Array(content.utf8)
            guard let embeddedTree = contentBytes.withUnsafeBufferPointer({ buffer in
                ts_parser_parse_string(
                    parser,
                    nil,
                    buffer.baseAddress,
                    UInt32(buffer.count)
                )
            }) else {
                continue
            }

            // Walk the embedded tree and collect ranges with offset
            let rootNode = ts_tree_root_node(embeddedTree)
            walkEmbeddedTree(node: rootNode, in: content, byteOffset: byteOffset, language: language, ranges: &ranges)

            ts_tree_delete(embeddedTree)
        }
    }

    private func walkEmbeddedTree(node: TSNode, in text: String, byteOffset: Int, language: KeystoneLanguage, ranges: inout [HighlightRange]) {
        let nodeType = String(cString: ts_node_type(node))
        let startByte = Int(ts_node_start_byte(node))
        let endByte = Int(ts_node_end_byte(node))

        // Map node type to token type using the embedded language's mappings
        if let tokenType = mapNodeTypeToToken(nodeType, language: language) {
            ranges.append(HighlightRange(
                start: startByte + byteOffset,
                end: endByte + byteOffset,
                tokenType: tokenType
            ))
        }

        // Recursively process children
        let childCount = ts_node_child_count(node)
        for i in 0..<childCount {
            let child = ts_node_child(node, i)
            walkEmbeddedTree(node: child, in: text, byteOffset: byteOffset, language: language, ranges: &ranges)
        }
    }

    private func walkTree(node: TSNode, in text: String, ranges: inout [HighlightRange]) {
        let nodeType = String(cString: ts_node_type(node))
        let startByte = Int(ts_node_start_byte(node))
        let endByte = Int(ts_node_end_byte(node))

        // Map node type to token type
        if let tokenType = mapNodeTypeToToken(nodeType, language: language) {
            ranges.append(HighlightRange(
                start: startByte,
                end: endByte,
                tokenType: tokenType
            ))
        }

        // Recursively process children
        let childCount = ts_node_child_count(node)
        for i in 0..<childCount {
            let child = ts_node_child(node, i)
            walkTree(node: child, in: text, ranges: &ranges)
        }
    }

    private func mapNodeTypeToToken(_ nodeType: String, language: KeystoneLanguage) -> TokenType? {
        // Language-specific mappings first
        switch language {
        case .swift:
            return mapSwiftNodeType(nodeType)
        case .python:
            return mapPythonNodeType(nodeType)
        case .javascript, .typescript:
            return mapJavaScriptNodeType(nodeType)
        case .html:
            return mapHTMLNodeType(nodeType)
        case .css:
            return mapCSSNodeType(nodeType)
        case .json:
            return mapJSONNodeType(nodeType)
        default:
            return mapGenericNodeType(nodeType)
        }
    }

    // MARK: - Language-Specific Node Type Mappings

    private func mapSwiftNodeType(_ nodeType: String) -> TokenType? {
        switch nodeType {
        // Keywords
        case "import", "func", "var", "let", "class", "struct", "enum", "protocol",
             "extension", "if", "else", "guard", "switch", "case", "default",
             "for", "while", "repeat", "return", "throw", "throws", "try", "catch",
             "defer", "do", "async", "await", "private", "public", "internal",
             "fileprivate", "open", "static", "final", "override", "mutating",
             "nonmutating", "convenience", "required", "init", "deinit", "self",
             "Self", "super", "nil", "true", "false", "where", "in", "as", "is",
             "typealias", "associatedtype", "subscript", "get", "set", "willSet",
             "didSet", "inout", "some", "any", "weak", "unowned", "lazy":
            return .keyword

        // Types
        case "type_identifier", "simple_identifier":
            return .type

        // Strings
        case "line_string_literal", "multi_line_string_literal", "string_literal":
            return .string

        // Comments
        case "comment", "multiline_comment":
            return .comment

        // Numbers
        case "integer_literal", "real_literal", "boolean_literal":
            return .number

        // Functions
        case "function_declaration", "call_expression":
            return .function

        // Attributes
        case "attribute":
            return .attribute

        default:
            return nil
        }
    }

    private func mapPythonNodeType(_ nodeType: String) -> TokenType? {
        switch nodeType {
        case "import", "from", "def", "class", "if", "elif", "else", "for",
             "while", "try", "except", "finally", "with", "as", "return",
             "yield", "raise", "pass", "break", "continue", "lambda", "and",
             "or", "not", "in", "is", "global", "nonlocal", "assert", "async",
             "await", "True", "False", "None":
            return .keyword
        case "type", "identifier":
            return .type
        case "string", "concatenated_string":
            return .string
        case "comment":
            return .comment
        case "integer", "float":
            return .number
        case "function_definition", "call":
            return .function
        case "decorator":
            return .attribute
        default:
            return nil
        }
    }

    private func mapJavaScriptNodeType(_ nodeType: String) -> TokenType? {
        switch nodeType {
        case "import", "export", "from", "function", "const", "let", "var",
             "class", "extends", "if", "else", "switch", "case", "default",
             "for", "while", "do", "return", "throw", "try", "catch", "finally",
             "new", "this", "super", "async", "await", "true", "false", "null",
             "undefined", "typeof", "instanceof", "interface", "type":
            return .keyword
        case "type_identifier", "identifier":
            return .type
        case "string", "template_string", "template_literal":
            return .string
        case "comment":
            return .comment
        case "number":
            return .number
        case "function_declaration", "arrow_function", "call_expression":
            return .function
        default:
            return nil
        }
    }

    private func mapHTMLNodeType(_ nodeType: String) -> TokenType? {
        switch nodeType {
        case "tag_name", "start_tag", "end_tag", "self_closing_tag":
            return .tag
        case "attribute_name":
            return .attribute
        case "attribute_value", "quoted_attribute_value":
            return .string
        case "comment":
            return .comment
        default:
            return nil
        }
    }

    private func mapCSSNodeType(_ nodeType: String) -> TokenType? {
        switch nodeType {
        case "tag_name", "class_selector", "id_selector", "pseudo_class_selector":
            return .tag
        case "property_name":
            return .attribute
        case "string_value":
            return .string
        case "comment":
            return .comment
        case "integer_value", "float_value", "color_value":
            return .number
        case "function_name":
            return .function
        default:
            return nil
        }
    }

    private func mapJSONNodeType(_ nodeType: String) -> TokenType? {
        switch nodeType {
        case "string":
            return .string
        case "number":
            return .number
        case "true", "false", "null":
            return .keyword
        default:
            return nil
        }
    }

    private func mapGenericNodeType(_ nodeType: String) -> TokenType? {
        // Common TreeSitter node types mapped to token types
        switch nodeType {
        // Keywords
        case "if", "else", "for", "while", "return", "import", "export",
             "function", "class", "struct", "enum", "let", "var", "const",
             "func", "def", "try", "catch", "throw", "async", "await",
             "public", "private", "static", "final", "override":
            return .keyword

        // Types
        case "type_identifier", "primitive_type", "predefined_type":
            return .type

        // Strings
        case "string", "string_literal", "template_string", "raw_string":
            return .string

        // Comments
        case "comment", "line_comment", "block_comment", "documentation_comment":
            return .comment

        // Numbers
        case "number", "integer", "float", "number_literal", "integer_literal":
            return .number

        // Functions
        case "function_declaration", "method_declaration", "call_expression":
            return .function

        // Tags (HTML/XML)
        case "tag_name", "start_tag", "end_tag", "self_closing_tag":
            return .tag

        // Attributes
        case "attribute_name", "property_identifier":
            return .attribute

        // Operators
        case "operator", "binary_operator", "unary_operator":
            return .operator

        // Punctuation
        case "punctuation", "bracket", "brace", "paren":
            return .punctuation

        default:
            return nil
        }
    }

    /// Gets the color for a token type based on the current theme.
    public func color(for tokenType: TokenType) -> PlatformColor {
        switch tokenType {
        case .keyword:
            return PlatformColor(theme.keyword)
        case .type:
            return PlatformColor(theme.type)
        case .string:
            return PlatformColor(theme.string)
        case .comment:
            return PlatformColor(theme.comment)
        case .number:
            return PlatformColor(theme.number)
        case .function:
            return PlatformColor(theme.function)
        case .tag:
            return PlatformColor(theme.tag)
        case .attribute:
            return PlatformColor(theme.attribute)
        case .operator, .punctuation:
            return PlatformColor(theme.text)
        }
    }
}

// MARK: - Supporting Types

/// Represents a range of text with a specific token type.
public struct HighlightRange: Equatable, Sendable {
    /// The start byte offset.
    public let start: Int
    /// The end byte offset.
    public let end: Int
    /// The type of token.
    public let tokenType: TokenType

    public init(start: Int, end: Int, tokenType: TokenType) {
        self.start = start
        self.end = end
        self.tokenType = tokenType
    }
}

/// Types of syntax tokens for highlighting.
public enum TokenType: String, Sendable {
    case keyword
    case type
    case string
    case comment
    case number
    case function
    case tag
    case attribute
    case `operator`
    case punctuation
}

// MARK: - Incremental Parsing Support

extension TreeSitterHighlighter {
    /// Whether we have a valid tree for incremental updates
    public var hasTree: Bool {
        tree != nil
    }

    /// Updates the syntax tree incrementally after an edit (async version).
    /// This is MUCH faster than a full reparse for small edits.
    /// - Parameters:
    ///   - text: The new text content after the edit.
    ///   - edit: The edit that was made.
    ///   - completion: Called on main thread when parsing completes.
    public func updateAsync(_ text: String, with edit: TextEdit, completion: @escaping ([(range: NSRange, tokenType: TokenType)]) -> Void) {
        // If no tree exists, fall back to full parse
        guard tree != nil else {
            parseAsync(text, completion: completion)
            return
        }

        cacheLock.lock()
        // If already parsing, queue this as pending
        if isParsing {
            pendingParseText = text
            pendingCompletion = completion
            cacheLock.unlock()
            return
        }
        isParsing = true
        cacheLock.unlock()

        // Do incremental parse on background thread
        Self.parseQueue.async { [weak self] in
            guard let self = self else { return }

            let ranges = self.updateSync(text, with: edit)
            let charRanges = self.convertToCharRanges(ranges, in: text)
            let textHash = text.hashValue

            self.cacheLock.lock()
            self.cachedTextHash = textHash
            self.cachedRanges = ranges
            self.cachedCharRanges = charRanges
            self.isParsing = false

            let pending = self.pendingParseText
            let pendingComp = self.pendingCompletion
            self.pendingParseText = nil
            self.pendingCompletion = nil
            self.cacheLock.unlock()

            DispatchQueue.main.async {
                completion(charRanges)
            }

            // Handle pending request
            if let pendingText = pending, let pendingCallback = pendingComp {
                if pendingText.hashValue != textHash {
                    self.parseAsync(pendingText, completion: pendingCallback)
                } else {
                    DispatchQueue.main.async {
                        pendingCallback(charRanges)
                    }
                }
            }
        }
    }

    /// Synchronous incremental update (called on background thread)
    private func updateSync(_ text: String, with edit: TextEdit) -> [HighlightRange] {
        guard let parser = parser, let oldTree = tree, hasLanguage else {
            return parseSync(text)
        }

        // Create TSInputEdit
        var inputEdit = TSInputEdit(
            start_byte: UInt32(edit.startByte),
            old_end_byte: UInt32(edit.oldEndByte),
            new_end_byte: UInt32(edit.newEndByte),
            start_point: TSPoint(row: UInt32(edit.startRow), column: UInt32(edit.startColumn)),
            old_end_point: TSPoint(row: UInt32(edit.oldEndRow), column: UInt32(edit.oldEndColumn)),
            new_end_point: TSPoint(row: UInt32(edit.newEndRow), column: UInt32(edit.newEndColumn))
        )

        ts_tree_edit(oldTree, &inputEdit)

        // Re-parse with the old tree for incremental parsing (FAST!)
        let bytes = Array(text.utf8)
        let newTree = bytes.withUnsafeBufferPointer { buffer in
            ts_parser_parse_string(
                parser,
                oldTree,
                buffer.baseAddress,
                UInt32(buffer.count)
            )
        }

        ts_tree_delete(oldTree)
        self.tree = newTree

        guard let tree = self.tree else { return [] }

        let rootNode = ts_tree_root_node(tree)
        var ranges: [HighlightRange] = []
        walkTree(node: rootNode, in: text, ranges: &ranges)

        // For HTML, also parse embedded CSS and JavaScript
        if language == .html {
            parseEmbeddedLanguages(text: text, ranges: &ranges)
        }

        return ranges
    }

    /// Updates the syntax tree incrementally after an edit.
    /// - Parameters:
    ///   - text: The new text content.
    ///   - edit: The edit that was made.
    /// - Returns: Updated highlight ranges.
    public func update(_ text: String, with edit: TextEdit) -> [HighlightRange] {
        guard let parser = parser, let oldTree = tree, hasLanguage else {
            return parse(text)
        }

        // Create TSInputEdit
        var inputEdit = TSInputEdit(
            start_byte: UInt32(edit.startByte),
            old_end_byte: UInt32(edit.oldEndByte),
            new_end_byte: UInt32(edit.newEndByte),
            start_point: TSPoint(row: UInt32(edit.startRow), column: UInt32(edit.startColumn)),
            old_end_point: TSPoint(row: UInt32(edit.oldEndRow), column: UInt32(edit.oldEndColumn)),
            new_end_point: TSPoint(row: UInt32(edit.newEndRow), column: UInt32(edit.newEndColumn))
        )

        ts_tree_edit(oldTree, &inputEdit)

        // Re-parse with the old tree for incremental parsing
        let bytes = Array(text.utf8)
        let newTree = bytes.withUnsafeBufferPointer { buffer in
            ts_parser_parse_string(
                parser,
                oldTree,
                buffer.baseAddress,
                UInt32(buffer.count)
            )
        }

        ts_tree_delete(oldTree)
        self.tree = newTree

        guard let tree = self.tree else { return [] }

        let rootNode = ts_tree_root_node(tree)
        var ranges: [HighlightRange] = []
        walkTree(node: rootNode, in: text, ranges: &ranges)

        return ranges
    }
}

/// Represents a text edit for incremental parsing.
public struct TextEdit: Sendable {
    public let startByte: Int
    public let oldEndByte: Int
    public let newEndByte: Int
    public let startRow: Int
    public let startColumn: Int
    public let oldEndRow: Int
    public let oldEndColumn: Int
    public let newEndRow: Int
    public let newEndColumn: Int

    public init(
        startByte: Int,
        oldEndByte: Int,
        newEndByte: Int,
        startRow: Int,
        startColumn: Int,
        oldEndRow: Int,
        oldEndColumn: Int,
        newEndRow: Int,
        newEndColumn: Int
    ) {
        self.startByte = startByte
        self.oldEndByte = oldEndByte
        self.newEndByte = newEndByte
        self.startRow = startRow
        self.startColumn = startColumn
        self.oldEndRow = oldEndRow
        self.oldEndColumn = oldEndColumn
        self.newEndRow = newEndRow
        self.newEndColumn = newEndColumn
    }
}
