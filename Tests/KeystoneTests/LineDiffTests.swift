import XCTest
@testable import Keystone

final class LineDiffTests: XCTestCase {
    private func markers(_ old: String, _ new: String) -> LineChangeMarkers {
        LineDiff.markers(old: LineDiff.lineHashes(of: old), new: LineDiff.lineHashes(of: new))!
    }

    func testIdentical() {
        XCTAssertEqual(markers("a\nb\nc", "a\nb\nc"), .empty)
    }

    func testModifiedLine() {
        let m = markers("a\nb\nc", "a\nB\nc")
        XCTAssertEqual(m.modified, IndexSet([1]))
        XCTAssertTrue(m.added.isEmpty && m.deletedBefore.isEmpty)
    }

    func testAddedLines() {
        let m = markers("a\nc", "a\nb1\nb2\nc")
        XCTAssertEqual(m.added, IndexSet([1, 2]))
        XCTAssertTrue(m.modified.isEmpty)
    }

    func testDeletedLines() {
        let m = markers("a\nb\nc\nd", "a\nd")
        XCTAssertEqual(m.deletedBefore, IndexSet([1]))
        XCTAssertTrue(m.added.isEmpty && m.modified.isEmpty)
    }

    func testDeletionAtEnd() {
        let m = markers("a\nb\nc", "a")
        XCTAssertEqual(m.deletedBefore, IndexSet([1]))
    }

    func testReplaceTwoWithThree() {
        let m = markers("a\nx\ny\nz", "a\n1\n2\n3\nz")
        XCTAssertEqual(m.modified, IndexSet([1, 2]))
        XCTAssertEqual(m.added, IndexSet([3]))
    }

    func testAppendAtEndOfFile() {
        let m = markers("a\nb", "a\nb\nc")
        XCTAssertEqual(m.added, IndexSet([2]))
    }

    func testCRLFDiffersFromLF() {
        XCTAssertEqual(markers("a\r\nb", "a\nb").modified, IndexSet([0]))
    }

    func testLargeFileWithSmallEditIsFast() {
        let lines = (0..<200_000).map { "line \($0) some content here" }
        let old = lines.joined(separator: "\n")
        var changed = lines
        changed[100_000] = "edited"
        changed.insert("new", at: 150_000)
        let new = changed.joined(separator: "\n")
        let start = Date()
        let oldHashes = LineDiff.lineHashes(of: old)
        let newHashes = LineDiff.lineHashes(of: new)
        let m = LineDiff.markers(old: oldHashes, new: newHashes)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(m?.modified, IndexSet([100_000]))
        XCTAssertEqual(m?.added, IndexSet([150_000]))
        XCTAssertLessThan(elapsed, 1.0, "\(elapsed)s")
    }

    func testGivesUpOnUnrelatedTexts() {
        let saved = LineDiff.maximumEditDistance
        LineDiff.maximumEditDistance = 10
        defer { LineDiff.maximumEditDistance = saved }
        let old = (0..<100).map { "o\($0)" }.joined(separator: "\n")
        let new = (0..<100).map { "n\($0)" }.joined(separator: "\n")
        XCTAssertNil(LineDiff.markers(old: LineDiff.lineHashes(of: old), new: LineDiff.lineHashes(of: new)))
    }
}
