//
//  HighlightQueries.swift
//  Keystone
//
//  Embedded TreeSitter highlight queries for syntax highlighting.
//

import Foundation

/// Provides embedded highlight queries for various languages.
enum HighlightQueries {

    // MARK: - Swift

    static let swift = """
    ; Strings
    (line_string_literal) @string
    (multi_line_string_literal) @string
    (raw_string_literal) @string

    ; Numbers
    (integer_literal) @number
    (real_literal) @number
    (hex_literal) @number
    (oct_literal) @number
    (bin_literal) @number

    ; Booleans
    (boolean_literal) @constant.builtin

    ; Comments
    (comment) @comment
    (multiline_comment) @comment

    ; Punctuation
    ["(" ")" "[" "]" "{" "}"] @punctuation
    ["." "," ":" ";"] @punctuation
    """

    // MARK: - JavaScript

    static let javascript = """
    ; Properties
    (property_identifier) @property

    ; Strings
    (string) @string
    (template_string) @string

    ; Numbers
    (number) @number

    ; Booleans and constants
    (true) @constant.builtin
    (false) @constant.builtin
    (null) @constant.builtin

    ; Comments
    (comment) @comment
    """

    // MARK: - TypeScript

    static let typescript = """
    ; Properties
    (property_identifier) @property

    ; Types
    (type_identifier) @type
    (predefined_type) @type

    ; Strings
    (string) @string
    (template_string) @string

    ; Numbers
    (number) @number

    ; Booleans and constants
    (true) @constant.builtin
    (false) @constant.builtin
    (null) @constant.builtin

    ; Comments
    (comment) @comment
    """

    // MARK: - Python

    static let python = """
    ; Strings
    (string) @string

    ; Numbers
    (integer) @number
    (float) @number

    ; Booleans and constants
    (true) @constant.builtin
    (false) @constant.builtin
    (none) @constant.builtin

    ; Comments
    (comment) @comment
    """

    // MARK: - Go

    static let go = """
    ; Types
    (type_identifier) @type

    ; Strings
    (raw_string_literal) @string
    (interpreted_string_literal) @string

    ; Numbers
    (int_literal) @number
    (float_literal) @number
    (imaginary_literal) @number

    ; Booleans
    (true) @constant.builtin
    (false) @constant.builtin
    (nil) @constant.builtin
    (iota) @constant.builtin

    ; Comments
    (comment) @comment
    """

    // MARK: - Rust

    static let rust = """
    ; Types
    (type_identifier) @type

    ; Strings
    (string_literal) @string
    (raw_string_literal) @string
    (char_literal) @string

    ; Numbers
    (integer_literal) @number
    (float_literal) @number

    ; Booleans
    (boolean_literal) @constant.builtin

    ; Comments
    (line_comment) @comment
    (block_comment) @comment
    """

    // MARK: - C

    static let c = """
    ; Types
    (type_identifier) @type
    (primitive_type) @type
    (sized_type_specifier) @type

    ; Preprocessor
    (preproc_include) @keyword
    (preproc_def) @keyword
    (preproc_ifdef) @keyword
    (preproc_else) @keyword
    (preproc_endif) @keyword

    ; Strings
    (string_literal) @string
    (char_literal) @string

    ; Numbers
    (number_literal) @number

    ; Booleans
    (true) @constant.builtin
    (false) @constant.builtin

    ; Comments
    (comment) @comment
    """

    // MARK: - C++

    static let cpp = """
    ; Types
    (type_identifier) @type
    (primitive_type) @type
    (sized_type_specifier) @type

    ; Preprocessor
    (preproc_include) @keyword
    (preproc_def) @keyword
    (preproc_ifdef) @keyword
    (preproc_else) @keyword
    (preproc_endif) @keyword

    ; Strings
    (string_literal) @string
    (raw_string_literal) @string
    (char_literal) @string

    ; Numbers
    (number_literal) @number

    ; Booleans
    (true) @constant.builtin
    (false) @constant.builtin
    (nullptr) @constant.builtin

    ; Comments
    (comment) @comment
    """

    // MARK: - HTML

    static let html = """
    (tag_name) @tag
    (attribute_name) @property
    (attribute_value) @string
    (text) @variable
    (comment) @comment
    (doctype) @keyword

    ["<" ">" "</" "/>"] @punctuation
    """

    // MARK: - CSS

    static let css = """
    ; Selectors
    (class_selector) @type
    (id_selector) @type

    ; Properties and values
    (property_name) @property
    (color_value) @number
    (integer_value) @number
    (float_value) @number
    (string_value) @string

    ; Comments
    (comment) @comment
    """

    // MARK: - JSON

    static let json = """
    (string) @string
    (number) @number
    (true) @constant.builtin
    (false) @constant.builtin
    (null) @constant.builtin
    """

    // MARK: - YAML

    static let yaml = """
    (string_scalar) @string
    (double_quote_scalar) @string
    (single_quote_scalar) @string
    (integer_scalar) @number
    (float_scalar) @number
    (boolean_scalar) @constant.builtin
    (null_scalar) @constant.builtin
    (comment) @comment
    (anchor) @keyword
    (alias) @keyword
    """

    // MARK: - Markdown

    static let markdown = """
    (atx_heading) @keyword
    (setext_heading) @keyword
    (emphasis) @variable
    (strong_emphasis) @variable
    (code_span) @string
    (fenced_code_block) @string
    (indented_code_block) @string
    (link_destination) @string
    (link_title) @string
    (link_text) @variable
    """

    // MARK: - Bash/Shell

    static let bash = """
    ; Variables
    (variable_name) @variable
    (special_variable_name) @variable

    ; Commands
    (command_name) @function

    ; Strings
    (string) @string
    (raw_string) @string
    (heredoc_body) @string

    ; Comments
    (comment) @comment
    """

    // MARK: - Ruby

    static let ruby = """
    ; Variables
    (instance_variable) @variable
    (class_variable) @variable
    (global_variable) @variable

    ; Types
    (constant) @type

    ; Strings
    (string) @string
    (symbol) @string
    (heredoc_body) @string

    ; Numbers
    (integer) @number
    (float) @number

    ; Booleans
    (true) @constant.builtin
    (false) @constant.builtin
    (nil) @constant.builtin

    ; Comments
    (comment) @comment
    """

    // MARK: - Injection Queries

    /// Injection query for HTML to embed JavaScript in script tags and CSS in style tags
    /// The mapper looks for captures not named "language" or "injection.language" and uses
    /// the capture.properties["injection.language"] to determine the language
    static let htmlInjections = """
    ; Inject JavaScript into script tags
    (script_element (raw_text) @javascript
      (#set! injection.language "javascript"))

    ; Inject CSS into style tags
    (style_element (raw_text) @css
      (#set! injection.language "css"))
    """

    /// Injection query for Markdown code blocks
    static let markdownInjections = """
    ; Inject language based on info string in fenced code blocks
    (fenced_code_block
      (info_string (language) @injection.language)
      (code_fence_content) @injection.content)
    """
}
