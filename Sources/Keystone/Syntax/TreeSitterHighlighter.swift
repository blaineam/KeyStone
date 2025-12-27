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

    public init(language: KeystoneLanguage, theme: KeystoneTheme) {
        self.language = language
        self.theme = theme
        self.parser = ts_parser_new()

        // Set the language grammar
        if let parser = self.parser {
            self.hasLanguage = Self.setLanguage(parser: parser, language: language)
        }
    }

    deinit {
        if let tree = tree {
            ts_tree_delete(tree)
        }
        if let parser = parser {
            ts_parser_delete(parser)
        }
    }

    /// Returns whether TreeSitter parsing is available for this language
    public var isTreeSitterAvailable: Bool {
        hasLanguage
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
    /// - Parameter text: The source code to parse.
    /// - Returns: An array of highlight ranges with their associated token types.
    public func parse(_ text: String) -> [HighlightRange] {
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

        return ranges
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
