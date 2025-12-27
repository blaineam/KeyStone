//
//  TreeSitterHighlighterTests.swift
//  KeystoneTests
//
//  Tests for TreeSitter-based syntax highlighting.
//

import XCTest
@testable import Keystone

final class TreeSitterHighlighterTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitWithSupportedLanguage() {
        let highlighter = TreeSitterHighlighter(
            language: .swift,
            theme: KeystoneTheme.default
        )
        XCTAssertTrue(highlighter.isTreeSitterAvailable)
    }

    func testInitWithUnsupportedLanguage() {
        let highlighter = TreeSitterHighlighter(
            language: .plainText,
            theme: KeystoneTheme.default
        )
        XCTAssertFalse(highlighter.isTreeSitterAvailable)
    }

    // MARK: - Swift Parsing Tests

    func testParseSwiftKeywords() {
        let highlighter = TreeSitterHighlighter(
            language: .swift,
            theme: KeystoneTheme.default
        )
        let code = "func hello() { }"
        let ranges = highlighter.parse(code)

        // Should find at least the func keyword
        let keywords = ranges.filter { $0.tokenType == .keyword }
        XCTAssertFalse(keywords.isEmpty, "Should find keyword tokens")
    }

    func testParseSwiftString() {
        let highlighter = TreeSitterHighlighter(
            language: .swift,
            theme: KeystoneTheme.default
        )
        let code = "let greeting = \"Hello, World!\""
        let ranges = highlighter.parse(code)

        let strings = ranges.filter { $0.tokenType == .string }
        XCTAssertFalse(strings.isEmpty, "Should find string tokens")
    }

    func testParseSwiftComment() {
        let highlighter = TreeSitterHighlighter(
            language: .swift,
            theme: KeystoneTheme.default
        )
        let code = "// This is a comment\nlet x = 1"
        let ranges = highlighter.parse(code)

        let comments = ranges.filter { $0.tokenType == .comment }
        XCTAssertFalse(comments.isEmpty, "Should find comment tokens")
    }

    func testParseSwiftNumber() {
        let highlighter = TreeSitterHighlighter(
            language: .swift,
            theme: KeystoneTheme.default
        )
        let code = "let count = 42"
        let ranges = highlighter.parse(code)

        let numbers = ranges.filter { $0.tokenType == .number }
        XCTAssertFalse(numbers.isEmpty, "Should find number tokens")
    }

    // MARK: - Python Parsing Tests

    func testParsePython() {
        let highlighter = TreeSitterHighlighter(
            language: .python,
            theme: KeystoneTheme.default
        )
        let code = "def greet():\n    print(\"Hello\")"
        let ranges = highlighter.parse(code)

        XCTAssertFalse(ranges.isEmpty, "Should parse Python code")
    }

    // MARK: - JavaScript Parsing Tests

    func testParseJavaScript() {
        let highlighter = TreeSitterHighlighter(
            language: .javascript,
            theme: KeystoneTheme.default
        )
        let code = "function hello() { return 'world'; }"
        let ranges = highlighter.parse(code)

        XCTAssertFalse(ranges.isEmpty, "Should parse JavaScript code")
    }

    // MARK: - JSON Parsing Tests

    func testParseJSON() {
        let highlighter = TreeSitterHighlighter(
            language: .json,
            theme: KeystoneTheme.default
        )
        let code = "{\"name\": \"value\", \"count\": 42, \"active\": true}"
        let ranges = highlighter.parse(code)

        let strings = ranges.filter { $0.tokenType == .string }
        let numbers = ranges.filter { $0.tokenType == .number }
        let keywords = ranges.filter { $0.tokenType == .keyword }

        XCTAssertFalse(strings.isEmpty, "Should find string tokens in JSON")
        XCTAssertFalse(numbers.isEmpty, "Should find number tokens in JSON")
        XCTAssertFalse(keywords.isEmpty, "Should find keyword tokens (true/false/null) in JSON")
    }

    // MARK: - HTML Parsing Tests

    func testParseHTML() {
        let highlighter = TreeSitterHighlighter(
            language: .html,
            theme: KeystoneTheme.default
        )
        let code = "<div class=\"container\">Hello</div>"
        let ranges = highlighter.parse(code)

        let tags = ranges.filter { $0.tokenType == .tag }
        let attributes = ranges.filter { $0.tokenType == .attribute }

        XCTAssertFalse(tags.isEmpty, "Should find tag tokens in HTML")
        XCTAssertFalse(attributes.isEmpty, "Should find attribute tokens in HTML")
    }

    // MARK: - CSS Parsing Tests

    func testParseCSS() {
        let highlighter = TreeSitterHighlighter(
            language: .css,
            theme: KeystoneTheme.default
        )
        let code = ".container { color: red; }"
        let ranges = highlighter.parse(code)

        XCTAssertFalse(ranges.isEmpty, "Should parse CSS code")
    }

    // MARK: - Unsupported Language Tests

    func testParseUnsupportedLanguage() {
        let highlighter = TreeSitterHighlighter(
            language: .plainText,
            theme: KeystoneTheme.default
        )
        let code = "This is plain text"
        let ranges = highlighter.parse(code)

        XCTAssertTrue(ranges.isEmpty, "Plain text should return no highlight ranges")
    }

    // MARK: - Empty Input Tests

    func testParseEmptyString() {
        let highlighter = TreeSitterHighlighter(
            language: .swift,
            theme: KeystoneTheme.default
        )
        let ranges = highlighter.parse("")

        XCTAssertTrue(ranges.isEmpty, "Empty string should return no ranges")
    }

    // MARK: - HighlightRange Tests

    func testHighlightRangeEquality() {
        let range1 = HighlightRange(start: 0, end: 10, tokenType: .keyword)
        let range2 = HighlightRange(start: 0, end: 10, tokenType: .keyword)
        let range3 = HighlightRange(start: 0, end: 10, tokenType: .string)

        XCTAssertEqual(range1, range2)
        XCTAssertNotEqual(range1, range3)
    }

    // MARK: - TokenType Tests

    func testTokenTypeRawValues() {
        XCTAssertEqual(TokenType.keyword.rawValue, "keyword")
        XCTAssertEqual(TokenType.type.rawValue, "type")
        XCTAssertEqual(TokenType.string.rawValue, "string")
        XCTAssertEqual(TokenType.comment.rawValue, "comment")
        XCTAssertEqual(TokenType.number.rawValue, "number")
        XCTAssertEqual(TokenType.function.rawValue, "function")
        XCTAssertEqual(TokenType.tag.rawValue, "tag")
        XCTAssertEqual(TokenType.attribute.rawValue, "attribute")
        XCTAssertEqual(TokenType.operator.rawValue, "operator")
        XCTAssertEqual(TokenType.punctuation.rawValue, "punctuation")
    }

    // MARK: - TextEdit Tests

    func testTextEditInit() {
        let edit = TextEdit(
            startByte: 0,
            oldEndByte: 5,
            newEndByte: 10,
            startRow: 0,
            startColumn: 0,
            oldEndRow: 0,
            oldEndColumn: 5,
            newEndRow: 0,
            newEndColumn: 10
        )

        XCTAssertEqual(edit.startByte, 0)
        XCTAssertEqual(edit.oldEndByte, 5)
        XCTAssertEqual(edit.newEndByte, 10)
        XCTAssertEqual(edit.startRow, 0)
        XCTAssertEqual(edit.startColumn, 0)
    }

    // MARK: - Incremental Parsing Tests

    func testIncrementalUpdate() {
        let highlighter = TreeSitterHighlighter(
            language: .swift,
            theme: KeystoneTheme.default
        )

        // Initial parse
        let initialCode = "let x = 1"
        let initialRanges = highlighter.parse(initialCode)
        XCTAssertFalse(initialRanges.isEmpty)

        // Update with edit
        let newCode = "let x = 42"
        let edit = TextEdit(
            startByte: 8,
            oldEndByte: 9,
            newEndByte: 10,
            startRow: 0,
            startColumn: 8,
            oldEndRow: 0,
            oldEndColumn: 9,
            newEndRow: 0,
            newEndColumn: 10
        )

        let updatedRanges = highlighter.update(newCode, with: edit)
        XCTAssertFalse(updatedRanges.isEmpty)
    }

    // MARK: - Color Mapping Tests

    func testColorForTokenType() {
        let theme = KeystoneTheme.default
        let highlighter = TreeSitterHighlighter(
            language: .swift,
            theme: theme
        )

        // Just verify these don't crash - actual color values depend on theme
        _ = highlighter.color(for: .keyword)
        _ = highlighter.color(for: .type)
        _ = highlighter.color(for: .string)
        _ = highlighter.color(for: .comment)
        _ = highlighter.color(for: .number)
        _ = highlighter.color(for: .function)
        _ = highlighter.color(for: .tag)
        _ = highlighter.color(for: .attribute)
        _ = highlighter.color(for: .operator)
        _ = highlighter.color(for: .punctuation)
    }

    // MARK: - Multiple Language Support Tests

    func testAllSupportedLanguages() {
        let supportedLanguages: [KeystoneLanguage] = [
            .swift, .python, .javascript, .typescript, .json,
            .html, .css, .c, .cpp, .go, .rust, .ruby, .shell,
            .yaml, .markdown
        ]

        let theme = KeystoneTheme.default

        for language in supportedLanguages {
            let highlighter = TreeSitterHighlighter(
                language: language,
                theme: theme
            )
            XCTAssertTrue(
                highlighter.isTreeSitterAvailable,
                "TreeSitter should be available for \(language)"
            )
        }
    }

    func testUnsupportedLanguages() {
        let unsupportedLanguages: [KeystoneLanguage] = [
            .plainText, .xml, .sql, .php, .java
        ]

        let theme = KeystoneTheme.default

        for language in unsupportedLanguages {
            let highlighter = TreeSitterHighlighter(
                language: language,
                theme: theme
            )
            XCTAssertFalse(
                highlighter.isTreeSitterAvailable,
                "TreeSitter should not be available for \(language)"
            )
        }
    }
}
