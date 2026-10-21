//
//  PerformanceBudgetTests.swift
//  KeystoneTests
//
//  Budgets for the operations that made big files unusable. The limits are loose
//  (5–10x what a quiet machine measures) so CI noise doesn't fail them, but a
//  regression of the kind these guard against is 50–500x, not 5x.
//

import XCTest
@testable import Keystone

#if canImport(AppKit)
enum PerformanceFixtures {
    /// 2.2 MB HTML with a 1 MB minified JS line and a 0.7 MB CSS line.
    static let inlinedHTML = LargeFileFixtures.inlinedHTML()
    /// 100k lines of log output, plain text.
    static let logFile: String = (0..<100_000).map { "2026-10-21T10:\(String(format: "%02d", $0 % 60)):00Z [worker-\($0 % 8)] request \($0) completed in \($0 % 900)ms status=\($0 % 7 == 0 ? "ERROR" : "OK")" }.joined(separator: "\n")
    /// 60k flat top-level statements: the worst case for tree-sitter's incremental reparse.
    static let flatSwift = String(repeating: "let value = 42 // padding padding padding\n", count: 60_000)
    /// Deeply nested JSON, 2 MB.
    static let deepJSON: String = {
        var s = ""
        for i in 0..<40_000 {
            s += "  {\"id\": \(i), \"tags\": [\"a\", \"b\"], \"nested\": {\"x\": {\"y\": {\"z\": \(i % 10)}}}},\n"
        }
        return "[\n" + s + "  null\n]\n"
    }()
}

@MainActor
final class PerformanceBudgetTests: XCTestCase {
    private func makeTextView(_ text: String, language: KeystoneLanguage) -> TextView {
        let textView = TextView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        if let tsLanguage = language.treeSitterLanguage {
            textView.setState(TextViewState(text: text, theme: DefaultTheme(), language: tsLanguage, languageProvider: KeystoneLanguageProvider.shared))
        } else {
            textView.setState(TextViewState(text: text, theme: DefaultTheme()))
        }
        textView.layoutSubtreeIfNeeded()
        return textView
    }

    private func settle(_ textView: TextView, timeout: TimeInterval = 30) {
        let deadline = Date().addingTimeInterval(timeout)
        while !textView.debugIsParsingIdle && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    @discardableResult
    private func measureKeystrokes(_ textView: TextView, at location: Int, count: Int = 5, label: String) -> TimeInterval {
        var worst: TimeInterval = 0
        for i in 0..<count {
            let start = Date()
            textView.replace(NSRange(location: location + i, length: 0), withText: "x")
            textView.layoutSubtreeIfNeeded()
            textView.displayIfNeeded()
            worst = max(worst, Date().timeIntervalSince(start))
        }
        print("BUDGET \(label): worst keystroke \(String(format: "%.1f", worst * 1000)) ms")
        return worst
    }

    private func measureOpen(_ text: String, language: KeystoneLanguage, label: String) -> (TextView, TimeInterval) {
        let start = Date()
        let textView = makeTextView(text, language: language)
        let elapsed = Date().timeIntervalSince(start)
        print("BUDGET \(label): open to first layout \(String(format: "%.0f", elapsed * 1000)) ms")
        return (textView, elapsed)
    }

    // MARK: - 2.2 MB HTML with minified lines

    func testInlinedHTMLOpenAndType() {
        let html = PerformanceFixtures.inlinedHTML
        let (textView, open) = measureOpen(html, language: .html, label: "html open")
        XCTAssertLessThan(open, 1.0, "opening must not block on the full parse")
        settle(textView)
        let ns = html as NSString
        let normal = measureKeystrokes(textView, at: ns.range(of: "Paragraph 200").location, label: "html normal line")
        XCTAssertLessThan(normal, 0.05)
        let minified = measureKeystrokes(textView, at: ns.range(of: "<script>").location + 500_000, label: "html minified line")
        XCTAssertLessThan(minified, 0.1)
    }

    // MARK: - 100k-line log

    func testLogFileOpenTypeAndScroll() {
        let log = PerformanceFixtures.logFile
        let (textView, open) = measureOpen(log, language: .plainText, label: "log open")
        XCTAssertLessThan(open, 1.0)
        let typing = measureKeystrokes(textView, at: (log as NSString).length / 2, label: "log middle")
        XCTAssertLessThan(typing, 0.05)
        // Jump around the file: each stop lays out a fresh viewport.
        var worst: TimeInterval = 0
        for fraction in [0.1, 0.9, 0.5, 0.99, 0.0] {
            let location = Int(Double((log as NSString).length) * fraction)
            let start = Date()
            textView.scrollRangeToVisible(NSRange(location: location, length: 0), centerVertically: true)
            textView.layoutSubtreeIfNeeded()
            textView.displayIfNeeded()
            worst = max(worst, Date().timeIntervalSince(start))
        }
        print("BUDGET log scroll: worst jump \(String(format: "%.1f", worst * 1000)) ms")
        XCTAssertLessThan(worst, 0.2)
    }

    // MARK: - Flat 60k-line Swift (tree-sitter worst case)

    func testFlatSwiftTyping() {
        let (textView, open) = measureOpen(PerformanceFixtures.flatSwift, language: .swift, label: "flat swift open")
        XCTAssertLessThan(open, 1.0)
        settle(textView)
        let typing = measureKeystrokes(textView, at: 100, label: "flat swift")
        XCTAssertLessThan(typing, 0.05)
    }

    // MARK: - Deep JSON

    func testDeepJSONTypingAndFolds() {
        let json = PerformanceFixtures.deepJSON
        let (textView, open) = measureOpen(json, language: .json, label: "deep json open")
        XCTAssertLessThan(open, 1.0)
        let manager = CodeFoldingManager()
        textView.codeFoldingManager = manager
        settle(textView)
        let typing = measureKeystrokes(textView, at: (json as NSString).length / 2, label: "deep json")
        XCTAssertLessThan(typing, 0.05)
        settle(textView)
        // Each object sits on one line, so only the root array folds; the point is the walk stays cheap.
        XCTAssertEqual(manager.regions.first?.startLine, 0)
        XCTAssertGreaterThan(manager.regions.first?.endLine ?? 0, 40_000)
    }

    // MARK: - Deep inside a 1 MB line, looking at it

    /// Typing at offset 900,000 of the minified script line with the viewport scrolled
    /// there, wrapping, line numbers and invisibles on. Before chunked lines this was
    /// 25–40 ms per keystroke (whole-line attributed string + `CTTypesetter`); now ~6 ms
    /// in a debug build on a loaded machine.
    func testTypingDeepInsideWrappedMegabyteLine() {
        let html = PerformanceFixtures.inlinedHTML
        let textView = makeTextView(html, language: .html)
        textView.isLineWrappingEnabled = true
        textView.showLineNumbers = true
        textView.showTabs = true
        textView.showSpaces = true
        textView.showLineBreaks = true
        textView.layoutSubtreeIfNeeded()
        settle(textView)
        let location = (html as NSString).range(of: "<script>").location + 900_000
        textView.selectedRange = NSRange(location: location, length: 0)
        textView.scrollRangeToVisible(NSRange(location: location, length: 0), centerVertically: true)
        textView.layoutSubtreeIfNeeded()
        textView.displayIfNeeded()
        let count = 10
        var total: TimeInterval = 0
        var worst: TimeInterval = 0
        for i in 0..<count {
            let start = Date()
            textView.replace(NSRange(location: location + i, length: 0), withText: "x")
            textView.layoutSubtreeIfNeeded()
            textView.displayIfNeeded()
            let elapsed = Date().timeIntervalSince(start)
            total += elapsed
            worst = max(worst, elapsed)
        }
        let average = total / Double(count)
        print("BUDGET deep long line: average keystroke \(String(format: "%.1f", average * 1000)) ms, worst \(String(format: "%.1f", worst * 1000)) ms")
        XCTAssertLessThan(average, 0.025, "a keystroke deep inside a wrapped 1 MB line must only rebuild its chunk")
    }

    // MARK: - Find

    func testFindInLargeFileReturnsOffMainThread() {
        let html = PerformanceFixtures.inlinedHTML
        let manager = FindReplaceManager()
        manager.searchQuery = "Paragraph"
        let start = Date()
        manager.search(in: html)
        let mainThreadCost = Date().timeIntervalSince(start)
        print("BUDGET find: main-thread cost \(String(format: "%.1f", mainThreadCost * 1000)) ms")
        XCTAssertLessThan(mainThreadCost, 0.05, "search(in:) must only hand off")
        let deadline = Date().addingTimeInterval(10)
        while manager.isSearching && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        print("BUDGET find: results after \(String(format: "%.0f", Date().timeIntervalSince(start) * 1000)) ms")
        XCTAssertEqual(manager.matches.count, 400)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }
}
#endif
