//
//  CodeFoldingTests.swift
//  KeystoneTests
//

import XCTest
@testable import Keystone

@MainActor
final class CodeFoldingTests: XCTestCase {

    // MARK: - Region Detection Tests

    func testDetectBlockRegions() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            if true {
                print("hello")
            }
        }
        """

        manager.analyzeText(text)

        // Should detect 2 block regions: the function and the if statement
        XCTAssertEqual(manager.regions.count, 2)
    }

    func testDetectCommentRegions() {
        let manager = CodeFoldingManager()
        let text = """
        /* This is a
           multi-line
           comment */
        let x = 1
        """

        manager.analyzeText(text)

        let commentRegions = manager.regions.filter { $0.type == .comment }
        XCTAssertEqual(commentRegions.count, 1)
        XCTAssertEqual(commentRegions.first?.startLine, 0)
        XCTAssertEqual(commentRegions.first?.endLine, 2)
    }

    func testNoRegionsForSingleLineBlocks() {
        let manager = CodeFoldingManager()
        let text = "let array = [1, 2, 3]"

        manager.analyzeText(text)

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

        manager.analyzeText(text)

        guard let region = manager.regions.first else {
            XCTFail("Expected at least one region")
            return
        }

        XCTAssertFalse(manager.foldedRegionIds.contains(region.id))

        manager.toggleFold(for: region)
        XCTAssertTrue(manager.foldedRegionIds.contains(region.id))

        manager.toggleFold(for: region)
        XCTAssertFalse(manager.foldedRegionIds.contains(region.id))
    }

    func testFoldAndUnfoldSeparately() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            print("hello")
        }
        """

        manager.analyzeText(text)

        guard let region = manager.regions.first else {
            XCTFail("Expected at least one region")
            return
        }

        manager.fold(region)
        XCTAssertTrue(manager.foldedRegionIds.contains(region.id))

        manager.unfold(region)
        XCTAssertFalse(manager.foldedRegionIds.contains(region.id))
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

        manager.analyzeText(text)
        XCTAssertGreaterThan(manager.regions.count, 0)

        manager.foldAll()

        for region in manager.regions {
            XCTAssertTrue(manager.foldedRegionIds.contains(region.id))
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

        manager.analyzeText(text)
        manager.foldAll()
        manager.unfoldAll()

        for region in manager.regions {
            XCTAssertFalse(manager.foldedRegionIds.contains(region.id))
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

        manager.analyzeText(text)

        guard let region = manager.regions.first else {
            XCTFail("Expected at least one region")
            return
        }

        // Before folding, no lines are hidden
        XCTAssertFalse(manager.isLineHidden(1))
        XCTAssertFalse(manager.isLineHidden(2))

        manager.fold(region)

        // After folding, lines 1-3 should be hidden (but not line 0 which has the opening brace)
        XCTAssertTrue(manager.isLineHidden(1))
        XCTAssertTrue(manager.isLineHidden(2))
        XCTAssertTrue(manager.isLineHidden(3)) // closing brace line
        XCTAssertFalse(manager.isLineHidden(0)) // opening brace line stays visible
        XCTAssertFalse(manager.isLineHidden(4)) // line after region
    }

    func testIsLineHiddenWhenDisabled() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            line 2
        }
        """

        manager.analyzeText(text)
        guard let region = manager.regions.first else {
            XCTFail("Expected at least one region")
            return
        }

        manager.fold(region)
        XCTAssertTrue(manager.isLineHidden(1))

        // Disable folding - hiddenLines should still contain lines but isEnabled affects region detection
        manager.isEnabled = false
        manager.analyzeText(text) // Re-analyze clears regions
        XCTAssertTrue(manager.regions.isEmpty)
    }

    // MARK: - Region Query Tests

    func testRegionAtLine() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            print("hello")
        }
        """

        manager.analyzeText(text)

        // Region starts at line 0
        let region = manager.regionStarting(atLine: 0)
        XCTAssertNotNil(region)
        XCTAssertEqual(region?.startLine, 0)

        // No region starts at line 1
        XCTAssertNil(manager.regionStarting(atLine: 1))
    }

    func testRegionAtLineWhenDisabled() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            print("hello")
        }
        """

        manager.analyzeText(text)
        manager.isEnabled = false
        manager.analyzeText(text) // Re-analyze after disabling

        // Should return nil when disabled
        XCTAssertNil(manager.regionStarting(atLine: 0))
    }

    func testHasFoldableRegion() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            print("hello")
        }
        """

        manager.analyzeText(text)

        // Use regionStarting(atLine:) to check if a foldable region exists at a line
        XCTAssertNotNil(manager.regionStarting(atLine: 0)) // Region starts at line 0
        XCTAssertNil(manager.regionStarting(atLine: 1))    // No region starts at line 1
        XCTAssertNil(manager.regionStarting(atLine: 2))    // No region starts at line 2
    }

    // MARK: - Line Count Tests

    func testRegionLineCount() {
        let region = FoldableRegion(
            startLine: 1,
            endLine: 5,
            type: .block,
            range: NSRange(location: 0, length: 100),
            previewText: "test"
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

        manager.analyzeText(text)

        guard let region = manager.regions.first else {
            XCTFail("Expected at least one region")
            return
        }

        XCTAssertFalse(region.previewText.isEmpty)
        XCTAssertTrue(region.previewText.contains("func") || region.previewText == "...")
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

        manager.analyzeText(text)

        // Should detect multiple regions (class, func, if block)
        XCTAssertGreaterThanOrEqual(manager.regions.count, 3)
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

        manager.analyzeText(text)

        let classRegion = manager.regions.first { $0.startLine == 0 }
        let funcRegion = manager.regions.first { $0.startLine == 1 }

        XCTAssertNotNil(classRegion)
        XCTAssertNotNil(funcRegion)

        // Fold only the function
        if let funcRegion = funcRegion {
            manager.fold(funcRegion)
            XCTAssertTrue(manager.foldedRegionIds.contains(funcRegion.id))
        }

        // Class should still be unfolded
        if let classRegion = classRegion {
            XCTAssertFalse(manager.foldedRegionIds.contains(classRegion.id))
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

        manager.analyzeText(text)
        manager.isEnabled = false
        manager.analyzeText(text) // Re-analyze after disabling

        // When disabled, no regions should be found
        XCTAssertTrue(manager.regions.isEmpty)
    }

    // MARK: - Hidden Lines Tests

    func testHiddenLines() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            line 2
        }
        """

        manager.analyzeText(text)
        guard let region = manager.regions.first else {
            XCTFail("Expected at least one region")
            return
        }

        // Before folding, no hidden lines
        XCTAssertTrue(manager.hiddenLines.isEmpty)

        manager.fold(region)

        // After folding, should have hidden lines
        XCTAssertFalse(manager.hiddenLines.isEmpty)
    }

    func testHiddenLinesAfterUnfold() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            line 2
        }
        """

        manager.analyzeText(text)
        guard let region = manager.regions.first else {
            XCTFail("Expected at least one region")
            return
        }

        manager.fold(region)
        XCTAssertFalse(manager.hiddenLines.isEmpty)

        manager.unfold(region)
        XCTAssertTrue(manager.hiddenLines.isEmpty)
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

        manager.analyzeText(text)

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

        manager.analyzeText(text)
        let firstAnalysisRegions = manager.regions

        // Analyze same text again
        manager.analyzeText(text)

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

        manager.analyzeText(text1)
        XCTAssertEqual(manager.regions.count, 1)

        let text2 = """
        func test() {
            print("hello")
        }
        func another() {
            print("world")
        }
        """

        manager.analyzeText(text2)
        XCTAssertEqual(manager.regions.count, 2)
    }

    // MARK: - Folded Region State Tests

    func testFoldedRegionState() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            line 2
        }
        """

        manager.analyzeText(text)
        guard let region = manager.regions.first else {
            XCTFail("Expected at least one region")
            return
        }

        // Before folding, no lines should be hidden
        XCTAssertTrue(manager.hiddenLines.isEmpty)

        manager.fold(region)

        // After folding, inner lines should be hidden
        XCTAssertFalse(manager.hiddenLines.isEmpty)
        XCTAssertTrue(manager.foldedRegionIds.contains(region.id))
    }

    // MARK: - Region Containing Line Tests

    func testRegionContainingLine() {
        let manager = CodeFoldingManager()
        let text = """
        func test() {
            line 1
            line 2
        }
        """

        manager.analyzeText(text)

        // region(atLine:) returns innermost region containing the line
        let regionContainingLine1 = manager.region(atLine: 1)
        XCTAssertNotNil(regionContainingLine1)
        XCTAssertEqual(regionContainingLine1?.startLine, 0)

        // Line 4 is outside all regions
        let regionContainingLine4 = manager.region(atLine: 4)
        XCTAssertNil(regionContainingLine4)
    }
}
