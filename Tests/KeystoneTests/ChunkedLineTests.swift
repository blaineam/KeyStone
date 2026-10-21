//
//  ChunkedLineTests.swift
//  KeystoneTests
//
//  Lines longer than `LineController.maximumHighlightedLineLength` are stored and typeset
//  in chunks. These tests edit such a line every way the reconciliation has to handle and
//  check that the chunks always spell the line, that fragments stay line-local, and that
//  caret geometry round-trips.
//

import XCTest
@testable import Keystone

#if canImport(AppKit)
@MainActor
final class ChunkedLineTests: XCTestCase {
    private var savedChunkLength = 0

    override func setUp() {
        super.setUp()
        savedChunkLength = LineController.chunkLength
        // Small chunks so a modest line has many boundaries to hit.
        LineController.chunkLength = 1_024
    }

    override func tearDown() {
        LineController.chunkLength = savedChunkLength
        super.tearDown()
    }

    /// 40k characters of words with spaces, so word wrapping has places to break.
    private static let longLine: String = {
        var s = ""
        var i = 0
        while s.utf16.count < 40_000 {
            s += "w\(i % 97)x "
            i += 1
        }
        return s
    }()

    private func makeTextView(_ text: String) -> TextView {
        let textView = TextView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        textView.setState(TextViewState(text: text, theme: DefaultTheme()))
        textView.isLineWrappingEnabled = true
        textView.layoutSubtreeIfNeeded()
        return textView
    }

    private func lineText(_ textView: TextView, containing location: Int) -> String {
        let ns = textView.text as NSString
        let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
        return ns.substring(with: lineRange)
    }

    /// Chunks must be contiguous from 0, each within the limit, and spell the line.
    private func assertChunksSpellLine(_ textView: TextView, containing location: Int, file: StaticString = #filePath, line: UInt = #line) {
        guard let controller = textView.debugLineController(containing: location) else {
            return XCTFail("no line controller", file: file, line: line)
        }
        let chunks = controller.chunks
        XCTAssertGreaterThan(chunks.count, 1, "the line should be chunked", file: file, line: line)
        var expectedLocation = 0
        var joined = ""
        for chunk in chunks {
            XCTAssertEqual(chunk.location, expectedLocation, "chunks must be contiguous", file: file, line: line)
            XCTAssertLessThanOrEqual(chunk.length, LineController.chunkLength, file: file, line: line)
            XCTAssertGreaterThan(chunk.length, 0, file: file, line: line)
            expectedLocation += chunk.length
            joined += chunk.string as String
        }
        XCTAssertEqual(joined, lineText(textView, containing: location), "chunks must spell the line", file: file, line: line)
        XCTAssertEqual(controller.attributedString?.string, joined, file: file, line: line)
    }

    /// Caret x for `index` must map back to `index` through hit testing, using the fragment's own offset.
    private func assertCaretRoundTrips(_ textView: TextView, at index: Int, file: StaticString = #filePath, line: UInt = #line) {
        textView.scrollRangeToVisible(NSRange(location: index, length: 0), centerVertically: true)
        textView.layoutSubtreeIfNeeded()
        guard let controller = textView.debugLineController(containing: index) else {
            return XCTFail("no line controller", file: file, line: line)
        }
        let local = index - controller.line.location
        let rect = controller.caretRect(atIndex: local)
        XCTAssertGreaterThanOrEqual(rect.minX, 0, file: file, line: line)
        XCTAssertLessThan(rect.minX, 600, "caret x must be inside the wrapped width", file: file, line: line)
        let hit = controller.closestIndex(to: CGPoint(x: rect.minX + 1, y: rect.midY))
        XCTAssertEqual(hit, index, "closestIndex must undo caretRect across chunk offsets", file: file, line: line)
    }

    func testShortLineIsOneChunkWithZeroOffset() {
        let textView = makeTextView("short line\nsecond")
        let controller = textView.debugLineController(containing: 2)!
        XCTAssertEqual(controller.chunks.count, 1)
        XCTAssertEqual(controller.chunks[0].location, 0)
        XCTAssertEqual(controller.chunks[0].string as String, "short line\n")
        XCTAssertEqual(controller.caretRect(atIndex: 0).minX, 0)
    }

    func testEditsEverywhereKeepChunksSpellingTheLine() {
        let prefix = "first line\n"
        let textView = makeTextView(prefix + Self.longLine + "\nlast line")
        let lineStart = (prefix as NSString).length
        assertChunksSpellLine(textView, containing: lineStart)
        let controller = textView.debugLineController(containing: lineStart)!
        let boundary = controller.chunks[3].location

        // Insert inside a chunk, at a chunk boundary, and at the start of the line.
        for offset in [20_000, boundary, boundary - 1, 0] {
            textView.replace(NSRange(location: lineStart + offset, length: 0), withText: "INSERT")
            assertChunksSpellLine(textView, containing: lineStart)
        }
        // Delete across a chunk boundary, then a whole chunk and a half.
        let boundary2 = textView.debugLineController(containing: lineStart)!.chunks[5].location
        textView.replace(NSRange(location: lineStart + boundary2 - 10, length: 20), withText: "")
        assertChunksSpellLine(textView, containing: lineStart)
        textView.replace(NSRange(location: lineStart + boundary2, length: LineController.chunkLength * 3 / 2), withText: "")
        assertChunksSpellLine(textView, containing: lineStart)
        // Replace with longer text so the chunk splits, and with a huge paste.
        textView.replace(NSRange(location: lineStart + 5_000, length: 3), withText: String(repeating: "y", count: 3_000))
        assertChunksSpellLine(textView, containing: lineStart)
        textView.replace(NSRange(location: lineStart + 100, length: 0), withText: String(repeating: "z ", count: 2_000))
        assertChunksSpellLine(textView, containing: lineStart)
        // Delete at the very end of the line (before its newline).
        let length = (lineText(textView, containing: lineStart) as NSString).length
        textView.replace(NSRange(location: lineStart + length - 3, length: 2), withText: "")
        assertChunksSpellLine(textView, containing: lineStart)
        XCTAssertTrue(textView.text.hasSuffix("\nlast line"))
    }

    func testCompareFallbackMatchesHintedUpdate() {
        // When the edit extent is not known (another invalidation came first) the controller
        // compares old and new text; it must reach the same chunks.
        let textView = makeTextView(Self.longLine + "\n")
        let controller = textView.debugLineController(containing: 0)!
        controller.invalidateEverything()
        textView.replace(NSRange(location: 12_345, length: 7), withText: "compared")
        assertChunksSpellLine(textView, containing: 0)
        controller.invalidateEverything()
        textView.replace(NSRange(location: 1, length: 10_000), withText: "")
        assertChunksSpellLine(textView, containing: 0)
    }

    func testLineBecomingLongOrShortSwitchesRepresentation() {
        let textView = makeTextView("ab\n")
        XCTAssertEqual(textView.debugLineController(containing: 0)!.chunks.count, 1)
        textView.replace(NSRange(location: 1, length: 0), withText: Self.longLine)
        assertChunksSpellLine(textView, containing: 0)
        textView.replace(NSRange(location: 1, length: (Self.longLine as NSString).length), withText: "")
        let controller = textView.debugLineController(containing: 0)!
        XCTAssertEqual(controller.chunks.count, 1)
        XCTAssertEqual(controller.chunks[0].string as String, "ab\n")
    }

    func testCaretGeometryUsesFragmentOffsets() {
        let prefix = "first line\n"
        let textView = makeTextView(prefix + Self.longLine + "\nlast line")
        let lineStart = (prefix as NSString).length
        let controller = textView.debugLineController(containing: lineStart)!
        let boundary = controller.chunks[7].location
        for index in [lineStart + 30_000, lineStart + boundary, lineStart + boundary + 5, lineStart + boundary - 1] {
            assertCaretRoundTrips(textView, at: index)
        }
        // Fragments are line-local and never cross a chunk.
        textView.scrollRangeToVisible(NSRange(location: lineStart + boundary, length: 0), centerVertically: true)
        textView.layoutSubtreeIfNeeded()
        guard let node = controller.lineFragmentNode(containingCharacterAt: boundary - 1), let fragment = node.data.lineFragment else {
            return XCTFail("no fragment at the chunk boundary")
        }
        XCTAssertLessThanOrEqual(fragment.range.upperBound, boundary)
        XCTAssertEqual(fragment.stringOffset, controller.chunks[6].location)
        // Typing after the boundary still round-trips.
        textView.replace(NSRange(location: lineStart + boundary + 2, length: 0), withText: "Q")
        assertCaretRoundTrips(textView, at: lineStart + boundary + 3)
    }
}
#endif
