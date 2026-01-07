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
import TreeSitterJava
import TreeSitterPHP
import TreeSitterSQL
// Query modules with highlight.scm files
import TreeSitterSwiftQueries
import TreeSitterPythonQueries
import TreeSitterJavaScriptQueries
import TreeSitterTypeScriptQueries
import TreeSitterRubyQueries
import TreeSitterGoQueries
import TreeSitterRustQueries
import TreeSitterCQueries
import TreeSitterCPPQueries
import TreeSitterHTMLQueries
import TreeSitterCSSQueries
import TreeSitterJSONQueries
import TreeSitterYAMLQueries
import TreeSitterMarkdownQueries
import TreeSitterBashQueries
import TreeSitterJavaQueries
import TreeSitterPHPQueries
import TreeSitterSQLQueries

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
        switch self {
        case .plainText:
            return nil
        case .swift:
            return TreeSitterLanguage(
                tree_sitter_swift(),
                highlightsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterSwiftQueries.Query.highlightsFileURL)
            )
        case .javascript:
            return TreeSitterLanguage(
                tree_sitter_javascript(),
                highlightsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterJavaScriptQueries.Query.highlightsFileURL),
                injectionsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterJavaScriptQueries.Query.injectionsFileURL)
            )
        case .typescript:
            return TreeSitterLanguage(
                tree_sitter_typescript(),
                highlightsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterTypeScriptQueries.Query.highlightsFileURL)
            )
        case .python:
            return TreeSitterLanguage(
                tree_sitter_python(),
                highlightsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterPythonQueries.Query.highlightsFileURL)
            )
        case .ruby:
            return TreeSitterLanguage(
                tree_sitter_ruby(),
                highlightsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterRubyQueries.Query.highlightsFileURL)
            )
        case .go:
            return TreeSitterLanguage(
                tree_sitter_go(),
                highlightsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterGoQueries.Query.highlightsFileURL)
            )
        case .rust:
            return TreeSitterLanguage(
                tree_sitter_rust(),
                highlightsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterRustQueries.Query.highlightsFileURL),
                injectionsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterRustQueries.Query.injectionsFileURL)
            )
        case .c:
            return TreeSitterLanguage(
                tree_sitter_c(),
                highlightsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterCQueries.Query.highlightsFileURL)
            )
        case .cpp:
            return TreeSitterLanguage(
                tree_sitter_cpp(),
                highlightsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterCPPQueries.Query.highlightsFileURL)
            )
        case .java:
            return TreeSitterLanguage(
                tree_sitter_java(),
                highlightsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterJavaQueries.Query.highlightsFileURL)
            )
        case .kotlin:
            // Use Java parser as fallback (similar syntax)
            return TreeSitterLanguage(
                tree_sitter_java(),
                highlightsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterJavaQueries.Query.highlightsFileURL)
            )
        case .html:
            return TreeSitterLanguage(
                tree_sitter_html(),
                highlightsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterHTMLQueries.Query.highlightsFileURL),
                injectionsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterHTMLQueries.Query.injectionsFileURL)
            )
        case .xml:
            // Use HTML parser as fallback (similar syntax)
            return TreeSitterLanguage(
                tree_sitter_html(),
                highlightsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterHTMLQueries.Query.highlightsFileURL),
                injectionsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterHTMLQueries.Query.injectionsFileURL)
            )
        case .css:
            return TreeSitterLanguage(
                tree_sitter_css(),
                highlightsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterCSSQueries.Query.highlightsFileURL)
            )
        case .json:
            return TreeSitterLanguage(
                tree_sitter_json(),
                highlightsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterJSONQueries.Query.highlightsFileURL)
            )
        case .yaml:
            return TreeSitterLanguage(
                tree_sitter_yaml(),
                highlightsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterYAMLQueries.Query.highlightsFileURL)
            )
        case .markdown:
            return TreeSitterLanguage(
                tree_sitter_markdown(),
                highlightsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterMarkdownQueries.Query.highlightsFileURL),
                injectionsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterMarkdownQueries.Query.injectionsFileURL)
            )
        case .shell:
            return TreeSitterLanguage(
                tree_sitter_bash(),
                highlightsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterBashQueries.Query.highlightsFileURL)
            )
        case .sql:
            return TreeSitterLanguage(
                tree_sitter_sql(),
                highlightsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterSQLQueries.Query.highlightsFileURL)
            )
        case .php:
            return TreeSitterLanguage(
                tree_sitter_php(),
                highlightsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterPHPQueries.Query.highlightsFileURL),
                injectionsQuery: TreeSitterLanguage.Query(contentsOf: TreeSitterPHPQueries.Query.injectionsFileURL)
            )
        case .conf:
            return nil
        }
    }
}
