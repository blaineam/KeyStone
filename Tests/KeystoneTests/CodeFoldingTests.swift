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

    func testFoldAndUnfoldSeparately() {
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

        manager.fold(region)
        XCTAssertTrue(manager.isFolded(region))

        manager.unfold(region)
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

    func testIsLineHiddenWhenDisabled() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            line 2
        }
        """

        manager.analyze(text)
        guard let region = manager.regions.first else {
            XCTFail("Expected at least one region")
            return
        }

        manager.toggleFold(region)
        XCTAssertTrue(manager.isLineHidden(2))

        // Disable folding
        manager.isEnabled = false
        XCTAssertFalse(manager.isLineHidden(2))
    }

    // MARK: - Offset Visibility Tests

    func testIsOffsetHidden() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            line 2
        }
        """

        manager.analyze(text)
        guard let region = manager.regions.first else {
            XCTFail("Expected at least one region")
            return
        }

        manager.toggleFold(region)

        // Offset inside folded content should be hidden
        // "func test() {\n" is 14 chars, so offset 14+ is hidden
        XCTAssertFalse(manager.isOffsetHidden(0))  // Start of first line
        XCTAssertFalse(manager.isOffsetHidden(10)) // In first line
        XCTAssertTrue(manager.isOffsetHidden(15))  // In folded content
    }

    // MARK: - Auto-Unfold Tests

    func testUnfoldRegionsContainingOffset() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            line 2
        }
        """

        manager.analyze(text)
        guard let region = manager.regions.first else {
            XCTFail("Expected at least one region")
            return
        }

        manager.toggleFold(region)
        XCTAssertTrue(manager.isFolded(region))

        // Unfold by navigating to an offset inside the region
        let unfolded = manager.unfoldRegions(containingOffset: 15)
        XCTAssertTrue(unfolded)
        XCTAssertFalse(manager.isFolded(region))
    }

    func testUnfoldRegionsContainingLine() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            line 2
        }
        """

        manager.analyze(text)
        guard let region = manager.regions.first else {
            XCTFail("Expected at least one region")
            return
        }

        manager.toggleFold(region)
        XCTAssertTrue(manager.isFolded(region))

        // Unfold by navigating to line 2
        let unfolded = manager.unfoldRegions(containingLine: 2)
        XCTAssertTrue(unfolded)
        XCTAssertFalse(manager.isFolded(region))
    }

    func testUnfoldNestedRegions() {
        let manager = CodeFoldingManager()
        let text = """
        func outer() {
            func inner() {
                print("nested")
            }
        }
        """

        manager.analyze(text)

        // Fold all regions
        manager.foldAll()

        // Find the inner region
        let innerRegion = manager.regions.first { $0.startLine == 2 }
        XCTAssertNotNil(innerRegion)

        // Unfold by navigating to line 3 (inside inner region)
        let unfolded = manager.unfoldRegions(containingLine: 3)
        XCTAssertTrue(unfolded)

        // Both outer and inner should be unfolded since line 3 is in both
        for region in manager.regions {
            if region.startLine <= 3 && region.endLine >= 3 {
                XCTAssertFalse(manager.isFolded(region))
            }
        }
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

    func testRegionAtLineWhenDisabled() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            print("hello")
        }
        """

        manager.analyze(text)
        manager.isEnabled = false

        // Should return nil when disabled
        XCTAssertNil(manager.region(atLine: 1))
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

    func testNestedFoldingIndependent() {
        let manager = CodeFoldingManager()
        let text = """
        class Foo {
            func bar() {
                print("hello")
            }
        }
        """

        manager.analyze(text)

        let classRegion = manager.regions.first { $0.startLine == 1 }
        let funcRegion = manager.regions.first { $0.startLine == 2 }

        XCTAssertNotNil(classRegion)
        XCTAssertNotNil(funcRegion)

        // Fold only the function
        if let funcRegion = funcRegion {
            manager.fold(funcRegion)
            XCTAssertTrue(manager.isFolded(funcRegion))
        }

        // Class should still be unfolded
        if let classRegion = classRegion {
            XCTAssertFalse(manager.isFolded(classRegion))
        }
    }

    // MARK: - Enabled/Disabled Tests

    func testIsEnabledDefault() {
        let manager = CodeFoldingManager()
        XCTAssertTrue(manager.isEnabled)
    }

    func testFoldingDisabled() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            print("hello")
        }
        """

        manager.analyze(text)
        manager.isEnabled = false

        XCTAssertFalse(manager.hasFoldableRegion(atLine: 1))
        XCTAssertNil(manager.region(atLine: 1))
    }

    // MARK: - Hidden Character Ranges Tests

    func testHiddenCharacterRanges() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            line 2
        }
        """

        manager.analyze(text)
        guard let region = manager.regions.first else {
            XCTFail("Expected at least one region")
            return
        }

        // Before folding, no hidden ranges
        XCTAssertTrue(manager.hiddenCharacterRanges.isEmpty)

        manager.fold(region)

        // After folding, should have hidden ranges
        XCTAssertFalse(manager.hiddenCharacterRanges.isEmpty)
    }

    func testHiddenCharacterRangesWhenDisabled() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            line 2
        }
        """

        manager.analyze(text)
        guard let region = manager.regions.first else {
            XCTFail("Expected at least one region")
            return
        }

        manager.fold(region)
        XCTAssertFalse(manager.hiddenCharacterRanges.isEmpty)

        manager.isEnabled = false
        XCTAssertTrue(manager.hiddenCharacterRanges.isEmpty)
    }

    // MARK: - Folded Regions Property Tests

    func testFoldedRegionsProperty() {
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

        // Initially no folded regions
        XCTAssertTrue(manager.foldedRegions.isEmpty)

        // Fold one region
        if let region = manager.regions.first {
            manager.fold(region)
        }

        XCTAssertEqual(manager.foldedRegions.count, 1)

        // Fold all
        manager.foldAll()
        XCTAssertEqual(manager.foldedRegions.count, manager.regions.count)
    }

    // MARK: - Text Change Detection Tests

    func testAnalyzeSkipsUnchangedText() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            print("hello")
        }
        """

        manager.analyze(text)
        let firstAnalysisRegions = manager.regions

        // Analyze same text again
        manager.analyze(text)

        // Should have same region count
        XCTAssertEqual(manager.regions.count, firstAnalysisRegions.count)
    }

    func testAnalyzeUpdatesOnTextChange() {
        let manager = CodeFoldingManager()

        let text1 = """
        func test() {
            print("hello")
        }
        """

        manager.analyze(text1)
        XCTAssertEqual(manager.regions.count, 1)

        let text2 = """
        func test() {
            print("hello")
        }
        func another() {
            print("world")
        }
        """

        manager.analyze(text2)
        XCTAssertEqual(manager.regions.count, 2)
    }

    // MARK: - Folded Region Containing Offset Tests

    func testFoldedRegionContainingOffset() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            line 2
        }
        """

        manager.analyze(text)
        guard let region = manager.regions.first else {
            XCTFail("Expected at least one region")
            return
        }

        // Before folding, no region contains the offset
        XCTAssertNil(manager.foldedRegion(containingOffset: 15))

        manager.fold(region)

        // After folding, should find the region
        let foundRegion = manager.foldedRegion(containingOffset: 15)
        XCTAssertNotNil(foundRegion)
        XCTAssertEqual(foundRegion?.id, region.id)
    }

    // MARK: - Line Start Offset Tests

    func testGetLineStartOffset() {
        let manager = CodeFoldingManager()
        let text = """
        line1
        line2
        line3
        """

        manager.analyze(text)

        XCTAssertEqual(manager.getLineStartOffset(1), 0)
        XCTAssertEqual(manager.getLineStartOffset(2), 6) // "line1\n" = 6 chars
        XCTAssertEqual(manager.getLineStartOffset(3), 12) // "line1\nline2\n" = 12 chars
    }
}
