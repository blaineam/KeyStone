//
//  SyntaxTreeFoldingTests.swift
//  KeystoneTests
//

import XCTest
@testable import Keystone

#if canImport(AppKit)
@MainActor
final class SyntaxTreeFoldingTests: XCTestCase {
    private func makeTextView(_ text: String, language: KeystoneLanguage) -> (TextView, CodeFoldingManager) {
        let textView = TextView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        textView.setState(TextViewState(text: text, theme: DefaultTheme(), language: language.treeSitterLanguage!, languageProvider: KeystoneLanguageProvider.shared))
        let manager = CodeFoldingManager()
        textView.codeFoldingManager = manager
        textView.layoutSubtreeIfNeeded()
        return (textView, manager)
    }

    private func waitUntilIdle(_ textView: TextView) {
        let deadline = Date().addingTimeInterval(10)
        while !textView.debugIsParsingIdle && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func spans(_ manager: CodeFoldingManager) -> [(Int, Int, FoldableRegionType)] {
        manager.regions.map { ($0.startLine, $0.endLine, $0.type) }.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
    }

    func testSwiftFoldsFunctionsAndControlFlow() {
        let swift = """
        import Foundation

        struct Point {
            var x = 0
            var y = 0
        }

        func draw(_ points: [Point]) {
            for p in points {
                if p.x > 0 {
                    print(p)
                }
            }
        }
        """
        let (_, manager) = makeTextView(swift, language: .swift)
        XCTAssertTrue(manager.usesSyntaxTreeRegions)
        let found = spans(manager)
        XCTAssertTrue(found.contains { $0.0 == 2 && $0.1 == 5 }, "struct body: \(found)")
        XCTAssertTrue(found.contains { $0.0 == 7 && $0.1 == 13 && $0.2 == .function }, "function: \(found)")
        XCTAssertTrue(found.contains { $0.0 == 8 && $0.1 == 12 && $0.2 == .forLoop }, "for: \(found)")
        XCTAssertTrue(found.contains { $0.0 == 9 && $0.1 == 11 && $0.2 == .ifStatement }, "if: \(found)")
        XCTAssertEqual(manager.regionStarting(atLine: 7)?.previewText, "func draw(_ points: [Point]) {")
    }

    func testHTMLFoldsElementsAndEmbeddedScript() {
        let html = """
        <html>
        <body>
          <div class="a">
            <p>hi</p>
          </div>
          <script>
            function f() {
              return 1;
            }
          </script>
        </body>
        </html>
        """
        let (_, manager) = makeTextView(html, language: .html)
        let found = spans(manager)
        XCTAssertTrue(found.contains { $0.0 == 0 && $0.1 == 11 }, "html element: \(found)")
        XCTAssertTrue(found.contains { $0.0 == 2 && $0.1 == 4 }, "div: \(found)")
        XCTAssertTrue(found.contains { $0.0 == 6 && $0.1 == 8 && $0.2 == .function }, "injected JS function: \(found)")
    }

    func testJSONFoldsObjectsAndArrays() {
        let json = """
        {
          "a": [
            1,
            2
          ],
          "b": {"c": 1}
        }
        """
        let (_, manager) = makeTextView(json, language: .json)
        let found = spans(manager)
        XCTAssertTrue(found.contains { $0.0 == 0 && $0.1 == 6 }, "root object: \(found)")
        XCTAssertTrue(found.contains { $0.0 == 1 && $0.1 == 4 }, "array: \(found)")
        XCTAssertFalse(found.contains { $0.0 == 5 }, "single-line object must not fold: \(found)")
    }

    func testMinifiedLineProducesNoRegionsAndIsCheap() {
        let js = "function f(){return [1,2,{a:1}]}" + String(repeating: "function g(a){if(a){return a}else{return 0}}", count: 20_000) + "\n"
        let start = Date()
        let (textView, manager) = makeTextView(js, language: .javascript)
        waitUntilIdle(textView)
        XCTAssertTrue(manager.regions.isEmpty, "\(manager.regions.count) regions")
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }

    func testRegionsFollowEditsInBackgroundMode() {
        let saved = TreeSitterInternalLanguageMode.backgroundParseThreshold
        TreeSitterInternalLanguageMode.backgroundParseThreshold = 10
        defer { TreeSitterInternalLanguageMode.backgroundParseThreshold = saved }
        let swift = "func a() {\n    1\n}\n"
        let (textView, manager) = makeTextView(swift, language: .swift)
        waitUntilIdle(textView)
        XCTAssertEqual(spans(manager).map { ($0.0, $0.1) }.first.map { [$0.0, $0.1] }, [0, 2])
        guard let first = manager.regions.first else { return XCTFail("no regions after the deferred parse") }
        // Fold it, then add a function below: the fold survives, the new region appears.
        manager.fold(first)
        textView.replace(NSRange(location: swift.utf16.count, length: 0), withText: "func b() {\n    2\n}\n")
        waitUntilIdle(textView)
        let found = spans(manager)
        XCTAssertEqual(found.count, 2, "\(found)")
        XCTAssertEqual(manager.foldedRegions.count, 1)
        XCTAssertEqual(manager.foldedRegions.first?.startLine, 0)
    }

    func testPlainTextStillUsesHeuristics() {
        let manager = CodeFoldingManager()
        manager.analyzeText("{\n a\n}\n")
        XCTAssertEqual(manager.regions.count, 1)
        XCTAssertFalse(manager.usesSyntaxTreeRegions)
    }
}
#endif
