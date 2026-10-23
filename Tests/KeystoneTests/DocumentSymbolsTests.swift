//
//  DocumentSymbolsTests.swift
//  KeystoneTests
//

import XCTest
@testable import Keystone

#if canImport(AppKit)
@MainActor
final class DocumentSymbolsTests: XCTestCase {
    private func symbols(_ text: String, _ language: KeystoneLanguage) -> [DocumentSymbol] {
        let textView = TextView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        textView.setState(TextViewState(text: text, theme: DefaultTheme(), language: language.treeSitterLanguage!, languageProvider: KeystoneLanguageProvider.shared))
        textView.layoutSubtreeIfNeeded()
        return textView.documentSymbols
    }

    private func names(_ list: [DocumentSymbol]) -> [String] { list.map { "\($0.kind.rawValue):\($0.name)@\($0.depth)" } }

    func testSwift() {
        let found = symbols("""
        import Foundation
        struct Point { var x = 0; func norm() -> Int { let t = 1; return t } }
        protocol Drawable { func draw() }
        enum Shape { case a }
        func top() {}
        let answer = 42
        class Box<T> { let value: T; init(_ v: T) { value = v } }
        """, .swift)
        let n = names(found)
        XCTAssertTrue(n.contains("struct:Point@0"), "\(n)")
        XCTAssertTrue(n.contains("property:x@1") || n.contains("variable:x@1"), "\(n)")
        XCTAssertTrue(n.contains("method:norm@1") || n.contains("function:norm@1"), "\(n)")
        XCTAssertFalse(n.contains { $0.hasSuffix(":t@2") }, "locals inside functions are not symbols: \(n)")
        XCTAssertTrue(n.contains("interface:Drawable@0"), "\(n)")
        XCTAssertTrue(n.contains("enum:Shape@0"), "\(n)")
        XCTAssertTrue(n.contains("function:top@0"), "\(n)")
        XCTAssertTrue(n.contains("variable:answer@0"), "\(n)")
        XCTAssertTrue(n.contains("class:Box@0"), "\(n)")
    }

    func testJavaScriptAndPython() {
        let js = names(symbols("""
        class Cart { total() { return 1 } }
        function add(a, b) { return a + b }
        const mul = (a, b) => a * b
        """, .javascript))
        XCTAssertTrue(js.contains("class:Cart@0"), "\(js)")
        XCTAssertTrue(js.contains("method:total@1"), "\(js)")
        XCTAssertTrue(js.contains("function:add@0"), "\(js)")
        XCTAssertTrue(js.contains("function:mul@0"), "arrow function assigned to a const: \(js)")

        let py = names(symbols("""
        class Dog:
            def bark(self):
                x = 1
        def main():
            pass
        """, .python))
        XCTAssertTrue(py.contains("class:Dog@0"), "\(py)")
        XCTAssertTrue(py.contains("method:bark@1"), "\(py)")
        XCTAssertTrue(py.contains("function:main@0"), "\(py)")
    }

    func testMarkdownJSONAndHTML() {
        let md = names(symbols("# Title\n\ntext\n\n## Section A\n\n### Sub\n", .markdown))
        XCTAssertEqual(md, ["section:Title@0", "section:Section A@0", "section:Sub@0"])

        let json = names(symbols(#"{"name": "x", "deps": {"a": 1}, "list": [1]}"#, .json))
        XCTAssertEqual(json, ["key:name@0", "key:deps@0", "key:a@1", "key:list@0"])

        let html = names(symbols("<div id=\"root\"><p>hi</p><span id=\"tail\"></span></div>", .html))
        XCTAssertEqual(html, ["tag:#root@0", "tag:#tail@1"])
    }

    func testPathContainingOffset() {
        let text = """
        class Outer {
            func inner() {
                let x = 1
            }
        }
        """
        let found = symbols(text, .swift)
        let offset = (text as NSString).range(of: "let x").location
        XCTAssertEqual(found.path(containing: offset).map(\.name), ["Outer", "inner"])
        XCTAssertEqual(found.path(containing: 0).map(\.name), ["Outer"])
    }

    func testDocumentPublishesSymbols() {
        let doc = KeystoneDocument(text: "func a() {}\n")
        let view = KeystoneTextView(document: doc, language: .swift, configuration: KeystoneConfiguration(), cursorPosition: .constant(CursorPosition()), scrollOffset: .constant(0), matchingBracket: .constant(nil), scrollToCursor: .constant(false))
        let coordinator = view.makeCoordinator()
        defer { withExtendedLifetime(coordinator) {} }
        let textView = TextView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        textView.editorDelegate = coordinator
        textView.setState(TextViewState(text: doc.text, theme: DefaultTheme(), language: KeystoneLanguage.swift.treeSitterLanguage!, languageProvider: KeystoneLanguageProvider.shared))
        coordinator.textView = textView
        doc.attach(textView) { [weak coordinator] t, u in coordinator?.applyText(t, undo: u) }
        XCTAssertEqual(doc.symbols.map(\.name), ["a"])
        textView.replace(NSRange(location: 12, length: 0), withText: "func b() {}\n")
        XCTAssertEqual(doc.symbols.map(\.name), ["a", "b"])
    }
}
#endif
