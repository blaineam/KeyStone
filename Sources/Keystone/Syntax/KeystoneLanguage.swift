//
//  KeystoneLanguage.swift
//  Keystone
//

import Foundation
import TreeSitterSwift
import TreeSitterPython
import TreeSitterJavaScript
import TreeSitterTypeScript
import TreeSitterRuby
import TreeSitterGo
import TreeSitterRust
import TreeSitterC
import TreeSitterCPP
import TreeSitterHTML
import TreeSitterCSS
import TreeSitterJSON
import TreeSitterYAML
import TreeSitterMarkdown
import TreeSitterBash

/// Represents comment syntax for a programming language.
public struct CommentSyntax: Sendable {
    /// The line comment prefix (e.g., "//", "#", "--").
    public let lineComment: String?
    /// The block comment delimiters (start, end).
    public let blockComment: (start: String, end: String)?

    public init(lineComment: String? = nil, blockComment: (String, String)? = nil) {
        self.lineComment = lineComment
        if let block = blockComment {
            self.blockComment = (start: block.0, end: block.1)
        } else {
            self.blockComment = nil
        }
    }
}

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

    /// Comment syntax for the language.
    public var commentSyntax: CommentSyntax? {
        switch self {
        case .plainText:
            return nil
        case .swift, .kotlin, .java, .c, .cpp, .go, .rust, .javascript, .typescript, .php:
            return CommentSyntax(lineComment: "//", blockComment: ("/*", "*/"))
        case .python, .ruby, .shell, .yaml, .conf:
            return CommentSyntax(lineComment: "#")
        case .html, .xml:
            return CommentSyntax(blockComment: ("<!--", "-->"))
        case .css:
            return CommentSyntax(blockComment: ("/*", "*/"))
        case .sql:
            return CommentSyntax(lineComment: "--", blockComment: ("/*", "*/"))
        case .markdown:
            return CommentSyntax(blockComment: ("<!--", "-->"))
        case .json:
            return nil
        }
    }

    /// Whether this language supports line commenting.
    public var supportsComments: Bool {
        commentSyntax != nil
    }

    /// Detects the language from a filename.
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
            let lowercased = filename.lowercased()
            if lowercased.hasSuffix(".conf") || lowercased.hasSuffix(".ini") ||
               lowercased == ".gitignore" || lowercased == ".env" ||
               lowercased.contains("rc") || lowercased.contains("config") {
                return .conf
            }
            return .plainText
        }
    }

    /// Returns the corresponding TreeSitterLanguage for syntax highlighting.
    public var treeSitterLanguage: TreeSitterLanguage? {
        guard let highlightQuery = highlightQuery else { return nil }
        let query = TreeSitterLanguage.Query(string: highlightQuery)
        let injectionsQuery = injectionQuery.map { TreeSitterLanguage.Query(string: $0) }

        switch self {
        case .plainText: return nil
        case .swift: return TreeSitterLanguage(tree_sitter_swift(), highlightsQuery: query)
        case .javascript: return TreeSitterLanguage(tree_sitter_javascript(), highlightsQuery: query)
        case .typescript: return TreeSitterLanguage(tree_sitter_typescript(), highlightsQuery: query)
        case .python: return TreeSitterLanguage(tree_sitter_python(), highlightsQuery: query)
        case .ruby: return TreeSitterLanguage(tree_sitter_ruby(), highlightsQuery: query)
        case .go: return TreeSitterLanguage(tree_sitter_go(), highlightsQuery: query)
        case .rust: return TreeSitterLanguage(tree_sitter_rust(), highlightsQuery: query)
        case .c: return TreeSitterLanguage(tree_sitter_c(), highlightsQuery: query)
        case .cpp: return TreeSitterLanguage(tree_sitter_cpp(), highlightsQuery: query)
        case .java: return nil // Not included in TreeSitterLanguages
        case .kotlin: return nil // Not included in TreeSitterLanguages
        case .html: return TreeSitterLanguage(tree_sitter_html(), highlightsQuery: query, injectionsQuery: injectionsQuery)
        case .xml: return nil // Not included
        case .css: return TreeSitterLanguage(tree_sitter_css(), highlightsQuery: query)
        case .json: return TreeSitterLanguage(tree_sitter_json(), highlightsQuery: query)
        case .yaml: return TreeSitterLanguage(tree_sitter_yaml(), highlightsQuery: query)
        case .markdown: return TreeSitterLanguage(tree_sitter_markdown(), highlightsQuery: query, injectionsQuery: injectionsQuery)
        case .shell: return TreeSitterLanguage(tree_sitter_bash(), highlightsQuery: query)
        case .sql: return nil // Not included
        case .php: return nil // Not included
        case .conf: return nil
        }
    }

    /// Returns the injection query string for this language (for embedded languages).
    private var injectionQuery: String? {
        switch self {
        case .html: return HighlightQueries.htmlInjections
        case .markdown: return HighlightQueries.markdownInjections
        default: return nil
        }
    }

    /// Returns the highlight query string for this language.
    private var highlightQuery: String? {
        switch self {
        case .plainText: return nil
        case .swift: return HighlightQueries.swift
        case .javascript: return HighlightQueries.javascript
        case .typescript: return HighlightQueries.typescript
        case .python: return HighlightQueries.python
        case .ruby: return HighlightQueries.ruby
        case .go: return HighlightQueries.go
        case .rust: return HighlightQueries.rust
        case .c: return HighlightQueries.c
        case .cpp: return HighlightQueries.cpp
        case .java: return nil
        case .kotlin: return nil
        case .html: return HighlightQueries.html
        case .xml: return nil
        case .css: return HighlightQueries.css
        case .json: return HighlightQueries.json
        case .yaml: return HighlightQueries.yaml
        case .markdown: return HighlightQueries.markdown
        case .shell: return HighlightQueries.bash
        case .sql: return nil
        case .php: return nil
        case .conf: return nil
        }
    }
}
