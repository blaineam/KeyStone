//
//  TreeSitterHighlighter.swift
//  Keystone
//
//  TreeSitter-based syntax highlighting with language grammar support.
//

import Foundation
import TreeSitter

/// A syntax highlighter that uses TreeSitter for accurate parsing.
public class TreeSitterHighlighter {
    private var parser: OpaquePointer?
    private var tree: OpaquePointer?
    private let language: KeystoneLanguage
    private let theme: KeystoneTheme

    public init(language: KeystoneLanguage, theme: KeystoneTheme) {
        self.language = language
        self.theme = theme
        self.parser = ts_parser_new()
    }

    deinit {
        if let tree = tree {
            ts_tree_delete(tree)
        }
        if let parser = parser {
            ts_parser_delete(parser)
        }
    }

    /// Parses the given text and returns syntax highlighting ranges.
    /// - Parameter text: The source code to parse.
    /// - Returns: An array of highlight ranges with their associated token types.
    public func parse(_ text: String) -> [HighlightRange] {
        guard let parser = parser else { return [] }

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
        if let tokenType = mapNodeTypeToToken(nodeType) {
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

    private func mapNodeTypeToToken(_ nodeType: String) -> TokenType? {
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
        guard let parser = parser, let oldTree = tree else {
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
