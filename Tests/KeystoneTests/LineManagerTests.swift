//
//  LineManagerTests.swift
//  KeystoneTests
//

import XCTest
@testable import Keystone

final class LineManagerTests: XCTestCase {

    // MARK: - Basic Functionality Tests

    func testEmptyText() {
        let manager = LineManager()
        manager.rebuild(from: "")

        XCTAssertEqual(manager.lineCount, 1)
        XCTAssertEqual(manager.totalLength, 0)
    }

    func testSingleLine() {
        let manager = LineManager()
        manager.rebuild(from: "Hello, World!")

        XCTAssertEqual(manager.lineCount, 1)
        XCTAssertEqual(manager.totalLength, 13)
    }

    func testMultipleLines() {
        let manager = LineManager()
        manager.rebuild(from: "Line 1\nLine 2\nLine 3")

        XCTAssertEqual(manager.lineCount, 3)
        XCTAssertEqual(manager.totalLength, 20)
    }

    func testLineEndingWithNewline() {
        let manager = LineManager()
        manager.rebuild(from: "Line 1\nLine 2\n")

        XCTAssertEqual(manager.lineCount, 2)
    }

    // MARK: - Line Lookup Tests

    func testLineContainingOffset() {
        let manager = LineManager()
        manager.rebuild(from: "Line 1\nLine 2\nLine 3")
        // "Line 1\n" = 7 chars, "Line 2\n" = 7 chars

        // Offset 0 should be in line 1
        let line1 = manager.lineContaining(offset: 0)
        XCTAssertNotNil(line1)
        XCTAssertEqual(line1?.number, 1)

        // Offset 7 should be in line 2
        let line2 = manager.lineContaining(offset: 7)
        XCTAssertNotNil(line2)
        XCTAssertEqual(line2?.number, 2)

        // Offset 14 should be in line 3
        let line3 = manager.lineContaining(offset: 14)
        XCTAssertNotNil(line3)
        XCTAssertEqual(line3?.number, 3)
    }

    func testLineAt() {
        let manager = LineManager()
        manager.rebuild(from: "Line 1\nLine 2\nLine 3")

        let line1 = manager.line(at: 1)
        XCTAssertNotNil(line1)
        XCTAssertEqual(line1?.number, 1)
        XCTAssertEqual(line1?.startOffset, 0)
        XCTAssertEqual(line1?.length, 7) // "Line 1\n"

        let line2 = manager.line(at: 2)
        XCTAssertNotNil(line2)
        XCTAssertEqual(line2?.number, 2)
        XCTAssertEqual(line2?.startOffset, 7)

        let line3 = manager.line(at: 3)
        XCTAssertNotNil(line3)
        XCTAssertEqual(line3?.number, 3)
        XCTAssertEqual(line3?.startOffset, 14)
    }

    func testStartOffset() {
        let manager = LineManager()
        manager.rebuild(from: "Line 1\nLine 2\nLine 3")

        XCTAssertEqual(manager.startOffset(forLine: 1), 0)
        XCTAssertEqual(manager.startOffset(forLine: 2), 7)
        XCTAssertEqual(manager.startOffset(forLine: 3), 14)
        XCTAssertNil(manager.startOffset(forLine: 4))
        XCTAssertNil(manager.startOffset(forLine: 0))
    }

    // MARK: - Visible Line Range Tests

    func testVisibleLineRange() {
        let manager = LineManager()
        manager.rebuild(from: "Line 1\nLine 2\nLine 3\nLine 4\nLine 5")

        let range = manager.visibleLineRange(viewportStart: 7, viewportEnd: 20)
        XCTAssertNotNil(range)
        XCTAssertEqual(range?.lowerBound, 2) // Line 2 starts at offset 7
        XCTAssertEqual(range?.upperBound, 3) // Line 3 ends at offset 21
    }

    // MARK: - Lines in Range Tests

    func testLinesInRange() {
        let manager = LineManager()
        manager.rebuild(from: "Line 1\nLine 2\nLine 3")

        // Range from offset 5 (middle of line 1) to offset 15 (line 2 + part of line 3)
        let lines = manager.lines(in: NSRange(location: 5, length: 10))
        // This should include lines 1, 2, and potentially 3
        XCTAssertGreaterThanOrEqual(lines.count, 2)
        XCTAssertEqual(lines[0].number, 1)
        XCTAssertEqual(lines[1].number, 2)
    }

    // MARK: - LF Handling Tests

    func testLFLineEndings() {
        let manager = LineManager()
        manager.rebuild(from: "Line 1\nLine 2\nLine 3")

        XCTAssertEqual(manager.lineCount, 3)

        let line1 = manager.line(at: 1)
        XCTAssertEqual(line1?.length, 7) // "Line 1\n"

        let line2 = manager.line(at: 2)
        XCTAssertEqual(line2?.startOffset, 7)
    }

    // MARK: - Incremental Update Tests

    func testDidInsertMarksRebuildNeeded() {
        let manager = LineManager()
        manager.rebuild(from: "Hello")
        manager.clearRebuildFlag()

        manager.didInsert(at: 5, text: "\nWorld")

        XCTAssertTrue(manager.rebuildNeeded)
    }

    func testDidDeleteMarksRebuildNeeded() {
        let manager = LineManager()
        manager.rebuild(from: "Hello\nWorld")
        manager.clearRebuildFlag()

        manager.didDelete(range: NSRange(location: 5, length: 6))

        XCTAssertTrue(manager.rebuildNeeded)
    }

    // MARK: - Edge Cases

    func testInvalidLineNumber() {
        let manager = LineManager()
        manager.rebuild(from: "Hello")

        XCTAssertNil(manager.line(at: 0))
        XCTAssertNil(manager.line(at: -1))
        XCTAssertNil(manager.line(at: 100))
    }

    func testInvalidOffset() {
        let manager = LineManager()
        manager.rebuild(from: "Hello")

        XCTAssertNil(manager.lineContaining(offset: -1))
        XCTAssertNil(manager.lineContaining(offset: 100))
    }
}

// MARK: - LineHeightCache Tests

final class LineHeightCacheTests: XCTestCase {

    func testRebuild() {
        let cache = LineHeightCache()
        cache.rebuild(lineCount: 5, defaultHeight: 20.0)

        XCTAssertEqual(cache.lineCount, 5)
        XCTAssertEqual(cache.totalHeight, 100.0)
    }

    func testHeightForLine() {
        let cache = LineHeightCache()
        cache.rebuild(lineCount: 3, defaultHeight: 20.0)

        XCTAssertEqual(cache.height(forLine: 1), 20.0)
        XCTAssertEqual(cache.height(forLine: 2), 20.0)
        XCTAssertEqual(cache.height(forLine: 3), 20.0)
    }

    func testSetHeight() {
        let cache = LineHeightCache()
        cache.rebuild(lineCount: 3, defaultHeight: 20.0)

        cache.setHeight(30.0, forLine: 2)

        XCTAssertEqual(cache.height(forLine: 2), 30.0)
        XCTAssertEqual(cache.totalHeight, 70.0) // 20 + 30 + 20
    }

    func testYOffset() {
        let cache = LineHeightCache()
        cache.rebuild(lineCount: 3, defaultHeight: 20.0)

        XCTAssertEqual(cache.yOffset(forLine: 1), 0.0)
        XCTAssertEqual(cache.yOffset(forLine: 2), 20.0)
        XCTAssertEqual(cache.yOffset(forLine: 3), 40.0)
    }

    func testLineAtYOffset() {
        let cache = LineHeightCache()
        cache.rebuild(lineCount: 5, defaultHeight: 20.0)

        XCTAssertEqual(cache.lineAt(yOffset: 0), 1)
        XCTAssertEqual(cache.lineAt(yOffset: 19), 1)
        XCTAssertEqual(cache.lineAt(yOffset: 20), 2)
        XCTAssertEqual(cache.lineAt(yOffset: 50), 3)
        XCTAssertEqual(cache.lineAt(yOffset: 90), 5)
    }

    func testVisibleLines() {
        let cache = LineHeightCache()
        cache.rebuild(lineCount: 10, defaultHeight: 20.0)

        let visibleRange = cache.visibleLines(viewportTop: 30, viewportBottom: 70)

        XCTAssertEqual(visibleRange.lowerBound, 2)
        XCTAssertEqual(visibleRange.upperBound, 4)
    }
}
