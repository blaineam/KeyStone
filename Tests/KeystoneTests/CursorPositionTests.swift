//
//  CursorPositionTests.swift
//  KeystoneTests
//

import XCTest
@testable import Keystone

final class CursorPositionTests: XCTestCase {

    // MARK: - From Offset Tests

    func testFromOffsetAtStart() {
        let text = "Hello\nWorld"
        let position = CursorPosition.from(offset: 0, in: text)
        XCTAssertEqual(position.line, 1)
        XCTAssertEqual(position.column, 1)
        XCTAssertEqual(position.offset, 0)
    }

    func testFromOffsetMiddleOfFirstLine() {
        let text = "Hello\nWorld"
        let position = CursorPosition.from(offset: 3, in: text)
        XCTAssertEqual(position.line, 1)
        XCTAssertEqual(position.column, 4)
        XCTAssertEqual(position.offset, 3)
    }

    func testFromOffsetAtNewline() {
        let text = "Hello\nWorld"
        let position = CursorPosition.from(offset: 5, in: text)
        XCTAssertEqual(position.line, 1)
        XCTAssertEqual(position.column, 6)
        XCTAssertEqual(position.offset, 5)
    }

    func testFromOffsetSecondLine() {
        let text = "Hello\nWorld"
        let position = CursorPosition.from(offset: 6, in: text)
        XCTAssertEqual(position.line, 2)
        XCTAssertEqual(position.column, 1)
        XCTAssertEqual(position.offset, 6)
    }

    func testFromOffsetEndOfSecondLine() {
        let text = "Hello\nWorld"
        let position = CursorPosition.from(offset: 11, in: text)
        XCTAssertEqual(position.line, 2)
        XCTAssertEqual(position.column, 6)
    }

    func testFromOffsetMultipleLines() {
        let text = "Line1\nLine2\nLine3\nLine4"
        let position = CursorPosition.from(offset: 18, in: text)
        XCTAssertEqual(position.line, 4)
        XCTAssertEqual(position.column, 1)
    }

    func testFromOffsetEmptyString() {
        let text = ""
        let position = CursorPosition.from(offset: 0, in: text)
        XCTAssertEqual(position.line, 1)
        XCTAssertEqual(position.column, 1)
    }

    // MARK: - Selection Length Tests

    func testSelectionLength() {
        let text = "Hello World"
        let position = CursorPosition.from(offset: 0, in: text, selectionLength: 5)
        XCTAssertEqual(position.selectionLength, 5)
    }

    // MARK: - Offset Calculation Tests

    func testOffsetFromLineColumn() {
        let text = "Hello\nWorld\nTest"

        // First line, first column
        XCTAssertEqual(CursorPosition.offset(line: 1, column: 1, in: text), 0)

        // First line, 4th column
        XCTAssertEqual(CursorPosition.offset(line: 1, column: 4, in: text), 3)

        // Second line, first column
        XCTAssertEqual(CursorPosition.offset(line: 2, column: 1, in: text), 6)

        // Third line, first column
        XCTAssertEqual(CursorPosition.offset(line: 3, column: 1, in: text), 12)
    }

    func testOffsetBeyondTextReturnsTextLength() {
        let text = "Hello"
        let offset = CursorPosition.offset(line: 10, column: 10, in: text)
        XCTAssertEqual(offset, 5)
    }

    // MARK: - Equatable Tests

    func testEquatable() {
        let pos1 = CursorPosition(line: 1, column: 5, selectionLength: 0, offset: 4)
        let pos2 = CursorPosition(line: 1, column: 5, selectionLength: 0, offset: 4)
        let pos3 = CursorPosition(line: 2, column: 1, selectionLength: 0, offset: 10)

        XCTAssertEqual(pos1, pos2)
        XCTAssertNotEqual(pos1, pos3)
    }

    // MARK: - Default Initialization

    func testDefaultInit() {
        let position = CursorPosition()
        XCTAssertEqual(position.line, 1)
        XCTAssertEqual(position.column, 1)
        XCTAssertEqual(position.selectionLength, 0)
        XCTAssertEqual(position.offset, 0)
    }
}
