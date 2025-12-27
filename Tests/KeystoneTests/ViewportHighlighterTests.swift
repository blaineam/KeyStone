//
//  ViewportHighlighterTests.swift
//  KeystoneTests
//

import XCTest
@testable import Keystone

final class HighlightTrackerTests: XCTestCase {

    // MARK: - Basic Functionality Tests

    func testNeedsHighlightingForUnhighlightedLine() {
        let tracker = HighlightTracker()

        XCTAssertTrue(tracker.needsHighlighting(line: 1))
        XCTAssertTrue(tracker.needsHighlighting(line: 5))
        XCTAssertTrue(tracker.needsHighlighting(line: 100))
    }

    func testMarkHighlightedLine() {
        let tracker = HighlightTracker()

        tracker.markHighlighted(line: 1)

        XCTAssertFalse(tracker.needsHighlighting(line: 1))
        XCTAssertTrue(tracker.needsHighlighting(line: 2))
    }

    func testMarkHighlightedRange() {
        let tracker = HighlightTracker()

        tracker.markHighlighted(lines: 1...5)

        XCTAssertFalse(tracker.needsHighlighting(line: 1))
        XCTAssertFalse(tracker.needsHighlighting(line: 3))
        XCTAssertFalse(tracker.needsHighlighting(line: 5))
        XCTAssertTrue(tracker.needsHighlighting(line: 6))
    }

    func testDocumentDidChange() {
        let tracker = HighlightTracker()

        tracker.markHighlighted(line: 1)
        XCTAssertFalse(tracker.needsHighlighting(line: 1))

        tracker.documentDidChange()
        XCTAssertTrue(tracker.needsHighlighting(line: 1))
    }

    func testMarkLinesDirty() {
        let tracker = HighlightTracker()

        tracker.markHighlighted(lines: 1...10)
        tracker.markLinesDirty(5...7)

        XCTAssertFalse(tracker.needsHighlighting(line: 1))
        XCTAssertFalse(tracker.needsHighlighting(line: 4))
        XCTAssertTrue(tracker.needsHighlighting(line: 5))
        XCTAssertTrue(tracker.needsHighlighting(line: 6))
        XCTAssertTrue(tracker.needsHighlighting(line: 7))
        XCTAssertFalse(tracker.needsHighlighting(line: 8))
    }

    func testMarkAllDirty() {
        let tracker = HighlightTracker()

        tracker.markHighlighted(lines: 1...10)
        tracker.markAllDirty()

        XCTAssertTrue(tracker.needsHighlighting(line: 1))
        XCTAssertTrue(tracker.needsHighlighting(line: 5))
        XCTAssertTrue(tracker.needsHighlighting(line: 10))
    }

    func testLinesNeedingHighlight() {
        let tracker = HighlightTracker()

        tracker.markHighlighted(lines: 1...3)
        tracker.markHighlighted(lines: 7...10)

        let needsHighlight = tracker.linesNeedingHighlight(in: 1...10)

        XCTAssertEqual(needsHighlight, [4, 5, 6])
    }

    func testPruneCache() {
        let tracker = HighlightTracker()

        // Highlight lines 1-100
        tracker.markHighlighted(lines: 1...100)

        // Prune keeping only lines near 50-60
        tracker.pruneCache(keepingLinesNear: 50...60, buffer: 10)

        // Lines far from viewport should now need highlighting
        XCTAssertTrue(tracker.needsHighlighting(line: 1))
        XCTAssertTrue(tracker.needsHighlighting(line: 30))
        XCTAssertTrue(tracker.needsHighlighting(line: 80))
        XCTAssertTrue(tracker.needsHighlighting(line: 100))

        // Lines within buffer should still be cached
        XCTAssertFalse(tracker.needsHighlighting(line: 45))
        XCTAssertFalse(tracker.needsHighlighting(line: 55))
        XCTAssertFalse(tracker.needsHighlighting(line: 65))
    }

    func testLastHighlightedRange() {
        let tracker = HighlightTracker()

        XCTAssertNil(tracker.lastHighlightedRange)

        tracker.markHighlighted(lines: 5...10)

        XCTAssertEqual(tracker.lastHighlightedRange, 5...10)
    }
}
