//
//  LineEndingTests.swift
//  KeystoneTests
//

import XCTest
@testable import Keystone

final class LineEndingTests: XCTestCase {

    // MARK: - Case Tests

    func testAllCases() {
        XCTAssertEqual(LineEnding.allCases.count, 3)
        XCTAssertTrue(LineEnding.allCases.contains(.lf))
        XCTAssertTrue(LineEnding.allCases.contains(.crlf))
        XCTAssertTrue(LineEnding.allCases.contains(.cr))
    }

    // MARK: - Symbol Tests

    func testLFSymbol() {
        XCTAssertEqual(LineEnding.lf.symbol, "\n")
    }

    func testCRLFSymbol() {
        XCTAssertEqual(LineEnding.crlf.symbol, "\r\n")
    }

    func testCRSymbol() {
        XCTAssertEqual(LineEnding.cr.symbol, "\r")
    }

    // MARK: - Init from Symbol Tests

    func testInitFromLFSymbol() {
        let ending = LineEnding(symbol: "\n")
        XCTAssertEqual(ending, .lf)
    }

    func testInitFromCRLFSymbol() {
        let ending = LineEnding(symbol: "\r\n")
        XCTAssertEqual(ending, .crlf)
    }

    func testInitFromCRSymbol() {
        let ending = LineEnding(symbol: "\r")
        XCTAssertEqual(ending, .cr)
    }

    func testInitFromInvalidSymbol() {
        let ending = LineEnding(symbol: "x")
        XCTAssertNil(ending)
    }

    func testInitFromEmptySymbol() {
        let ending = LineEnding(symbol: "")
        XCTAssertNil(ending)
    }

    // MARK: - Raw Value Tests

    func testRawValues() {
        XCTAssertEqual(LineEnding.lf.rawValue, "lf")
        XCTAssertEqual(LineEnding.crlf.rawValue, "crlf")
        XCTAssertEqual(LineEnding.cr.rawValue, "cr")
    }

    func testInitFromRawValue() {
        XCTAssertEqual(LineEnding(rawValue: "lf"), .lf)
        XCTAssertEqual(LineEnding(rawValue: "crlf"), .crlf)
        XCTAssertEqual(LineEnding(rawValue: "cr"), .cr)
        XCTAssertNil(LineEnding(rawValue: "invalid"))
    }
}
