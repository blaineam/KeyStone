//
//  KeystoneConfigurationTests.swift
//  KeystoneTests
//

import XCTest
@testable import Keystone

@MainActor
final class KeystoneConfigurationTests: XCTestCase {

    // MARK: - Default Values Tests

    func testDefaultValues() {
        let config = KeystoneConfiguration()

        XCTAssertEqual(config.fontSize, 14.0)
        XCTAssertTrue(config.showLineNumbers)
        XCTAssertTrue(config.highlightCurrentLine)
        XCTAssertFalse(config.showInvisibleCharacters)
        XCTAssertTrue(config.lineWrapping)
        XCTAssertTrue(config.autoInsertPairs)
        XCTAssertTrue(config.highlightMatchingBrackets)
        XCTAssertTrue(config.tabKeyInsertsTab)
        XCTAssertEqual(config.indentation.type, .spaces)
        XCTAssertEqual(config.indentation.width, 4)
        XCTAssertEqual(config.lineEnding, .lf)
    }

    // MARK: - Detect Settings Tests

    func testDetectSettingsFromText() {
        let config = KeystoneConfiguration()
        // Use LF line endings and tab indentation
        let text = "line1\nline2\n\tindented line"

        config.detectSettings(from: text)

        XCTAssertEqual(config.lineEnding, .lf)
        XCTAssertEqual(config.indentation.type, .tabs)
    }

    func testDetectSettingsSpaces() {
        let config = KeystoneConfiguration()
        let text = "line1\nline2\n    indented"

        config.detectSettings(from: text)

        XCTAssertEqual(config.lineEnding, .lf)
        XCTAssertEqual(config.indentation.type, .spaces)
    }

    // MARK: - Character Pair Tests

    func testShouldAutoInsertPairOpenParen() {
        let config = KeystoneConfiguration()
        config.autoInsertPairs = true

        let result = config.shouldAutoInsertPair(for: Character("("), in: "text", at: 4)
        XCTAssertEqual(result, Character(")"))
    }

    func testShouldAutoInsertPairOpenBrace() {
        let config = KeystoneConfiguration()
        config.autoInsertPairs = true

        let result = config.shouldAutoInsertPair(for: Character("{"), in: "text", at: 4)
        XCTAssertEqual(result, Character("}"))
    }

    func testShouldAutoInsertPairOpenBracket() {
        let config = KeystoneConfiguration()
        config.autoInsertPairs = true

        let result = config.shouldAutoInsertPair(for: Character("["), in: "text", at: 4)
        XCTAssertEqual(result, Character("]"))
    }

    func testShouldAutoInsertPairDoubleQuote() {
        let config = KeystoneConfiguration()
        config.autoInsertPairs = true

        let result = config.shouldAutoInsertPair(for: Character("\""), in: "text", at: 4)
        XCTAssertEqual(result, Character("\""))
    }

    func testShouldAutoInsertPairSingleQuote() {
        let config = KeystoneConfiguration()
        config.autoInsertPairs = true

        let result = config.shouldAutoInsertPair(for: Character("'"), in: "text", at: 4)
        XCTAssertEqual(result, Character("'"))
    }

    func testShouldAutoInsertPairBacktick() {
        let config = KeystoneConfiguration()
        config.autoInsertPairs = true

        let result = config.shouldAutoInsertPair(for: Character("`"), in: "text", at: 4)
        XCTAssertEqual(result, Character("`"))
    }

    func testShouldAutoInsertPairDisabled() {
        let config = KeystoneConfiguration()
        config.autoInsertPairs = false

        let result = config.shouldAutoInsertPair(for: Character("("), in: "text", at: 4)
        XCTAssertNil(result)
    }

    func testShouldAutoInsertPairRegularCharacter() {
        let config = KeystoneConfiguration()
        config.autoInsertPairs = true

        let result = config.shouldAutoInsertPair(for: Character("a"), in: "text", at: 4)
        XCTAssertNil(result)
    }

    // MARK: - Skip Closing Pair Tests

    func testShouldSkipClosingPair() {
        let config = KeystoneConfiguration()
        config.autoInsertPairs = true

        // Cursor is at position 4, next character is )
        let text = "test)"
        let result = config.shouldSkipClosingPair(for: Character(")"), in: text, at: 4)
        XCTAssertTrue(result)
    }

    func testShouldNotSkipClosingPairDifferentChar() {
        let config = KeystoneConfiguration()
        config.autoInsertPairs = true

        let text = "test)"
        let result = config.shouldSkipClosingPair(for: Character("]"), in: text, at: 4)
        XCTAssertFalse(result)
    }

    func testShouldNotSkipWhenDisabled() {
        let config = KeystoneConfiguration()
        config.autoInsertPairs = false

        let text = "test)"
        let result = config.shouldSkipClosingPair(for: Character(")"), in: text, at: 4)
        XCTAssertFalse(result)
    }

    // MARK: - Delete Pair Tests

    func testShouldDeletePair() {
        let config = KeystoneConfiguration()
        config.autoInsertPairs = true

        // Text is "()" and cursor is between them (position 1)
        let text = "()"
        let result = config.shouldDeletePair(in: text, at: 1)
        XCTAssertTrue(result)
    }

    func testShouldDeletePairBraces() {
        let config = KeystoneConfiguration()
        config.autoInsertPairs = true

        let text = "{}"
        let result = config.shouldDeletePair(in: text, at: 1)
        XCTAssertTrue(result)
    }

    func testShouldDeletePairBrackets() {
        let config = KeystoneConfiguration()
        config.autoInsertPairs = true

        let text = "[]"
        let result = config.shouldDeletePair(in: text, at: 1)
        XCTAssertTrue(result)
    }

    func testShouldDeletePairQuotes() {
        let config = KeystoneConfiguration()
        config.autoInsertPairs = true

        let text = "\"\""
        let result = config.shouldDeletePair(in: text, at: 1)
        XCTAssertTrue(result)
    }

    func testShouldNotDeleteNonPair() {
        let config = KeystoneConfiguration()
        config.autoInsertPairs = true

        let text = "ab"
        let result = config.shouldDeletePair(in: text, at: 1)
        XCTAssertFalse(result)
    }

    func testShouldNotDeleteWhenDisabled() {
        let config = KeystoneConfiguration()
        config.autoInsertPairs = false

        let text = "()"
        let result = config.shouldDeletePair(in: text, at: 1)
        XCTAssertFalse(result)
    }
}
