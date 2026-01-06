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
    ; Types
    (type_identifier) @type
    (class_declaration name: (type_identifier) @type)
    (protocol_declaration name: (type_identifier) @type)
    (struct_declaration name: (type_identifier) @type)
    (enum_declaration name: (type_identifier) @type)
    (extension_declaration name: (type_identifier) @type)
    (actor_declaration name: (type_identifier) @type)

    ; Functions
    (function_declaration name: (simple_identifier) @function)
    (call_expression (simple_identifier) @function)

    ; Properties and variables
    (property_declaration (pattern (simple_identifier) @property))
    (value_binding_pattern (simple_identifier) @variable)

    ; Keywords
    [
      "actor"
      "any"
      "as"
      "async"
      "await"
      "break"
      "case"
      "catch"
      "class"
      "continue"
      "default"
      "defer"
      "deinit"
      "do"
      "else"
      "enum"
      "extension"
      "fallthrough"
      "fileprivate"
      "for"
      "func"
      "guard"
      "if"
      "import"
      "in"
      "init"
      "inout"
      "internal"
      "is"
      "let"
      "nonisolated"
      "open"
      "operator"
      "override"
      "private"
      "protocol"
      "public"
      "repeat"
      "rethrows"
      "return"
      "some"
      "static"
      "struct"
      "subscript"
      "super"
      "switch"
      "throw"
      "throws"
      "try"
      "typealias"
      "var"
      "where"
      "while"
    ] @keyword

    ; Builtins
    [
      "true"
      "false"
      "nil"
    ] @constant.builtin

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

    ; Comments
    (comment) @comment
    (multiline_comment) @comment

    ; Operators
    (custom_operator) @operator

    ; Punctuation
    ["(" ")" "[" "]" "{" "}"] @punctuation
    ["." "," ":" ";"] @punctuation
    """

    // MARK: - JavaScript

    static let javascript = """
    ; Variables
    (identifier) @variable

    ; Properties
    (property_identifier) @property

    ; Functions
    (function_declaration name: (identifier) @function)
    (method_definition name: (property_identifier) @function)
    (call_expression function: (identifier) @function)
    (call_expression function: (member_expression property: (property_identifier) @function))

    ; Keywords
    [
      "async"
      "await"
      "break"
      "case"
      "catch"
      "class"
      "const"
      "continue"
      "debugger"
      "default"
      "delete"
      "do"
      "else"
      "export"
      "extends"
      "finally"
      "for"
      "from"
      "function"
      "get"
      "if"
      "import"
      "in"
      "instanceof"
      "let"
      "new"
      "of"
      "return"
      "set"
      "static"
      "switch"
      "throw"
      "try"
      "typeof"
      "var"
      "void"
      "while"
      "with"
      "yield"
    ] @keyword

    ; Builtins
    [
      "true"
      "false"
      "null"
      "undefined"
    ] @constant.builtin

    ; Strings
    (string) @string
    (template_string) @string

    ; Numbers
    (number) @number

    ; Comments
    (comment) @comment
    """

    // MARK: - TypeScript

    static let typescript = """
    ; Inherit from JavaScript
    \(javascript)

    ; Type annotations
    (type_identifier) @type
    (predefined_type) @type

    ; Type parameters
    (type_parameter name: (type_identifier) @type)

    ; Interface and type declarations
    (interface_declaration name: (type_identifier) @type)
    (type_alias_declaration name: (type_identifier) @type)

    ; Additional TypeScript keywords
    [
      "abstract"
      "declare"
      "enum"
      "implements"
      "interface"
      "namespace"
      "private"
      "protected"
      "public"
      "readonly"
      "type"
    ] @keyword
    """

    // MARK: - Python

    static let python = """
    ; Variables
    (identifier) @variable

    ; Functions
    (function_definition name: (identifier) @function)
    (call function: (identifier) @function)
    (call function: (attribute attribute: (identifier) @function))

    ; Parameters
    (parameters (identifier) @variable)

    ; Types
    (class_definition name: (identifier) @type)
    (type (identifier) @type)

    ; Keywords
    [
      "and"
      "as"
      "assert"
      "async"
      "await"
      "break"
      "class"
      "continue"
      "def"
      "del"
      "elif"
      "else"
      "except"
      "exec"
      "finally"
      "for"
      "from"
      "global"
      "if"
      "import"
      "in"
      "is"
      "lambda"
      "nonlocal"
      "not"
      "or"
      "pass"
      "print"
      "raise"
      "return"
      "try"
      "while"
      "with"
      "yield"
    ] @keyword

    ; Builtins
    [
      "True"
      "False"
      "None"
    ] @constant.builtin

    ((identifier) @variable.builtin
      (#match? @variable.builtin "^(self|cls)$"))

    ; Strings
    (string) @string

    ; Numbers
    (integer) @number
    (float) @number

    ; Comments
    (comment) @comment

    ; Operators
    [
      "+"
      "-"
      "*"
      "/"
      "//"
      "%"
      "**"
      "=="
      "!="
      "<"
      "<="
      ">"
      ">="
      "&"
      "|"
      "^"
      "~"
      "<<"
      ">>"
    ] @operator
    """

    // MARK: - Go

    static let go = """
    ; Variables
    (identifier) @variable

    ; Functions
    (function_declaration name: (identifier) @function)
    (method_declaration name: (field_identifier) @function)
    (call_expression function: (identifier) @function)
    (call_expression function: (selector_expression field: (field_identifier) @function))

    ; Types
    (type_identifier) @type
    (type_declaration (type_spec name: (type_identifier) @type))

    ; Keywords
    [
      "break"
      "case"
      "chan"
      "const"
      "continue"
      "default"
      "defer"
      "else"
      "fallthrough"
      "for"
      "func"
      "go"
      "goto"
      "if"
      "import"
      "interface"
      "map"
      "package"
      "range"
      "return"
      "select"
      "struct"
      "switch"
      "type"
      "var"
    ] @keyword

    ; Builtins
    [
      "true"
      "false"
      "nil"
      "iota"
    ] @constant.builtin

    ; Strings
    (raw_string_literal) @string
    (interpreted_string_literal) @string

    ; Numbers
    (int_literal) @number
    (float_literal) @number
    (imaginary_literal) @number

    ; Comments
    (comment) @comment
    """

    // MARK: - Rust

    static let rust = """
    ; Variables
    (identifier) @variable

    ; Functions
    (function_item name: (identifier) @function)
    (call_expression function: (identifier) @function)
    (call_expression function: (field_expression field: (field_identifier) @function))

    ; Types
    (type_identifier) @type
    (struct_item name: (type_identifier) @type)
    (enum_item name: (type_identifier) @type)
    (trait_item name: (type_identifier) @type)

    ; Keywords
    [
      "as"
      "async"
      "await"
      "break"
      "const"
      "continue"
      "crate"
      "dyn"
      "else"
      "enum"
      "extern"
      "fn"
      "for"
      "if"
      "impl"
      "in"
      "let"
      "loop"
      "match"
      "mod"
      "move"
      "mut"
      "pub"
      "ref"
      "return"
      "self"
      "Self"
      "static"
      "struct"
      "super"
      "trait"
      "type"
      "unsafe"
      "use"
      "where"
      "while"
    ] @keyword

    ; Builtins
    [
      "true"
      "false"
    ] @constant.builtin

    ; Strings
    (string_literal) @string
    (raw_string_literal) @string
    (char_literal) @string

    ; Numbers
    (integer_literal) @number
    (float_literal) @number

    ; Comments
    (line_comment) @comment
    (block_comment) @comment
    """

    // MARK: - C

    static let c = """
    ; Variables
    (identifier) @variable

    ; Functions
    (function_declarator declarator: (identifier) @function)
    (call_expression function: (identifier) @function)

    ; Types
    (type_identifier) @type
    (primitive_type) @type
    (sized_type_specifier) @type

    ; Keywords
    [
      "break"
      "case"
      "const"
      "continue"
      "default"
      "do"
      "else"
      "enum"
      "extern"
      "for"
      "goto"
      "if"
      "inline"
      "register"
      "return"
      "sizeof"
      "static"
      "struct"
      "switch"
      "typedef"
      "union"
      "volatile"
      "while"
    ] @keyword

    ; Preprocessor
    (preproc_include) @keyword
    (preproc_def) @keyword
    (preproc_ifdef) @keyword
    (preproc_else) @keyword
    (preproc_endif) @keyword

    ; Builtins
    [
      "true"
      "false"
      "NULL"
    ] @constant.builtin

    ; Strings
    (string_literal) @string
    (char_literal) @string

    ; Numbers
    (number_literal) @number

    ; Comments
    (comment) @comment
    """

    // MARK: - C++

    static let cpp = """
    ; Inherit from C
    \(c)

    ; Additional C++ keywords
    [
      "catch"
      "class"
      "constexpr"
      "delete"
      "explicit"
      "friend"
      "mutable"
      "namespace"
      "new"
      "noexcept"
      "nullptr"
      "operator"
      "private"
      "protected"
      "public"
      "template"
      "this"
      "throw"
      "try"
      "typename"
      "using"
      "virtual"
    ] @keyword
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
    (pseudo_class_selector) @keyword
    (pseudo_element_selector) @keyword

    ; Properties and values
    (property_name) @property
    (plain_value) @variable
    (color_value) @number
    (integer_value) @number
    (float_value) @number
    (string_value) @string

    ; Comments
    (comment) @comment

    ; At-rules
    (at_keyword) @keyword
    """

    // MARK: - JSON

    static let json = """
    (pair key: (string) @property)
    (string) @string
    (number) @number
    [
      "true"
      "false"
      "null"
    ] @constant.builtin
    """

    // MARK: - YAML

    static let yaml = """
    (block_mapping_pair key: (flow_node) @property)
    (flow_mapping_pair key: (flow_node) @property)
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
    (special_variable_name) @variable.builtin

    ; Commands
    (command_name) @function

    ; Keywords
    [
      "case"
      "do"
      "done"
      "elif"
      "else"
      "esac"
      "fi"
      "for"
      "function"
      "if"
      "in"
      "select"
      "then"
      "until"
      "while"
    ] @keyword

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
    (identifier) @variable
    (instance_variable) @variable
    (class_variable) @variable
    (global_variable) @variable

    ; Functions
    (method name: (identifier) @function)
    (call method: (identifier) @function)
    (method_call method: (identifier) @function)

    ; Types
    (constant) @type
    (class name: (constant) @type)
    (module name: (constant) @type)

    ; Keywords
    [
      "alias"
      "and"
      "begin"
      "break"
      "case"
      "class"
      "def"
      "defined?"
      "do"
      "else"
      "elsif"
      "end"
      "ensure"
      "for"
      "if"
      "in"
      "module"
      "next"
      "not"
      "or"
      "redo"
      "rescue"
      "retry"
      "return"
      "self"
      "super"
      "then"
      "unless"
      "until"
      "when"
      "while"
      "yield"
    ] @keyword

    ; Builtins
    [
      "true"
      "false"
      "nil"
    ] @constant.builtin

    ; Strings
    (string) @string
    (symbol) @string
    (heredoc_body) @string

    ; Numbers
    (integer) @number
    (float) @number

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
