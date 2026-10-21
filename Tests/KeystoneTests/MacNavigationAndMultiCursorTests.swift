//
//  MacNavigationAndMultiCursorTests.swift
//  KeystoneTests
//

import XCTest
@testable import Keystone

#if canImport(AppKit)
import AppKit

final class TextNavigationTests: XCTestCase {
    let s = "foo bar.baz(qux)\n  indented line\n" as NSString

    func testWordEndAfter() {
        XCTAssertEqual(TextNavigation.wordEnd(after: 0, in: s), 3)      // foo|
        XCTAssertEqual(TextNavigation.wordEnd(after: 3, in: s), 7)      // skip space, bar|
        XCTAssertEqual(TextNavigation.wordEnd(after: 7, in: s), 8)      // .|
        XCTAssertEqual(TextNavigation.wordEnd(after: 8, in: s), 11)     // baz|
        XCTAssertEqual(TextNavigation.wordEnd(after: 16, in: s), 17, "at a line end, step over the break")
    }

    func testWordStartBefore() {
        XCTAssertEqual(TextNavigation.wordStart(before: 11, in: s), 8)  // |baz
        XCTAssertEqual(TextNavigation.wordStart(before: 8, in: s), 7)   // |.
        XCTAssertEqual(TextNavigation.wordStart(before: 7, in: s), 4)   // |bar
        XCTAssertEqual(TextNavigation.wordStart(before: 4, in: s), 0)   // |foo (skips the space)
        XCTAssertEqual(TextNavigation.wordStart(before: 17, in: s), 16, "at a line start, step over the break")
    }

    func testWordRangeAt() {
        XCTAssertEqual(TextNavigation.wordRange(at: 1, in: s), NSRange(location: 0, length: 3))
        XCTAssertEqual(TextNavigation.wordRange(at: 3, in: s), NSRange(location: 0, length: 3), "caret right after a word picks it")
        XCTAssertEqual(TextNavigation.wordRange(at: 15, in: s), NSRange(location: 15, length: 1), "punctuation run")
    }

    func testFirstNonWhitespace() {
        let line = NSRange(location: 17, length: 15) // "  indented line"
        XCTAssertEqual(TextNavigation.firstNonWhitespace(in: line, of: s), 19)
    }

    func testNormalizedMergesOverlaps() {
        let (carets, primary) = CaretSelection.normalized([
            CaretSelection(range: NSRange(location: 10, length: 5)),
            CaretSelection(caretAt: 2),
            CaretSelection(range: NSRange(location: 12, length: 5)),
            CaretSelection(caretAt: 2),
        ], primary: 2)
        XCTAssertEqual(carets.map(\.range), [NSRange(location: 2, length: 0), NSRange(location: 10, length: 7)])
        XCTAssertEqual(primary, 1)
    }
}

@MainActor
final class MacKeyboardNavigationTests: XCTestCase {
    private func makeTextView(_ text: String) -> TextView {
        let textView = TextView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        textView.setState(TextViewState(text: text, theme: DefaultTheme()))
        textView.layoutSubtreeIfNeeded()
        return textView
    }

    private func cmd(_ textView: TextView, _ selector: Selector) { textView.debugDoCommand(selector) }

    func testWordMovementAndExtension() {
        let tv = makeTextView("foo bar.baz(qux)\nnext")
        tv.selectedRange = NSRange(location: 0, length: 0)
        cmd(tv, #selector(NSResponder.moveWordRight(_:)))
        XCTAssertEqual(tv.selectedRange, NSRange(location: 3, length: 0))
        cmd(tv, #selector(NSResponder.moveWordRightAndModifySelection(_:)))
        XCTAssertEqual(tv.selectedRange, NSRange(location: 3, length: 4))
        cmd(tv, #selector(NSResponder.moveWordLeftAndModifySelection(_:)))
        XCTAssertEqual(tv.selectedRange, NSRange(location: 3, length: 1), "head moves back to the start of 'bar'")
        cmd(tv, #selector(NSResponder.moveWordLeftAndModifySelection(_:)))
        XCTAssertEqual(tv.selectedRange, NSRange(location: 0, length: 3), "and past the anchor")
        cmd(tv, #selector(NSResponder.moveRight(_:)))
        XCTAssertEqual(tv.selectedRange, NSRange(location: 3, length: 0), "→ with a selection collapses to its end")
    }

    func testSmartHomeAndEnd() {
        let tv = makeTextView("    let x = 1\n")
        tv.selectedRange = NSRange(location: 10, length: 0)
        cmd(tv, #selector(NSResponder.moveToBeginningOfLine(_:)))
        XCTAssertEqual(tv.selectedRange.location, 4, "first stop is the first non-blank column")
        cmd(tv, #selector(NSResponder.moveToBeginningOfLine(_:)))
        XCTAssertEqual(tv.selectedRange.location, 0, "second stop is the real start")
        cmd(tv, #selector(NSResponder.moveToEndOfLine(_:)))
        XCTAssertEqual(tv.selectedRange.location, 13)
        cmd(tv, #selector(NSResponder.moveToBeginningOfLineAndModifySelection(_:)))
        XCTAssertEqual(tv.selectedRange, NSRange(location: 0, length: 13))
    }

    func testDocumentBoundsAndLines() {
        let tv = makeTextView("one\ntwo\nthree")
        tv.selectedRange = NSRange(location: 5, length: 0)
        cmd(tv, #selector(NSResponder.moveToEndOfDocument(_:)))
        XCTAssertEqual(tv.selectedRange.location, 13)
        cmd(tv, #selector(NSResponder.moveToBeginningOfDocumentAndModifySelection(_:)))
        XCTAssertEqual(tv.selectedRange, NSRange(location: 0, length: 13))
        tv.selectedRange = NSRange(location: 1, length: 0)
        cmd(tv, #selector(NSResponder.moveDown(_:)))
        XCTAssertEqual(tv.selectedRange.location, 5)
        cmd(tv, #selector(NSResponder.moveDownAndModifySelection(_:)))
        XCTAssertEqual(tv.selectedRange, NSRange(location: 5, length: 4))
    }

    func testDeleteWordAndToLineStart() {
        let tv = makeTextView("alpha beta gamma")
        tv.selectedRange = NSRange(location: 16, length: 0)
        cmd(tv, #selector(NSResponder.deleteWordBackward(_:)))
        XCTAssertEqual(tv.text, "alpha beta ")
        cmd(tv, #selector(NSResponder.deleteToBeginningOfLine(_:)))
        XCTAssertEqual(tv.text, "")
    }

    func testDeleteToLineStartAtLineStartJoinsLines() {
        let tv = makeTextView("one\ntwo")
        tv.selectedRange = NSRange(location: 4, length: 0)
        cmd(tv, #selector(NSResponder.deleteToBeginningOfLine(_:)))
        XCTAssertEqual(tv.text, "onetwo")
    }
}

@MainActor
final class MultiCursorTests: XCTestCase {
    private func makeTextView(_ text: String) -> TextView {
        let textView = TextView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        textView.setState(TextViewState(text: text, theme: DefaultTheme()))
        textView.layoutSubtreeIfNeeded()
        return textView
    }

    func testTypingAtTwoCaretsAndUndo() {
        let tv = makeTextView("ab\ncd")
        tv.selectedRanges = [NSRange(location: 1, length: 0), NSRange(location: 4, length: 0)]
        XCTAssertEqual(tv.selectedRanges.count, 2)
        tv.debugInsertText("X")
        XCTAssertEqual(tv.text, "aXb\ncXd")
        XCTAssertEqual(tv.selectedRanges, [NSRange(location: 2, length: 0), NSRange(location: 6, length: 0)])
        tv.debugInsertText("Y")
        XCTAssertEqual(tv.text, "aXYb\ncXYd")
        tv.textUndoManager.undo()
        XCTAssertEqual(tv.text, "ab\ncd", "one undo step reverts every caret's typing")
    }

    func testBackspaceAndForwardDeleteAtTwoCarets() {
        let tv = makeTextView("abc\ndef")
        tv.selectedRanges = [NSRange(location: 2, length: 0), NSRange(location: 6, length: 0)]
        tv.debugDoCommand(#selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(tv.text, "ac\ndf")
        XCTAssertEqual(tv.selectedRanges, [NSRange(location: 1, length: 0), NSRange(location: 4, length: 0)])
        tv.debugDoCommand(#selector(NSResponder.deleteForward(_:)))
        XCTAssertEqual(tv.text, "a\nd")
    }

    func testSelectNextAndAllOccurrences() {
        let tv = makeTextView("let a = 1\nlet b = a + a\n")
        tv.selectedRange = NSRange(location: 4, length: 0)
        tv.selectNextOccurrence()
        XCTAssertEqual(tv.selectedRanges, [NSRange(location: 4, length: 1)], "first ⌘D selects the word")
        tv.selectNextOccurrence()
        XCTAssertEqual(tv.selectedRanges, [NSRange(location: 4, length: 1), NSRange(location: 18, length: 1)])
        tv.selectNextOccurrence()
        XCTAssertEqual(tv.selectedRanges.count, 3)
        tv.selectNextOccurrence()
        XCTAssertEqual(tv.selectedRanges.count, 3, "no more occurrences: nothing added")
        tv.collapseSelections()
        XCTAssertEqual(tv.selectedRanges.count, 1)
        tv.selectAllOccurrences()
        XCTAssertEqual(tv.selectedRanges.count, 3)
        tv.debugInsertText("x")
        XCTAssertEqual(tv.text, "let x = 1\nlet b = x + x\n")
    }

    func testAddCaretBelowAndTypeOnEachLine() {
        let tv = makeTextView("one\ntwo\nthree\n")
        tv.selectedRange = NSRange(location: 0, length: 0)
        tv.addCaretBelow()
        tv.addCaretBelow()
        XCTAssertEqual(tv.selectedRanges.map(\.location), [0, 4, 8])
        tv.debugInsertText("- ")
        XCTAssertEqual(tv.text, "- one\n- two\n- three\n")
    }

    func testToggleCaretRemovesExistingOne() {
        let tv = makeTextView("abcdef")
        tv.selectedRange = NSRange(location: 1, length: 0)
        tv.toggleCaret(at: 4)
        XCTAssertEqual(tv.selectedRanges.count, 2)
        tv.toggleCaret(at: 4)
        XCTAssertEqual(tv.selectedRanges, [NSRange(location: 1, length: 0)])
    }

    func testCopyJoinsAndPasteDistributes() {
        let tv = makeTextView("aa\nbb\ncc")
        tv.selectedRanges = [NSRange(location: 0, length: 2), NSRange(location: 3, length: 2), NSRange(location: 6, length: 2)]
        XCTAssertEqual(tv.debugCopyableText(), "aa\nbb\ncc")
        tv.debugPaste("1\n2\n3")
        XCTAssertEqual(tv.text, "1\n2\n3", "one line per caret")
        tv.selectedRanges = [NSRange(location: 0, length: 0), NSRange(location: 2, length: 0)]
        tv.debugPaste("Z")
        XCTAssertEqual(tv.text, "Z1\nZ2\n3", "otherwise the same text everywhere")
    }

    func testSettingSingleSelectionCollapsesCarets() {
        let tv = makeTextView("abc")
        tv.selectedRanges = [NSRange(location: 0, length: 0), NSRange(location: 2, length: 0)]
        tv.selectedRange = NSRange(location: 1, length: 0)
        XCTAssertEqual(tv.selectedRanges, [NSRange(location: 1, length: 0)])
    }
}
#endif

