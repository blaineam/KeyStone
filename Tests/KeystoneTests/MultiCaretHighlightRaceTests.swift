//
//  MultiCaretHighlightRaceTests.swift
//  KeystoneTests
//
//  Crash (Enter Space 7.3.0, Mac): typing with carets on several lines segfaulted inside tree-sitter
//  (`ts_node_parent` <- `TreeSitterSyntaxHighlighter.bracketDepth`). The highlighter collected its captures on a
//  background queue and then walked each capture's node up the tree on the main queue; by then a reparse
//  (asynchronous for big documents) had replaced and freed the tree the nodes pointed into.
//
//  These drive that scenario end to end. A use-after-free often does not crash on its own, so the real guard is
//  `swift test --sanitize=address` (the crash is reported deterministically there); BracketDepthCaptureTests is
//  the always-on check of the invariant that fixes it.
//

import XCTest
@testable import Keystone

#if canImport(AppKit)
import AppKit

@MainActor
final class MultiCaretHighlightRaceTests: XCTestCase {
    private func pump(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    private func lineStart(of lineIndex: Int, in lines: [String]) -> Int {
        lines.prefix(lineIndex).reduce(0) { $0 + $1.utf16.count + 1 }
    }

    /// Types one space at each of three carets (different lines, different columns) 40 times, letting the
    /// background highlight and its main-queue completion run between keystrokes.
    private func typeAtThreeCarets(language: KeystoneLanguage, lines: [String], lineIndexes: [Int], baseColumns: [Int],
                                   forceBackgroundParse: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let saved = TreeSitterInternalLanguageMode.backgroundParseThreshold
        if forceBackgroundParse { TreeSitterInternalLanguageMode.backgroundParseThreshold = 10 }
        defer { TreeSitterInternalLanguageMode.backgroundParseThreshold = saved }

        let configuration = KeystoneConfiguration()
        XCTAssertTrue(configuration.colorizeBracketPairs, "bracket-pair colours are on by default", file: file, line: line)
        let theme = KeystoneRunestoneThemeMac(configuration: configuration)
        let text = lines.joined(separator: "\n")
        let textView = TextView(frame: CGRect(x: 0, y: 0, width: 900, height: 700))
        textView.setState(TextViewState(text: text, theme: theme, language: language.treeSitterLanguage!,
                                        languageProvider: KeystoneLanguageProvider.shared))
        textView.layoutSubtreeIfNeeded()
        pump(0.3)

        for round in 0..<40 {
            let starts = lineIndexes.map { lineStart(of: $0, in: lines) }
            let columns = baseColumns.enumerated().map { $0.element + (round + $0.offset * 3) % 7 }
            textView.selectedRanges = zip(starts, columns).map { NSRange(location: $0 + $1, length: 0) }
            textView.debugInsertText(" ")
            textView.layoutSubtreeIfNeeded()
            textView.displayIfNeeded()
            pump(0.01)
        }
        pump(1.0)
        // Every round typed one space at each caret, and nothing else changed.
        XCTAssertEqual(textView.text.utf16.count, text.utf16.count + 40 * 3, file: file, line: line)
        XCTAssertEqual(textView.text.replacingOccurrences(of: " ", with: ""), text.replacingOccurrences(of: " ", with: ""),
                       file: file, line: line)
    }

    private var javascriptLines: [String] {
        (0..<60).map { "function f\($0)(a, b) { return [a[0], (b + \($0)), {k: [1, (2)]}, g(h(i(j)))]; }" }
    }

    /// Self-closing tags, an inline <style> and an inline <script>: each embedded language is its own syntax tree.
    private var htmlLines: [String] {
        (0..<40).map { i in
            "<div class=\"c\(i)\"><br/><img src=\"a\(i).png\" alt=\"x\"/><input type=\"text\" value=\"\(i)\"/><style>.k\(i){margin:0;padding:\(i)px}</style><script>f(\(i),[1,(2)],{a:{b:\(i)}});</script></div>"
        }
    }

    func testJavaScript_differentColumns() {
        typeAtThreeCarets(language: .javascript, lines: javascriptLines, lineIndexes: [3, 9, 14], baseColumns: [6, 22, 41], forceBackgroundParse: false)
    }

    func testJavaScript_differentColumns_backgroundParse() {
        typeAtThreeCarets(language: .javascript, lines: javascriptLines, lineIndexes: [3, 9, 14], baseColumns: [6, 22, 41], forceBackgroundParse: true)
    }

    func testHTMLWithSelfClosingTagsAndEmbeddedLanguages() {
        typeAtThreeCarets(language: .html, lines: htmlLines, lineIndexes: [2, 6, 11], baseColumns: [9, 31, 77], forceBackgroundParse: false)
    }

    func testHTMLWithSelfClosingTagsAndEmbeddedLanguages_backgroundParse() {
        typeAtThreeCarets(language: .html, lines: htmlLines, lineIndexes: [2, 6, 11], baseColumns: [9, 31, 77], forceBackgroundParse: true)
    }
}
#endif
