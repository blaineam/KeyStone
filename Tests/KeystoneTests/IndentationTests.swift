//
//  IndentationTests.swift
//  KeystoneTests
//

import XCTest
@testable import Keystone

final class IndentationTests: XCTestCase {

    // MARK: - Detection Tests

    func testDetectTabs() {
        let text = """
        func test() {
        \treturn true
        }
        """
        let settings = IndentationSettings.detect(from: text)
        XCTAssertEqual(settings.type, .tabs)
    }

    func testDetect4Spaces() {
        let text = """
        func test() {
            return true
        }
        """
        let settings = IndentationSettings.detect(from: text)
        XCTAssertEqual(settings.type, .spaces)
        XCTAssertEqual(settings.width, 4)
    }

    func testDetect2Spaces() {
        let text = """
        func test() {
          return true
        }
        """
        let settings = IndentationSettings.detect(from: text)
        XCTAssertEqual(settings.type, .spaces)
        XCTAssertEqual(settings.width, 2)
    }

    func testDetectNoIndentation() {
        let text = """
        line1
        line2
        line3
        """
        let settings = IndentationSettings.detect(from: text)
        // Should default to spaces with width 4
        XCTAssertEqual(settings.type, .spaces)
        XCTAssertEqual(settings.width, 4)
    }

    func testDetectEmptyString() {
        let settings = IndentationSettings.detect(from: "")
        XCTAssertEqual(settings.type, .spaces)
        XCTAssertEqual(settings.width, 4)
    }

    // MARK: - Indent String Tests

    func testIndentStringSpaces() {
        let settings = IndentationSettings(type: .spaces, width: 4)
        XCTAssertEqual(settings.indentString, "    ")

        let settings2 = IndentationSettings(type: .spaces, width: 2)
        XCTAssertEqual(settings2.indentString, "  ")
    }

    func testIndentStringTabs() {
        let settings = IndentationSettings(type: .tabs, width: 4)
        XCTAssertEqual(settings.indentString, "\t")
    }

    // MARK: - Indentation Type Tests

    func testIndentationTypeRawValues() {
        XCTAssertEqual(IndentationType.tabs.rawValue, "Tabs")
        XCTAssertEqual(IndentationType.spaces.rawValue, "Spaces")
    }

    func testIndentationTypeCaseIterable() {
        XCTAssertEqual(IndentationType.allCases.count, 2)
        XCTAssertTrue(IndentationType.allCases.contains(.tabs))
        XCTAssertTrue(IndentationType.allCases.contains(.spaces))
    }
}
