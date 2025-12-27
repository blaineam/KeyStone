//
//  FindReplaceTests.swift
//  KeystoneTests
//

import XCTest
@testable import Keystone

@MainActor
final class FindReplaceTests: XCTestCase {

    // MARK: - Basic Search Tests

    func testSearchFindsMatches() {
        let manager = FindReplaceManager()
        manager.searchQuery = "hello"

        let text = "hello world, hello there"
        manager.search(in: text)

        XCTAssertEqual(manager.matches.count, 2)
    }

    func testSearchNoMatches() {
        let manager = FindReplaceManager()
        manager.searchQuery = "foo"

        let text = "hello world"
        manager.search(in: text)

        XCTAssertEqual(manager.matches.count, 0)
    }

    func testSearchEmptyQuery() {
        let manager = FindReplaceManager()
        manager.searchQuery = ""

        let text = "hello world"
        manager.search(in: text)

        XCTAssertEqual(manager.matches.count, 0)
    }

    // MARK: - Case Sensitive Search Tests

    func testSearchCaseInsensitiveByDefault() {
        let manager = FindReplaceManager()
        manager.searchQuery = "HELLO"

        let text = "hello world, Hello there"
        manager.search(in: text)

        XCTAssertEqual(manager.matches.count, 2)
    }

    func testSearchCaseSensitive() {
        let manager = FindReplaceManager()
        manager.searchQuery = "hello"
        manager.options.caseSensitive = true

        let text = "hello world, Hello there"
        manager.search(in: text)

        XCTAssertEqual(manager.matches.count, 1)
        XCTAssertEqual(manager.matches.first?.matchedText, "hello")
    }

    // MARK: - Whole Word Search Tests

    func testSearchWholeWord() {
        let manager = FindReplaceManager()
        manager.searchQuery = "hello"
        manager.options.wholeWord = true

        let text = "hello world, helloworld"
        manager.search(in: text)

        XCTAssertEqual(manager.matches.count, 1)
    }

    func testSearchWholeWordMultipleMatches() {
        let manager = FindReplaceManager()
        manager.searchQuery = "hello"
        manager.options.wholeWord = true

        let text = "hello world, hello there"
        manager.search(in: text)

        XCTAssertEqual(manager.matches.count, 2)
    }

    // MARK: - Regex Search Tests

    func testSearchWithRegex() {
        let manager = FindReplaceManager()
        manager.searchQuery = "\\d+"
        manager.options.useRegex = true

        let text = "item1, item22, item333"
        manager.search(in: text)

        XCTAssertEqual(manager.matches.count, 3)
        XCTAssertEqual(manager.matches[0].matchedText, "1")
        XCTAssertEqual(manager.matches[1].matchedText, "22")
        XCTAssertEqual(manager.matches[2].matchedText, "333")
    }

    func testSearchInvalidRegex() {
        let manager = FindReplaceManager()
        manager.searchQuery = "[invalid"
        manager.options.useRegex = true

        let text = "hello world"
        manager.search(in: text)

        XCTAssertEqual(manager.matches.count, 0)
    }

    // MARK: - Navigation Tests

    func testFindNextWrapsAround() {
        let manager = FindReplaceManager()
        manager.searchQuery = "a"

        let text = "a b a c a"
        manager.search(in: text)

        XCTAssertEqual(manager.matches.count, 3)
        XCTAssertEqual(manager.currentMatchIndex, 0)

        manager.findNext()
        XCTAssertEqual(manager.currentMatchIndex, 1)

        manager.findNext()
        XCTAssertEqual(manager.currentMatchIndex, 2)

        manager.findNext()
        XCTAssertEqual(manager.currentMatchIndex, 0) // Wraps around
    }

    func testFindPreviousWrapsAround() {
        let manager = FindReplaceManager()
        manager.searchQuery = "a"

        let text = "a b a c a"
        manager.search(in: text)

        XCTAssertEqual(manager.currentMatchIndex, 0)

        manager.findPrevious()
        XCTAssertEqual(manager.currentMatchIndex, 2) // Wraps around to last

        manager.findPrevious()
        XCTAssertEqual(manager.currentMatchIndex, 1)
    }

    func testFindNextNoWrapAround() {
        let manager = FindReplaceManager()
        manager.searchQuery = "a"
        manager.options.wrapAround = false

        let text = "a b a"
        manager.search(in: text)

        XCTAssertEqual(manager.currentMatchIndex, 0)

        manager.findNext()
        XCTAssertEqual(manager.currentMatchIndex, 1)

        manager.findNext()
        XCTAssertEqual(manager.currentMatchIndex, 1) // Stays at last
    }

    // MARK: - Replace Tests

    func testReplaceCurrent() {
        let manager = FindReplaceManager()
        manager.searchQuery = "hello"
        manager.replaceText = "hi"

        let text = "hello world"
        manager.search(in: text)

        let result = manager.replaceCurrent(in: text)

        XCTAssertEqual(result, "hi world")
    }

    func testReplaceAll() {
        let manager = FindReplaceManager()
        manager.searchQuery = "a"
        manager.replaceText = "X"

        let text = "a b a c a"
        manager.search(in: text)

        let result = manager.replaceAll(in: text)

        XCTAssertEqual(result, "X b X c X")
    }

    func testReplaceAllNoMatches() {
        let manager = FindReplaceManager()
        manager.searchQuery = "foo"
        manager.replaceText = "bar"

        let text = "hello world"
        manager.search(in: text)

        let result = manager.replaceAll(in: text)

        XCTAssertEqual(result, "hello world")
    }

    // MARK: - Status Tests

    func testStatusTextEmpty() {
        let manager = FindReplaceManager()
        manager.searchQuery = ""

        XCTAssertEqual(manager.statusText, "")
    }

    func testStatusTextNoResults() {
        let manager = FindReplaceManager()
        manager.searchQuery = "foo"

        let text = "hello world"
        manager.search(in: text)

        XCTAssertEqual(manager.statusText, "No results")
    }

    func testStatusTextWithMatches() {
        let manager = FindReplaceManager()
        manager.searchQuery = "a"

        let text = "a b a c a"
        manager.search(in: text)

        XCTAssertEqual(manager.statusText, "1 of 3")

        manager.findNext()
        XCTAssertEqual(manager.statusText, "2 of 3")
    }

    // MARK: - Visibility Tests

    func testShowAndHide() {
        let manager = FindReplaceManager()

        XCTAssertFalse(manager.isVisible)

        manager.show()
        XCTAssertTrue(manager.isVisible)

        manager.hide()
        XCTAssertFalse(manager.isVisible)
    }

    func testToggle() {
        let manager = FindReplaceManager()

        XCTAssertFalse(manager.isVisible)

        manager.toggle()
        XCTAssertTrue(manager.isVisible)

        manager.toggle()
        XCTAssertFalse(manager.isVisible)
    }

    func testHideAlsoHidesReplace() {
        let manager = FindReplaceManager()
        manager.show()
        manager.showReplace = true

        XCTAssertTrue(manager.showReplace)

        manager.hide()
        XCTAssertFalse(manager.showReplace)
    }

    // MARK: - Clear Tests

    func testClear() {
        let manager = FindReplaceManager()
        manager.searchQuery = "hello"
        manager.replaceText = "world"

        let text = "hello there"
        manager.search(in: text)

        XCTAssertEqual(manager.matches.count, 1)

        manager.clear()

        XCTAssertEqual(manager.searchQuery, "")
        XCTAssertEqual(manager.replaceText, "")
        XCTAssertEqual(manager.matches.count, 0)
        XCTAssertEqual(manager.currentMatchIndex, 0)
    }

    // MARK: - Match Properties Tests

    func testMatchLineAndColumn() {
        let manager = FindReplaceManager()
        manager.searchQuery = "world"

        let text = "hello\nworld"
        manager.search(in: text)

        XCTAssertEqual(manager.matches.count, 1)
        XCTAssertEqual(manager.matches.first?.lineNumber, 2)
        XCTAssertEqual(manager.matches.first?.column, 1)
    }

    func testCurrentMatch() {
        let manager = FindReplaceManager()
        manager.searchQuery = "a"

        let text = "a b a"
        manager.search(in: text)

        XCTAssertNotNil(manager.currentMatch)
        XCTAssertEqual(manager.currentMatch?.matchedText, "a")

        manager.findNext()
        XCTAssertEqual(manager.currentMatch?.matchedText, "a")
    }

    func testCurrentMatchNilWhenEmpty() {
        let manager = FindReplaceManager()
        manager.searchQuery = "foo"

        let text = "hello world"
        manager.search(in: text)

        XCTAssertNil(manager.currentMatch)
    }
}
