//
//  LargeFileEditingTests.swift
//  KeystoneTests
//
//  Regression tests for editing multi-megabyte files, notably single-file HTML
//  with minified JS/CSS inlined (a few enormous lines).
//

import XCTest
@testable import Keystone

enum LargeFileFixtures {
    /// Roughly `megabytes` MB of HTML: normal markup, a minified CSS line and a
    /// minified JS line that together hold most of the bytes.
    static func inlinedHTML(megabytes: Double = 2.2) -> String {
        let target = Int(megabytes * 1_000_000)
        var css = ""
        var i = 0
        while css.utf8.count < target / 3 {
            css += ".c\(i){margin:\(i % 9)px;color:#\(String(format: "%06x", i % 0xFFFFFF));padding:0 \(i % 5)px}@media(max-width:\(i % 900)px){.c\(i){display:none}}"
            i += 1
        }
        var js = ""
        i = 0
        while js.utf8.count < target * 2 / 3 {
            js += "function f\(i)(a,b){if(a>\(i)){return [a,b,{k:\"v\(i)\"}].map(function(x){return x})}else{for(var j=0;j<b;j++){a+=j}}return a}"
            i += 1
        }
        let body = (0..<400).map { "<p class=\"c\($0)\">Paragraph \($0)</p>" }.joined(separator: "\n")
        return "<!DOCTYPE html>\n<html>\n<head>\n<style>\(css)</style>\n</head>\n<body>\n\(body)\n<script>\(js)</script>\n</body>\n</html>\n"
    }
}

// MARK: - Binding sync (the "edits jump around and mix with old text" bug)

final class EditorTextSyncTests: XCTestCase {
    func testStaleBindingWhileWritePendingIsNotAnExternalChange() {
        // The editor holds newer text than the binding because the write is debounced.
        let isExternal = EditorTextSync.isExternalChange(
            binding: "old",
            lastSynced: "newer typing",
            bindingWritePending: true,
            isUpdatingText: false,
            editorText: { "newer typing" }
        )
        XCTAssertFalse(isExternal, "A stale binding must never be written back over the editor")
    }

    func testEditorTextIsNotReadWhileWritePending() {
        var reads = 0
        _ = EditorTextSync.isExternalChange(
            binding: "old", lastSynced: "new", bindingWritePending: true, isUpdatingText: false,
            editorText: { reads += 1; return "new" }
        )
        XCTAssertEqual(reads, 0)
    }

    func testBindingMatchingLastSyncedNeverCopiesEditorText() {
        var reads = 0
        let isExternal = EditorTextSync.isExternalChange(
            binding: "same", lastSynced: "same", bindingWritePending: false, isUpdatingText: false,
            editorText: { reads += 1; return "same" }
        )
        XCTAssertFalse(isExternal)
        XCTAssertEqual(reads, 0)
    }

    func testGenuineExternalChangeIsApplied() {
        XCTAssertTrue(EditorTextSync.isExternalChange(
            binding: "loaded from disk", lastSynced: "typed", bindingWritePending: false, isUpdatingText: false,
            editorText: { "typed" }
        ))
    }

    func testIgnoredWhileCoordinatorIsUpdating() {
        XCTAssertFalse(EditorTextSync.isExternalChange(
            binding: "a", lastSynced: "b", bindingWritePending: false, isUpdatingText: true,
            editorText: { "c" }
        ))
    }
}

// MARK: - Code folding on huge, minified input

@MainActor
final class LargeFileFoldingTests: XCTestCase {
    func testFoldingLargeInlinedHTMLFinishesQuickly() {
        let text = LargeFileFixtures.inlinedHTML()
        let manager = CodeFoldingManager()
        let start = Date()
        manager.analyzeText(text)
        let elapsed = Date().timeIntervalSince(start)
        // Was effectively unbounded (O(regions x file size)); linear now.
        XCTAssertLessThan(elapsed, 3.0, "analyzeText took \(elapsed)s")
    }

    func testRegionRangesAreUTF16Offsets() {
        // The emoji is 2 UTF-16 units but one Character.
        let text = "// 😀\nfunc a() {\n  1\n}\n"
        let manager = CodeFoldingManager()
        manager.analyzeText(text)
        let region = try? XCTUnwrap(manager.regions.first)
        let ns = text as NSString
        XCTAssertEqual(ns.substring(with: region!.range), "func a() {\n  1\n}")
    }

    func testFoldStateSurvivesReanalysis() {
        let text = "func a() {\n  1\n}\n"
        let manager = CodeFoldingManager()
        manager.analyzeText(text)
        let region = manager.regions[0]
        manager.fold(region)
        manager.analyzeText(text + "\n")
        XCTAssertEqual(manager.foldedRegions.count, 1)
    }

    func testBackgroundAnalysisAppliesAndDropsStaleResults() {
        let manager = CodeFoldingManager()
        manager.analyzeTextInBackground("func a() {\n  1\n}\n")
        manager.analyzeTextInBackground("func a() {\n  1\n}\nfunc b() {\n  2\n}\n")
        let done = expectation(description: "applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(manager.regions.count, 2)
    }
}

// MARK: - Bracket matcher NSString entry point

final class BracketMatcherNSStringTests: XCTestCase {
    func testNSStringVariantMatchesStringVariant() {
        let text = "a(b[c]{d})e"
        for position in 0..<(text as NSString).length {
            XCTAssertEqual(
                BracketMatcher.findMatch(in: text, at: position),
                BracketMatcher.findMatch(inNSString: text as NSString, at: position)
            )
        }
    }
}

#if canImport(AppKit)
import AppKit

// MARK: - Live text view

@MainActor
final class LargeFileTextViewTests: XCTestCase {
    private func makeTextView(text: String) -> TextView {
        let textView = TextView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let state = TextViewState(
            text: text,
            theme: DefaultTheme(),
            language: KeystoneLanguage.html.treeSitterLanguage!,
            languageProvider: KeystoneLanguageProvider.shared
        )
        textView.setState(state)
        textView.layoutSubtreeIfNeeded()
        return textView
    }

    private func settle() {
        let e = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { e.fulfill() }
        wait(for: [e], timeout: 5)
    }

    private func timedKeystroke(_ textView: TextView, at location: Int) -> TimeInterval {
        let start = Date()
        textView.replace(NSRange(location: location, length: 0), withText: "x")
        textView.layoutSubtreeIfNeeded()
        textView.displayIfNeeded()
        return Date().timeIntervalSince(start)
    }

    func testBackingStringMatchesText() {
        let textView = makeTextView(text: "hello\nworld")
        XCTAssertEqual(textView.backingString as String, textView.text)
    }

    func testCursorPositionFromTextViewMatchesScan() {
        let text = "one\ntwo 😀 x\n\nfour"
        let textView = makeTextView(text: text)
        for offset in 0...(text as NSString).length {
            textView.selectedRange = NSRange(location: offset, length: 0)
            let fast = CursorPosition.from(textView: textView)
            let slow = CursorPosition.from(offset: offset, in: text)
            XCTAssertEqual(fast, slow, "offset \(offset)")
        }
    }

    /// The edit-local injection update must produce exactly the highlighting a fresh parse does.
    func testLocalInjectionUpdatesMatchFreshParse() {
        let saved = TreeSitterLanguageLayer.localInjectionUpdateThreshold
        TreeSitterLanguageLayer.localInjectionUpdateThreshold = 1_000
        defer { TreeSitterLanguageLayer.localInjectionUpdateThreshold = saved }

        let html = LargeFileFixtures.inlinedHTML(megabytes: 0.15)
        let textView = makeTextView(text: html)
        settle()
        let ns = html as NSString
        let scriptStart = ns.range(of: "<script>").location
        let styleStart = ns.range(of: "<style>").location
        let paragraph = ns.range(of: "Paragraph 200").location

        // Edits positions are in the original text; apply back to front so they stay valid.
        let edits: [(NSRange, String)] = [
            (NSRange(location: scriptStart + 5_000, length: 0), "var added=1;"),
            (NSRange(location: styleStart + 3_000, length: 0), ".added{color:red}"),
            (NSRange(location: paragraph, length: 3), "Edited"),
            (NSRange(location: scriptStart + 1, length: 0), "// leading comment\n"),
            (NSRange(location: scriptStart + 5, length: 4), ""),
        ].sorted { $0.0.location > $1.0.location }
        for (range, text) in edits {
            textView.replace(range, withText: text)
        }

        let fresh = makeTextView(text: textView.text)
        settle()
        XCTAssertEqual(textView.debugCaptureSignature(), fresh.debugCaptureSignature())
        XCTAssertFalse(fresh.debugCaptureSignature().isEmpty)
    }

    func testRemovingAndRestoringScriptTagMatchesFreshParse() {
        let saved = TreeSitterLanguageLayer.localInjectionUpdateThreshold
        TreeSitterLanguageLayer.localInjectionUpdateThreshold = 1_000
        defer { TreeSitterLanguageLayer.localInjectionUpdateThreshold = saved }

        let html = LargeFileFixtures.inlinedHTML(megabytes: 0.15)
        let textView = makeTextView(text: html)
        settle()
        let tag = (html as NSString).range(of: "<script>")
        textView.replace(NSRange(location: tag.location, length: 1), withText: "")   // "script>" becomes text
        XCTAssertEqual(textView.debugCaptureSignature(), makeTextView(text: textView.text).debugCaptureSignature())
        textView.replace(NSRange(location: tag.location, length: 0), withText: "<")   // restore
        settle()
        XCTAssertEqual(textView.debugCaptureSignature(), makeTextView(text: html).debugCaptureSignature())
    }

    func testTypingInsideHugeMinifiedLineStaysResponsive() {
        let html = LargeFileFixtures.inlinedHTML()
        XCTAssertGreaterThan(html.utf8.count, 2_000_000)
        let textView = makeTextView(text: html)
        settle()

        // Middle of the minified JS line.
        let jsLine = (html as NSString).range(of: "<script>")
        let location = jsLine.location + 500_000

        var worst: TimeInterval = 0
        for i in 0..<5 {
            worst = max(worst, timedKeystroke(textView, at: location + i))
        }
        print("LARGE-FILE keystroke worst: \(worst)s")
        XCTAssertLessThan(worst, 0.5, "keystroke inside a 1MB line took \(worst)s")
    }

    func testTypingInRegularLineOfHugeFileStaysResponsive() {
        let html = LargeFileFixtures.inlinedHTML()
        let textView = makeTextView(text: html)
        settle()
        let location = (html as NSString).range(of: "Paragraph 200").location
        var worst: TimeInterval = 0
        for i in 0..<5 {
            worst = max(worst, timedKeystroke(textView, at: location + i))
        }
        print("LARGE-FILE regular-line keystroke worst: \(worst)s")
        XCTAssertLessThan(worst, 0.5)
    }
}
#endif
