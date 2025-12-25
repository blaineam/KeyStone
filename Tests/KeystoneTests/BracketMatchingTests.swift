//
//  BracketMatchingTests.swift
//  KeystoneTests
//

import XCTest
@testable import Keystone

final class BracketMatchingTests: XCTestCase {

    // MARK: - Find Match Tests

    func testFindMatchOpenParen() {
        let text = "func test() { }"
        let match = BracketMatcher.findMatch(in: text, at: 9) // Position of (
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.bracketType, Character("("))
        XCTAssertEqual(match?.openPosition, 9)
        XCTAssertEqual(match?.closePosition, 10)
    }

    func testFindMatchCloseParen() {
        let text = "func test() { }"
        let match = BracketMatcher.findMatch(in: text, at: 10) // Position of )
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.bracketType, Character("("))
        XCTAssertEqual(match?.openPosition, 9)
        XCTAssertEqual(match?.closePosition, 10)
    }

    func testFindMatchOpenBrace() {
        let text = "{ code }"
        let match = BracketMatcher.findMatch(in: text, at: 0)
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.bracketType, Character("{"))
        XCTAssertEqual(match?.openPosition, 0)
        XCTAssertEqual(match?.closePosition, 7)
    }

    func testFindMatchOpenBracket() {
        let text = "[1, 2, 3]"
        let match = BracketMatcher.findMatch(in: text, at: 0)
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.bracketType, Character("["))
        XCTAssertEqual(match?.openPosition, 0)
        XCTAssertEqual(match?.closePosition, 8)
    }

    func testFindMatchNestedBraces() {
        let text = "{ { inner } }"
        // Position of outer opening brace
        let outerMatch = BracketMatcher.findMatch(in: text, at: 0)
        XCTAssertNotNil(outerMatch)
        XCTAssertEqual(outerMatch?.openPosition, 0)
        XCTAssertEqual(outerMatch?.closePosition, 12)

        // Position of inner opening brace
        let innerMatch = BracketMatcher.findMatch(in: text, at: 2)
        XCTAssertNotNil(innerMatch)
        XCTAssertEqual(innerMatch?.openPosition, 2)
        XCTAssertEqual(innerMatch?.closePosition, 10)
    }

    func testFindMatchNoMatch() {
        let text = "no brackets here"
        let match = BracketMatcher.findMatch(in: text, at: 0)
        XCTAssertNil(match)
    }

    func testFindMatchUnbalanced() {
        let text = "{ unbalanced"
        let match = BracketMatcher.findMatch(in: text, at: 0)
        XCTAssertNil(match)
    }

    func testFindMatchPositionOutOfBounds() {
        let text = "{ }"
        let match = BracketMatcher.findMatch(in: text, at: 100)
        XCTAssertNil(match)
    }

    func testFindMatchEmptyString() {
        let text = ""
        let match = BracketMatcher.findMatch(in: text, at: 0)
        XCTAssertNil(match)
    }

    // MARK: - Find Enclosing Pair Tests

    func testFindEnclosingPair() {
        let text = "{ outer { inner } outer }"
        // Position inside inner braces
        let match = BracketMatcher.findEnclosingPair(in: text, at: 10)
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.bracketType, Character("{"))
        XCTAssertEqual(match?.openPosition, 8)
        XCTAssertEqual(match?.closePosition, 16)
    }

    func testFindEnclosingPairOuterBraces() {
        let text = "{ outer { inner } outer }"
        // Position between inner and outer braces (after inner close)
        let match = BracketMatcher.findEnclosingPair(in: text, at: 20)
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.openPosition, 0)
        XCTAssertEqual(match?.closePosition, 24)
    }

    func testFindEnclosingPairNoPair() {
        let text = "no brackets"
        let match = BracketMatcher.findEnclosingPair(in: text, at: 5)
        XCTAssertNil(match)
    }

    func testFindEnclosingPairMixedBrackets() {
        let text = "array[index].call()"
        // Position inside array brackets
        let match = BracketMatcher.findEnclosingPair(in: text, at: 6)
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.bracketType, Character("["))
    }

    // MARK: - Bracket Pairs Tests

    func testBracketPairs() {
        let pairs = BracketMatcher.bracketPairs
        XCTAssertEqual(pairs.count, 3)

        XCTAssertTrue(pairs.contains(where: { $0.open == "(" && $0.close == ")" }))
        XCTAssertTrue(pairs.contains(where: { $0.open == "[" && $0.close == "]" }))
        XCTAssertTrue(pairs.contains(where: { $0.open == "{" && $0.close == "}" }))
    }
}
