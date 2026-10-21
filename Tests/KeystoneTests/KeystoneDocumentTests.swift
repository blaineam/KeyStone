//
//  KeystoneDocumentTests.swift
//  KeystoneTests
//

import XCTest
import Combine
@testable import Keystone

@MainActor
final class KeystoneDocumentTests: XCTestCase {
    func testInitialState() {
        let doc = KeystoneDocument(text: "a\nb\nc")
        XCTAssertEqual(doc.lineCount, 3)
        XCTAssertEqual(doc.version, 0)
        XCTAssertFalse(doc.isModified)
        XCTAssertEqual(doc.text, "a\nb\nc")
        XCTAssertEqual(doc.utf16Length, 5)
    }

    func testReplaceAllBumpsVersionAndModified() {
        let doc = KeystoneDocument(text: "a")
        var changes: [KeystoneDocument.Change] = []
        let sub = doc.didChange.sink { changes.append($0) }
        defer { sub.cancel() }

        doc.replaceAll(with: "x\ny")
        XCTAssertEqual(doc.version, 1)
        XCTAssertTrue(doc.isModified)
        XCTAssertEqual(doc.lineCount, 2)
        XCTAssertEqual(changes.count, 1)
        XCTAssertTrue(changes[0].isWholeDocument)

        doc.markSaved()
        XCTAssertFalse(doc.isModified)
        XCTAssertEqual(doc.savedVersion, 1)

        doc.replaceAll(with: "loaded", markSaved: true)
        XCTAssertFalse(doc.isModified, "a file load is the saved state")
    }

    func testDetachedPositionAndOffset() {
        let doc = KeystoneDocument(text: "one\ntwo 😀 x\n\nfour")
        XCTAssertEqual(doc.offset(line: 1), 0)
        XCTAssertEqual(doc.offset(line: 2, column: 1), 4)
        XCTAssertEqual(doc.offset(line: 2, column: 99), 4 + 8, "column clamps to the line")
        XCTAssertEqual(doc.offset(line: 3), 13)
        XCTAssertEqual(doc.offset(line: 4, column: 3), 16)
        XCTAssertNil(doc.offset(line: 5))
        let p = doc.position(atOffset: 6)
        XCTAssertEqual(p.line, 2)
        XCTAssertEqual(p.column, 3)
    }

    #if canImport(AppKit)
    private func makeAttached(_ text: String, language: KeystoneLanguage = .swift) -> (KeystoneDocument, TextView, KeystoneTextView.Coordinator) {
        let doc = KeystoneDocument(text: text)
        let view = KeystoneTextView(
            document: doc,
            language: language,
            configuration: KeystoneConfiguration(),
            cursorPosition: .constant(CursorPosition()),
            scrollOffset: .constant(0),
            matchingBracket: .constant(nil),
            scrollToCursor: .constant(false)
        )
        let coordinator = view.makeCoordinator()
        // Build the NSView the way SwiftUI would.
        let textView = TextView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        textView.editorDelegate = coordinator
        textView.setState(TextViewState(text: text, theme: DefaultTheme(), language: language.treeSitterLanguage!, languageProvider: KeystoneLanguageProvider.shared))
        coordinator.textView = textView
        doc.attach(textView) { [weak coordinator] newText, preservingUndo in
            coordinator?.applyText(newText, preservingUndo: preservingUndo)
        }
        textView.layoutSubtreeIfNeeded()
        return (doc, textView, coordinator)
    }

    func testAttachedReadsComeFromTheView() {
        let (doc, textView, coordinator) = makeAttached("let a = 1\nlet b = 2")
        defer { withExtendedLifetime(coordinator) {} }
        XCTAssertEqual(doc.lineCount, 2)
        textView.replace(NSRange(location: 0, length: 0), withText: "// c\n")
        XCTAssertEqual(doc.text, "// c\nlet a = 1\nlet b = 2")
        XCTAssertEqual(doc.lineCount, 3)
        XCTAssertEqual(doc.utf16Length, textView.backingString.length)
    }

    func testTypingReportsRangeAndBumpsVersion() {
        let (doc, textView, coordinator) = makeAttached("hello")
        defer { withExtendedLifetime(coordinator) {} }
        var changes: [KeystoneDocument.Change] = []
        let sub = doc.didChange.sink { changes.append($0) }
        defer { sub.cancel() }

        textView.replace(NSRange(location: 5, length: 0), withText: " world")
        XCTAssertEqual(doc.version, 1)
        XCTAssertTrue(doc.isModified)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].range, NSRange(location: 5, length: 0))
        XCTAssertEqual(changes[0].replacementLength, 6)

        textView.replace(NSRange(location: 0, length: 5), withText: "HELLO")
        XCTAssertEqual(changes.last?.range, NSRange(location: 0, length: 5))
        XCTAssertEqual(changes.last?.replacementLength, 5)
        XCTAssertEqual(doc.text, "HELLO world")
    }

    func testReplaceAllOnAttachedViewAppliesAndResetsUndo() {
        let (doc, textView, coordinator) = makeAttached("a")
        defer { withExtendedLifetime(coordinator) {} }
        textView.replace(NSRange(location: 1, length: 0), withText: "b")
        XCTAssertTrue(textView.textUndoManager.canUndo)

        doc.replaceAll(with: "loaded from disk", markSaved: true)
        XCTAssertEqual(textView.text, "loaded from disk")
        XCTAssertFalse(doc.isModified)
        XCTAssertFalse(textView.textUndoManager.canUndo, "a file load clears undo")

        doc.replaceAll(with: "loaded from disk!", preservingUndo: true)
        XCTAssertEqual(textView.text, "loaded from disk!")
        XCTAssertTrue(doc.isModified)
    }

    func testAttachedPositionMatchesDetachedScan() {
        let text = "one\ntwo 😀 x\n\nfour"
        let (doc, _, coordinator) = makeAttached(text, language: .swift)
        defer { withExtendedLifetime(coordinator) {} }
        let detached = KeystoneDocument(text: text)
        for offset in 0...(text as NSString).length {
            XCTAssertEqual(doc.position(atOffset: offset), detached.position(atOffset: offset), "offset \(offset)")
        }
        for line in 1...5 {
            for column in [1, 2, 3, 50] {
                XCTAssertEqual(doc.offset(line: line, column: column), detached.offset(line: line, column: column), "\(line):\(column)")
            }
        }
    }

    func testDetachKeepsText() {
        let (doc, textView, coordinator) = makeAttached("keep me")
        defer { withExtendedLifetime(coordinator) {} }
        textView.replace(NSRange(location: 7, length: 0), withText: "!")
        doc.detach(textView)
        XCTAssertEqual(doc.text, "keep me!")
        XCTAssertEqual(doc.lineCount, 1)
        doc.replaceAll(with: "x\ny")
        XCTAssertEqual(doc.lineCount, 2)
    }

    func testNoWholeBufferCopyPerKeystroke() {
        // Smoke check that a keystroke in a big attached document stays cheap now
        // that nothing on the change path reads `text`.
        let big = String(repeating: "let value = 42 // padding padding padding\n", count: 60_000)
        let (doc, textView, coordinator) = makeAttached(big, language: .swift)
        defer { withExtendedLifetime(coordinator) {} }
        XCTAssertGreaterThan(doc.utf16Length, 2_000_000)
        var versions = 0
        let sub = doc.didChange.sink { _ in versions += 1 }
        defer { sub.cancel() }
        let start = Date()
        for i in 0..<20 {
            textView.replace(NSRange(location: 100 + i, length: 0), withText: "x")
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(versions, 20)
        XCTAssertLessThan(elapsed, 1.0, "20 keystrokes took \(elapsed)s")
    }
    #endif
}
