//
//  BracketDepthCaptureTests.swift
//  KeystoneTests
//
//  The highlighter must not walk a capture's syntax node after the captures were collected: the captures
//  are produced on a background queue, consumed later on the main queue, and a reparse in between frees the
//  tree the nodes point into (a heap-use-after-free that crashed Enter Space when typing at several carets).
//  So the bracket nesting depth is read while the nodes are still valid and carried on the capture itself.
//

import XCTest
@testable import Keystone

@MainActor
final class BracketDepthCaptureTests: XCTestCase {
    private func captures(in code: String) throws -> [TreeSitterCapture] {
        let state = TextViewState(text: code, theme: DefaultTheme(),
                                  language: KeystoneLanguage.javascript.treeSitterLanguage!,
                                  languageProvider: KeystoneLanguageProvider.shared)
        let mode = try XCTUnwrap(state.languageMode as? TreeSitterInternalLanguageMode)
        return mode.captures(in: ByteRange(from: ByteCount(0), to: ByteCount(code.utf16.count * 2)))
            .sorted { $0.byteRange.lowerBound.value < $1.byteRange.lowerBound.value }
    }

    private func brackets(in code: String) throws -> [TreeSitterCapture] {
        try captures(in: code).filter { $0.name.hasPrefix("punctuation.bracket") }
    }

    func testEveryBracketCaptureCarriesItsDepthFromCreation() throws {
        let found = try brackets(in: "f([{a: (1)}]);")
        XCTAssertFalse(found.isEmpty, "the grammar reports brackets")
        XCTAssertTrue(found.allSatisfy { $0.bracketDepth != nil }, "depth is read when the capture is built, not later")
    }

    func testDepthGrowsInwardAndMirrorsOnTheClosingBracket() throws {
        let depths = try brackets(in: "g(h(i(j())));").map { $0.bracketDepth ?? -1 }
        // ( ( ( ( ) ) ) ): the outermost pair is depth 0, each nested pair is one deeper, and every closer
        // carries its opener's depth.
        XCTAssertEqual(depths, [0, 1, 2, 3, 3, 2, 1, 0])
    }

    func testNonBracketCapturesDoNotPayForDepth() throws {
        let others = try captures(in: "const x = 1;").filter { !$0.name.hasPrefix("punctuation.bracket") }
        XCTAssertFalse(others.isEmpty)
        XCTAssertTrue(others.allSatisfy { $0.bracketDepth == nil })
    }
}
