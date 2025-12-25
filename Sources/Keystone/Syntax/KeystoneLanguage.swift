//
//  KeystoneLanguage.swift
//  Keystone
//

import Foundation

/// Represents a programming language for syntax highlighting.
public enum KeystoneLanguage: String, CaseIterable, Identifiable, Sendable {
    case plainText = "text"
    case swift
    case javascript
    case typescript
    case python
    case ruby
    case go
    case rust
    case c
    case cpp
    case java
    case kotlin
    case html
    case xml
    case css
    case json
    case yaml
    case markdown
    case shell
    case sql
    case php
    case conf

    public var id: String { rawValue }

    /// Display name for the language.
    public var displayName: String {
        switch self {
        case .plainText: return "Plain Text"
        case .swift: return "Swift"
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .python: return "Python"
        case .ruby: return "Ruby"
        case .go: return "Go"
        case .rust: return "Rust"
        case .c: return "C"
        case .cpp: return "C++"
        case .java: return "Java"
        case .kotlin: return "Kotlin"
        case .html: return "HTML"
        case .xml: return "XML"
        case .css: return "CSS"
        case .json: return "JSON"
        case .yaml: return "YAML"
        case .markdown: return "Markdown"
        case .shell: return "Shell"
        case .sql: return "SQL"
        case .php: return "PHP"
        case .conf: return "Config"
        }
    }

    /// Keywords for the language.
    public var keywords: [String] {
        switch self {
        case .swift:
            return ["func", "var", "let", "if", "else", "guard", "switch", "case", "default",
                    "for", "while", "repeat", "do", "break", "continue", "return", "throw",
                    "try", "catch", "throws", "rethrows", "import", "class", "struct", "enum",
                    "protocol", "extension", "init", "deinit", "self", "Self", "super", "nil",
                    "true", "false", "static", "private", "public", "internal", "fileprivate",
                    "open", "final", "override", "mutating", "nonmutating", "lazy", "weak",
                    "unowned", "as", "is", "in", "inout", "where", "async", "await", "actor",
                    "associatedtype", "typealias", "some", "any", "@State", "@Binding",
                    "@Published", "@ObservedObject", "@StateObject", "@Environment"]
        case .javascript, .typescript:
            return ["function", "var", "let", "const", "if", "else", "for", "while", "do",
                    "switch", "case", "default", "break", "continue", "return", "try", "catch",
                    "finally", "throw", "new", "delete", "typeof", "instanceof", "void", "this",
                    "class", "extends", "super", "import", "export", "from", "default", "async",
                    "await", "yield", "static", "get", "set", "true", "false", "null", "undefined"]
        case .python:
            return ["def", "class", "if", "elif", "else", "for", "while", "break", "continue",
                    "return", "try", "except", "finally", "raise", "with", "as", "import", "from",
                    "global", "nonlocal", "pass", "lambda", "yield", "True", "False", "None",
                    "and", "or", "not", "in", "is", "async", "await"]
        case .go:
            return ["break", "case", "chan", "const", "continue", "default", "defer", "else",
                    "fallthrough", "for", "func", "go", "goto", "if", "import", "interface",
                    "map", "package", "range", "return", "select", "struct", "switch", "type",
                    "var", "true", "false", "nil"]
        case .rust:
            return ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else",
                    "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop",
                    "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self",
                    "static", "struct", "super", "trait", "true", "type", "unsafe", "use",
                    "where", "while"]
        case .shell:
            return ["if", "then", "else", "elif", "fi", "case", "esac", "for", "while", "until",
                    "do", "done", "in", "function", "return", "local", "export", "readonly",
                    "declare", "typeset", "source", "alias", "true", "false"]
        case .sql:
            return ["SELECT", "FROM", "WHERE", "INSERT", "UPDATE", "DELETE", "CREATE", "DROP",
                    "ALTER", "TABLE", "INDEX", "VIEW", "DATABASE", "AND", "OR", "NOT", "NULL",
                    "IN", "LIKE", "BETWEEN", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "ON",
                    "GROUP", "BY", "ORDER", "HAVING", "LIMIT", "OFFSET", "UNION", "AS", "DISTINCT"]
        case .html, .xml:
            return []
        case .css:
            return ["important", "inherit", "initial", "unset"]
        case .conf:
            return ["true", "false", "yes", "no", "on", "off", "enabled", "disabled", "none", "auto"]
        default:
            return []
        }
    }

    /// Built-in types for the language.
    public var types: [String] {
        switch self {
        case .swift:
            return ["Int", "String", "Double", "Float", "Bool", "Character", "Array", "Dictionary",
                    "Set", "Optional", "Any", "AnyObject", "Void", "Never", "Error", "Result",
                    "Date", "Data", "URL", "UUID", "CGFloat", "CGPoint", "CGSize", "CGRect",
                    "View", "Text", "Button", "Image", "List", "NavigationStack", "VStack",
                    "HStack", "ZStack", "ForEach", "Binding", "State", "ObservableObject"]
        case .javascript, .typescript:
            return ["Array", "Object", "String", "Number", "Boolean", "Function", "Symbol",
                    "Map", "Set", "WeakMap", "WeakSet", "Promise", "Proxy", "Reflect", "JSON",
                    "Math", "Date", "RegExp", "Error", "console", "window", "document"]
        case .python:
            return ["int", "float", "str", "bool", "list", "dict", "set", "tuple", "type",
                    "object", "Exception", "range", "enumerate", "zip", "map", "filter", "len"]
        case .go:
            return ["int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16", "uint32",
                    "uint64", "float32", "float64", "complex64", "complex128", "byte", "rune",
                    "string", "bool", "error", "any"]
        case .rust:
            return ["i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16", "u32", "u64", "u128",
                    "usize", "f32", "f64", "bool", "char", "str", "String", "Vec", "Box", "Rc",
                    "Arc", "Option", "Result", "Ok", "Err", "Some", "None"]
        default:
            return []
        }
    }

    /// Detects the language from a filename.
    /// - Parameter filename: The filename to analyze.
    /// - Returns: The detected language.
    public static func detect(from filename: String) -> KeystoneLanguage {
        let ext = (filename as NSString).pathExtension.lowercased()

        switch ext {
        case "swift": return .swift
        case "js", "mjs", "cjs": return .javascript
        case "ts", "tsx": return .typescript
        case "py", "pyw": return .python
        case "rb": return .ruby
        case "go": return .go
        case "rs": return .rust
        case "c", "h": return .c
        case "cpp", "cc", "cxx", "hpp", "hxx": return .cpp
        case "java": return .java
        case "kt", "kts": return .kotlin
        case "html", "htm": return .html
        case "xml", "xsl", "xslt", "svg": return .xml
        case "css", "scss", "sass", "less": return .css
        case "json": return .json
        case "yaml", "yml": return .yaml
        case "md", "markdown": return .markdown
        case "sh", "bash", "zsh", "fish": return .shell
        case "sql": return .sql
        case "php": return .php
        case "conf", "ini", "cfg", "config": return .conf
        default:
            // Check for common config filenames
            let lowercased = filename.lowercased()
            if lowercased.hasSuffix(".conf") || lowercased.hasSuffix(".ini") ||
               lowercased == ".gitignore" || lowercased == ".env" ||
               lowercased.contains("rc") || lowercased.contains("config") {
                return .conf
            }
            return .plainText
        }
    }
}
