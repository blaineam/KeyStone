//
//  MultiCursorIOSTests.swift
//  KeystoneTests
//
//  iPad with a hardware keyboard or pointer: the same multi-cursor behaviour as the Mac.
//

import XCTest
@testable import Keystone

#if canImport(UIKit)
import UIKit

@MainActor
final class MultiCursorIOSTests: XCTestCase {
    private func makeTextView(_ text: String) -> TextView {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        let textView = TextView(frame: window.bounds)
        textView.setState(TextViewState(text: text, theme: DefaultTheme()))
        window.addSubview(textView)
        window.isHidden = false
        textView.layoutIfNeeded()
        return textView
    }

    func testTypingAtTwoCaretsAndUndo() {
        let tv = makeTextView("ab\ncd")
        tv.selectedRanges = [NSRange(location: 1, length: 0), NSRange(location: 4, length: 0)]
        XCTAssertEqual(tv.selectedRanges.count, 2)
        tv.debugInsertText("X")
        XCTAssertEqual(tv.text, "aXb\ncXd")
        XCTAssertEqual(tv.selectedRanges, [NSRange(location: 2, length: 0), NSRange(location: 6, length: 0)])
        tv.undoManager?.undo()
        XCTAssertEqual(tv.text, "ab\ncd")
    }

    func testBackspaceAtTwoCarets() {
        let tv = makeTextView("abc\ndef")
        tv.selectedRanges = [NSRange(location: 2, length: 0), NSRange(location: 6, length: 0)]
        tv.debugDeleteBackward()
        XCTAssertEqual(tv.text, "ac\ndf")
        XCTAssertEqual(tv.selectedRanges, [NSRange(location: 1, length: 0), NSRange(location: 4, length: 0)])
    }

    func testSelectNextAndAllOccurrences() {
        let tv = makeTextView("let a = 1\nlet b = a + a\n")
        tv.selectedRange = NSRange(location: 4, length: 0)
        tv.selectNextOccurrence()
        XCTAssertEqual(tv.selectedRanges, [NSRange(location: 4, length: 1)])
        tv.selectNextOccurrence()
        XCTAssertEqual(tv.selectedRanges.count, 2)
        tv.collapseSelections()
        XCTAssertEqual(tv.selectedRanges.count, 1)
        tv.selectAllOccurrences()
        XCTAssertEqual(tv.selectedRanges.count, 3)
        tv.debugInsertText("x")
        XCTAssertEqual(tv.text, "let x = 1\nlet b = x + x\n")
    }

    func testAddCaretBelowAndMoveAll() {
        let tv = makeTextView("one\ntwo\nthree\n")
        tv.selectedRange = NSRange(location: 0, length: 0)
        tv.addCaretBelow()
        tv.addCaretBelow()
        XCTAssertEqual(tv.selectedRanges.map(\.location), [0, 4, 8])
        tv.debugMove(.wordRight, extending: true)
        XCTAssertEqual(tv.selectedRanges, [NSRange(location: 0, length: 3), NSRange(location: 4, length: 3), NSRange(location: 8, length: 5)])
        tv.debugInsertText("-")
        XCTAssertEqual(tv.text, "-\n-\n-\n")
    }

    func testCopyJoinsAndPasteDistributes() {
        let tv = makeTextView("aa\nbb")
        tv.selectedRanges = [NSRange(location: 0, length: 2), NSRange(location: 3, length: 2)]
        XCTAssertEqual(tv.debugCopyableText(), "aa\nbb")
        tv.debugPaste("1\n2")
        XCTAssertEqual(tv.text, "1\n2")
    }

    func testPlainTapCollapses() {
        let tv = makeTextView("abc")
        tv.selectedRanges = [NSRange(location: 0, length: 0), NSRange(location: 2, length: 0)]
        tv.selectedRange = NSRange(location: 1, length: 0)
        XCTAssertEqual(tv.selectedRanges, [NSRange(location: 1, length: 0)])
    }
}
#endif
