//
//  KeystoneLanguageTests.swift
//  KeystoneTests
//

import XCTest
@testable import Keystone

final class KeystoneLanguageTests: XCTestCase {

    // MARK: - Detection Tests

    func testDetectSwift() {
        XCTAssertEqual(KeystoneLanguage.detect(from: "main.swift"), .swift)
        XCTAssertEqual(KeystoneLanguage.detect(from: "ViewController.swift"), .swift)
        XCTAssertEqual(KeystoneLanguage.detect(from: "test.Swift"), .swift)
    }

    func testDetectPython() {
        XCTAssertEqual(KeystoneLanguage.detect(from: "script.py"), .python)
        XCTAssertEqual(KeystoneLanguage.detect(from: "main.PY"), .python)
    }

    func testDetectJavaScript() {
        XCTAssertEqual(KeystoneLanguage.detect(from: "app.js"), .javascript)
    }

    func testDetectTypeScript() {
        XCTAssertEqual(KeystoneLanguage.detect(from: "app.ts"), .typescript)
        XCTAssertEqual(KeystoneLanguage.detect(from: "component.tsx"), .typescript)
    }

    func testDetectHTML() {
        XCTAssertEqual(KeystoneLanguage.detect(from: "index.html"), .html)
        XCTAssertEqual(KeystoneLanguage.detect(from: "page.htm"), .html)
    }

    func testDetectCSS() {
        XCTAssertEqual(KeystoneLanguage.detect(from: "styles.css"), .css)
    }

    func testDetectJSON() {
        XCTAssertEqual(KeystoneLanguage.detect(from: "package.json"), .json)
    }

    func testDetectYAML() {
        XCTAssertEqual(KeystoneLanguage.detect(from: "config.yaml"), .yaml)
        XCTAssertEqual(KeystoneLanguage.detect(from: "config.yml"), .yaml)
    }

    func testDetectMarkdown() {
        XCTAssertEqual(KeystoneLanguage.detect(from: "README.md"), .markdown)
        XCTAssertEqual(KeystoneLanguage.detect(from: "docs.markdown"), .markdown)
    }

    func testDetectShell() {
        XCTAssertEqual(KeystoneLanguage.detect(from: "build.sh"), .shell)
        XCTAssertEqual(KeystoneLanguage.detect(from: "setup.bash"), .shell)
        XCTAssertEqual(KeystoneLanguage.detect(from: "script.zsh"), .shell)
    }

    func testDetectConfig() {
        XCTAssertEqual(KeystoneLanguage.detect(from: "settings.conf"), .conf)
        XCTAssertEqual(KeystoneLanguage.detect(from: "config.ini"), .conf)
    }

    func testDetectXML() {
        XCTAssertEqual(KeystoneLanguage.detect(from: "data.xml"), .xml)
    }

    func testDetectC() {
        XCTAssertEqual(KeystoneLanguage.detect(from: "main.c"), .c)
        XCTAssertEqual(KeystoneLanguage.detect(from: "header.h"), .c)
    }

    func testDetectCpp() {
        XCTAssertEqual(KeystoneLanguage.detect(from: "main.cpp"), .cpp)
        XCTAssertEqual(KeystoneLanguage.detect(from: "class.hpp"), .cpp)
        XCTAssertEqual(KeystoneLanguage.detect(from: "main.cc"), .cpp)
    }

    func testDetectJava() {
        XCTAssertEqual(KeystoneLanguage.detect(from: "Main.java"), .java)
    }

    func testDetectGo() {
        XCTAssertEqual(KeystoneLanguage.detect(from: "main.go"), .go)
    }

    func testDetectRust() {
        XCTAssertEqual(KeystoneLanguage.detect(from: "main.rs"), .rust)
    }

    func testDetectRuby() {
        XCTAssertEqual(KeystoneLanguage.detect(from: "app.rb"), .ruby)
    }

    func testDetectPHP() {
        XCTAssertEqual(KeystoneLanguage.detect(from: "index.php"), .php)
    }

    func testDetectSQL() {
        XCTAssertEqual(KeystoneLanguage.detect(from: "query.sql"), .sql)
    }

    func testDetectPlainText() {
        XCTAssertEqual(KeystoneLanguage.detect(from: "notes.txt"), .plainText)
        XCTAssertEqual(KeystoneLanguage.detect(from: "unknown.xyz"), .plainText)
        XCTAssertEqual(KeystoneLanguage.detect(from: "noextension"), .plainText)
    }

    func testDetectWithPath() {
        XCTAssertEqual(KeystoneLanguage.detect(from: "/Users/test/project/main.swift"), .swift)
        XCTAssertEqual(KeystoneLanguage.detect(from: "path/to/file.py"), .python)
    }

    // MARK: - Comment Syntax Tests

    func testSwiftCommentSyntax() {
        let syntax = KeystoneLanguage.swift.commentSyntax
        XCTAssertNotNil(syntax)
        XCTAssertEqual(syntax?.lineComment, "//")
        XCTAssertEqual(syntax?.blockComment?.start, "/*")
        XCTAssertEqual(syntax?.blockComment?.end, "*/")
    }

    func testPythonCommentSyntax() {
        let syntax = KeystoneLanguage.python.commentSyntax
        XCTAssertNotNil(syntax)
        XCTAssertEqual(syntax?.lineComment, "#")
        XCTAssertNil(syntax?.blockComment)
    }

    func testHTMLCommentSyntax() {
        let syntax = KeystoneLanguage.html.commentSyntax
        XCTAssertNotNil(syntax)
        XCTAssertNil(syntax?.lineComment)
        XCTAssertEqual(syntax?.blockComment?.start, "<!--")
        XCTAssertEqual(syntax?.blockComment?.end, "-->")
    }

    func testPlainTextHasNoCommentSyntax() {
        let syntax = KeystoneLanguage.plainText.commentSyntax
        XCTAssertNil(syntax)
    }

    func testJSONHasNoCommentSyntax() {
        let syntax = KeystoneLanguage.json.commentSyntax
        XCTAssertNil(syntax)
    }

    // MARK: - Supports Comments Tests

    func testSwiftSupportsComments() {
        XCTAssertTrue(KeystoneLanguage.swift.supportsComments)
    }

    func testPlainTextDoesNotSupportComments() {
        XCTAssertFalse(KeystoneLanguage.plainText.supportsComments)
    }

    // MARK: - Case Iterable Tests

    func testAllCases() {
        XCTAssertTrue(KeystoneLanguage.allCases.count > 15)
        XCTAssertTrue(KeystoneLanguage.allCases.contains(.swift))
        XCTAssertTrue(KeystoneLanguage.allCases.contains(.python))
        XCTAssertTrue(KeystoneLanguage.allCases.contains(.javascript))
        XCTAssertTrue(KeystoneLanguage.allCases.contains(.plainText))
    }
}
