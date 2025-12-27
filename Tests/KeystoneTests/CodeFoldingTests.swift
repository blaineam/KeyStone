//
//  CodeFoldingTests.swift
//  KeystoneTests
//

import XCTest
@testable import Keystone

@MainActor
final class CodeFoldingTests: XCTestCase {

    // MARK: - Region Detection Tests

    func testDetectBraceRegions() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            if true {
                print("hello")
            }
        }
        """

        manager.analyze(text)

        // Should detect 2 brace regions: the function and the if statement
        let braceRegions = manager.regions.filter { $0.type == .braces }
        XCTAssertEqual(braceRegions.count, 2)
    }

    func testDetectBracketRegions() {
        let manager = CodeFoldingManager()
        let text = """
        let array = [
            1,
            2,
            3
        ]
        """

        manager.analyze(text)

        let bracketRegions = manager.regions.filter { $0.type == .brackets }
        XCTAssertEqual(bracketRegions.count, 1)
        XCTAssertEqual(bracketRegions.first?.startLine, 1)
        XCTAssertEqual(bracketRegions.first?.endLine, 5)
    }

    func testDetectCommentRegions() {
        let manager = CodeFoldingManager()
        let text = """
        /* This is a
           multi-line
           comment */
        let x = 1
        """

        manager.analyze(text)

        let commentRegions = manager.regions.filter { $0.type == .comment }
        XCTAssertEqual(commentRegions.count, 1)
        XCTAssertEqual(commentRegions.first?.startLine, 1)
        XCTAssertEqual(commentRegions.first?.endLine, 3)
    }

    func testNoRegionsForSingleLineBlocks() {
        let manager = CodeFoldingManager()
        let text = "let array = [1, 2, 3]"

        manager.analyze(text)

        // Single line brackets should not create a region
        XCTAssertEqual(manager.regions.count, 0)
    }

    // MARK: - Fold/Unfold Tests

    func testToggleFold() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            print("hello")
        }
        """

        manager.analyze(text)

        guard let region = manager.regions.first else {
            XCTFail("Expected at least one region")
            return
        }

        XCTAssertFalse(manager.isFolded(region))

        manager.toggleFold(region)
        XCTAssertTrue(manager.isFolded(region))

        manager.toggleFold(region)
        XCTAssertFalse(manager.isFolded(region))
    }

    func testFoldAll() {
        let manager = CodeFoldingManager()
        let text = """
        func a() {
            if true {
                print("a")
            }
        }
        func b() {
            print("b")
        }
        """

        manager.analyze(text)
        XCTAssertGreaterThan(manager.regions.count, 0)

        manager.foldAll()

        for region in manager.regions {
            XCTAssertTrue(manager.isFolded(region))
        }
    }

    func testUnfoldAll() {
        let manager = CodeFoldingManager()
        let text = """
        func a() {
            print("a")
        }
        func b() {
            print("b")
        }
        """

        manager.analyze(text)
        manager.foldAll()
        manager.unfoldAll()

        for region in manager.regions {
            XCTAssertFalse(manager.isFolded(region))
        }
    }

    // MARK: - Line Visibility Tests

    func testIsLineHidden() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            line 2
            line 3
        }
        line 5
        """

        manager.analyze(text)

        guard let region = manager.regions.first else {
            XCTFail("Expected at least one region")
            return
        }

        // Before folding, no lines are hidden
        XCTAssertFalse(manager.isLineHidden(2))
        XCTAssertFalse(manager.isLineHidden(3))

        manager.toggleFold(region)

        // After folding, lines 2-4 should be hidden (but not line 1 which has the opening brace)
        XCTAssertTrue(manager.isLineHidden(2))
        XCTAssertTrue(manager.isLineHidden(3))
        XCTAssertTrue(manager.isLineHidden(4)) // closing brace line
        XCTAssertFalse(manager.isLineHidden(1)) // opening brace line stays visible
        XCTAssertFalse(manager.isLineHidden(5)) // line after region
    }

    // MARK: - Region Query Tests

    func testRegionAtLine() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            print("hello")
        }
        """

        manager.analyze(text)

        // Region starts at line 1
        let region = manager.region(atLine: 1)
        XCTAssertNotNil(region)
        XCTAssertEqual(region?.startLine, 1)

        // No region starts at line 2
        XCTAssertNil(manager.region(atLine: 2))
    }

    func testHasFoldableRegion() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            print("hello")
        }
        """

        manager.analyze(text)

        XCTAssertTrue(manager.hasFoldableRegion(atLine: 1))
        XCTAssertFalse(manager.hasFoldableRegion(atLine: 2))
        XCTAssertFalse(manager.hasFoldableRegion(atLine: 3))
    }

    // MARK: - Line Count Tests

    func testRegionLineCount() {
        let region = FoldableRegion(
            startLine: 1,
            endLine: 5,
            type: .braces
        )

        XCTAssertEqual(region.lineCount, 5)
    }

    // MARK: - Preview Tests

    func testRegionPreview() {
        let manager = CodeFoldingManager()
        let text = """
        func longFunctionName() {
            print("hello")
        }
        """

        manager.analyze(text)

        guard let region = manager.regions.first else {
            XCTFail("Expected at least one region")
            return
        }

        XCTAssertFalse(region.preview.isEmpty)
        XCTAssertTrue(region.preview.contains("func") || region.preview == "...")
    }

    // MARK: - MARK Region Tests

    func testDetectMarkRegions() {
        let manager = CodeFoldingManager()
        let text = """
        // MARK: - Section 1
        let x = 1
        let y = 2
        // MARK: - Section 2
        let z = 3
        """

        manager.analyze(text)

        let markRegions = manager.regions.filter { $0.type == .region }
        XCTAssertGreaterThanOrEqual(markRegions.count, 1)
    }

    // MARK: - Nested Regions Tests

    func testNestedRegions() {
        let manager = CodeFoldingManager()
        let text = """
        class Foo {
            func bar() {
                if true {
                    print("nested")
                }
            }
        }
        """

        manager.analyze(text)

        // Should detect all nested brace regions
        let braceRegions = manager.regions.filter { $0.type == .braces }
        XCTAssertEqual(braceRegions.count, 3) // class, func, if
    }
}
