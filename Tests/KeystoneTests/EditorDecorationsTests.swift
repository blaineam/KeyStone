//
//  EditorDecorationsTests.swift
//  KeystoneTests
//
//  Change markers, indent guides, bracket-pair depth and the matching-bracket highlight.
//

import XCTest
@testable import Keystone

#if canImport(AppKit)
@MainActor
final class EditorDecorationsTests: XCTestCase {
    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func makeView(_ text: String, language: KeystoneLanguage = .plainText) -> TextView {
        let textView = TextView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        if let ts = language.treeSitterLanguage {
            textView.setState(TextViewState(text: text, theme: DefaultTheme(), language: ts, languageProvider: KeystoneLanguageProvider.shared))
        } else {
            textView.setState(TextViewState(text: text, theme: DefaultTheme()))
        }
        textView.layoutSubtreeIfNeeded()
        return textView
    }

    // MARK: Change markers

    func testDocumentTracksChangesAgainstSavedText() {
        let doc = KeystoneDocument(text: "a\nb\nc\n")
        spin(0.2) // baseline hashes land
        doc.replaceAll(with: "a\nB\nc\n", preservingUndo: true)
        spin(0.8)
        XCTAssertEqual(doc.changeMarkers.modified, IndexSet([1]))
        doc.markSaved()
        spin(0.2)
        XCTAssertEqual(doc.changeMarkers, .empty)
        doc.replaceAll(with: "a\nB\nnew\nc\n", preservingUndo: true)
        spin(0.8)
        XCTAssertEqual(doc.changeMarkers.added, IndexSet([2]))
        XCTAssertTrue(doc.changeMarkers.modified.isEmpty, "B is the saved text now")
    }

    func testLoadResetsMarkers() {
        let doc = KeystoneDocument(text: "x")
        spin(0.2)
        doc.replaceAll(with: "y", preservingUndo: true)
        spin(0.8)
        XCTAssertEqual(doc.changeMarkers.modified, IndexSet([0]))
        doc.replaceAll(with: "loaded", markSaved: true)
        spin(0.2)
        XCTAssertEqual(doc.changeMarkers, .empty)
    }

    func testGutterBuildsMarkerRectsForVisibleLines() {
        let tv = makeView("one\ntwo\nthree\nfour")
        tv.showLineNumbers = true
        tv.showChangeMarkers = true
        tv.changeMarkers = LineChangeMarkers(added: IndexSet([1]), modified: IndexSet([2]), deletedBefore: IndexSet([3]))
        tv.layoutSubtreeIfNeeded()
        XCTAssertEqual(tv.debugChangeMarkerRectCount, 3)
        tv.showChangeMarkers = false
        tv.layoutSubtreeIfNeeded()
        XCTAssertEqual(tv.debugChangeMarkerRectCount, 0)
    }

    // MARK: Indent guides

    func testIndentGuideCountsIncludingBlankLines() {
        let text = """
        func a() {
            if x {
                y

                z
            }
        }
        done
        """
        let tv = makeView(text)
        tv.indentStrategy = .space(length: 4)
        tv.showIndentGuides = true
        tv.layoutSubtreeIfNeeded()
        XCTAssertEqual(tv.debugIndentGuideCount(atRow: 0), 0)
        XCTAssertEqual(tv.debugIndentGuideCount(atRow: 1), 1)
        XCTAssertEqual(tv.debugIndentGuideCount(atRow: 2), 2)
        XCTAssertEqual(tv.debugIndentGuideCount(atRow: 3), 2, "a blank line inside the block keeps the block's guides")
        XCTAssertEqual(tv.debugIndentGuideCount(atRow: 5), 1)
        XCTAssertEqual(tv.debugIndentGuideCount(atRow: 7), 0)
    }

    func testTabsCountAsOneLevel() {
        let tv = makeView("a\n\tb\n\t\tc")
        tv.indentStrategy = .tab(length: 4)
        tv.showIndentGuides = true
        tv.layoutSubtreeIfNeeded()
        XCTAssertEqual(tv.debugIndentGuideCount(atRow: 1), 1)
        XCTAssertEqual(tv.debugIndentGuideCount(atRow: 2), 2)
    }

    // MARK: Bracket pairs

    func testBracketDepthFollowsNesting() {
        let tv = makeView("f([1, {a: (2)}])", language: .javascript)
        guard let root = tv.debugTreeSitterMode?.debugRootNode else { return XCTFail("no tree") }
        var depths: [String: Int] = [:]
        var stack = [root]
        while let node = stack.popLast() {
            if !node.isNamed, let type = node.type, ["(", "[", "{"].contains(type) {
                depths["\(type)@\(node.startByte.value / 2)"] = TreeSitterSyntaxHighlighter.bracketDepth(of: node)
            }
            for i in 0..<node.childCount { if let c = node.child(at: i) { stack.append(c) } }
        }
        XCTAssertEqual(depths["(@1"], 0)
        XCTAssertEqual(depths["[@2"], 1)
        XCTAssertEqual(depths["{@6"], 2)
        XCTAssertEqual(depths["(@10"], 3)
    }

    func testMatchingBracketIsRenderedAsHighlights() {
        let doc = KeystoneDocument(text: "call(a, b)")
        let view = KeystoneTextView(document: doc, language: .javascript, configuration: KeystoneConfiguration(), cursorPosition: .constant(CursorPosition()), scrollOffset: .constant(0), matchingBracket: .constant(nil), scrollToCursor: .constant(false))
        let coordinator = view.makeCoordinator()
        defer { withExtendedLifetime(coordinator) {} }
        let textView = TextView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        textView.editorDelegate = coordinator
        textView.setState(TextViewState(text: doc.text, theme: DefaultTheme(), language: KeystoneLanguage.javascript.treeSitterLanguage!, languageProvider: KeystoneLanguageProvider.shared))
        coordinator.textView = textView
        textView.selectedRange = NSRange(location: 4, length: 0) // before "("
        spin(0.05)
        XCTAssertEqual(Set(textView.highlightedRanges.map(\.id)), ["bracket-open", "bracket-close"])
        XCTAssertEqual(textView.highlightedRanges.map(\.range.location).sorted(), [4, 9])
        textView.selectedRange = NSRange(location: 1, length: 0)
        spin(0.05)
        XCTAssertTrue(textView.highlightedRanges.isEmpty)
    }
}
#endif
