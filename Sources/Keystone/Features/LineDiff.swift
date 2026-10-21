//
//  LineDiff.swift
//  Keystone
//
//  Line-level diff of the buffer against the saved text, for gutter change markers.
//

import Foundation

/// Which lines changed relative to the baseline, by 0-based line index in the current text.
public struct LineChangeMarkers: Equatable, Sendable {
    public var added = IndexSet()
    public var modified = IndexSet()
    /// Lines *before which* baseline lines were deleted. `lineCount` means "at the end".
    public var deletedBefore = IndexSet()

    public static let empty = LineChangeMarkers()

    public var isEmpty: Bool { added.isEmpty && modified.isEmpty && deletedBefore.isEmpty }

    public init(added: IndexSet = IndexSet(), modified: IndexSet = IndexSet(), deletedBefore: IndexSet = IndexSet()) {
        self.added = added
        self.modified = modified
        self.deletedBefore = deletedBefore
    }
}

/// Myers diff over line hashes. Linear in the text for hashing, O((N+M)·D) for the
/// diff itself; gives up (returns nil) past `maximumEditDistance` so a pathological
/// comparison never burns a core.
public enum LineDiff {
    public static var maximumEditDistance = 4_000

    /// Hashes of the lines of `text`, split on `\n` (a trailing `\r` is part of the line and
    /// so distinguishes CRLF from LF, which is what a diff should do).
    public static func lineHashes(of text: String) -> [Int] {
        let ns = text as NSString
        var hashes: [Int] = []
        hashes.reserveCapacity(ns.length / 32 + 1)
        var start = 0
        let length = ns.length
        var i = 0
        while i < length {
            if ns.character(at: i) == 0x0A {
                hashes.append(hash(ns, NSRange(location: start, length: i - start)))
                start = i + 1
            }
            i += 1
        }
        hashes.append(hash(ns, NSRange(location: start, length: length - start)))
        return hashes
    }

    private static func hash(_ string: NSString, _ range: NSRange) -> Int {
        // FNV-1a over UTF-16 units; the range is short so character(at:) is fine.
        var h: UInt64 = 0xcbf29ce484222325
        var i = range.location
        let end = range.upperBound
        while i < end {
            h ^= UInt64(string.character(at: i))
            h = h &* 0x100000001b3
            i += 1
        }
        return Int(truncatingIfNeeded: h)
    }

    /// Change markers for `new` relative to `old`. Nil when the texts differ too much to diff cheaply.
    public static func markers(old: [Int], new: [Int]) -> LineChangeMarkers? {
        // Trim the common prefix and suffix first: typing changes a few lines in the middle.
        var prefix = 0
        let minCount = min(old.count, new.count)
        while prefix < minCount && old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < minCount - prefix && old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        let a = Array(old[prefix..<(old.count - suffix)])
        let b = Array(new[prefix..<(new.count - suffix)])
        guard let script = myers(a, b) else { return nil }

        var markers = LineChangeMarkers()
        // Pair runs of deletions with the insertions that follow them: those are modifications.
        var i = 0
        while i < script.count {
            var deletes = 0
            var inserts = 0
            var insertStart: Int?
            var position = script[i].newIndex
            while i < script.count, script[i].kind == .delete {
                deletes += 1
                position = script[i].newIndex
                i += 1
            }
            while i < script.count, script[i].kind == .insert, deletes == 0 || script[i].newIndex == (insertStart ?? script[i].newIndex) + inserts {
                if insertStart == nil { insertStart = script[i].newIndex }
                inserts += 1
                i += 1
            }
            if deletes == 0 && inserts == 0 { i += 1; continue }
            let start = (insertStart ?? position) + prefix
            let paired = min(deletes, inserts)
            if paired > 0 { markers.modified.insert(integersIn: start..<(start + paired)) }
            if inserts > paired { markers.added.insert(integersIn: (start + paired)..<(start + inserts)) }
            if deletes > paired { markers.deletedBefore.insert(start + inserts) }
        }
        return markers
    }

    enum EditKind { case insert, delete }
    struct Edit { let kind: EditKind; let newIndex: Int }

    /// Classic Myers O(ND) with the forward-only V array; returns edits in order.
    static func myers(_ a: [Int], _ b: [Int]) -> [Edit]? {
        let n = a.count, m = b.count
        if n == 0 { return (0..<m).map { Edit(kind: .insert, newIndex: $0) } }
        if m == 0 { return (0..<n).map { _ in Edit(kind: .delete, newIndex: 0) } }
        let max = min(n + m, maximumEditDistance)
        let offset = max
        var v = [Int](repeating: 0, count: 2 * max + 2)
        var trace: [[Int]] = []
        var found = false
        outer: for d in 0...max {
            trace.append(v)
            var k = -d
            while k <= d {
                var x: Int
                if k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]) {
                    x = v[offset + k + 1]
                } else {
                    x = v[offset + k - 1] + 1
                }
                var y = x - k
                while x < n && y < m && a[x] == b[y] { x += 1; y += 1 }
                v[offset + k] = x
                if x >= n && y >= m { found = true; break outer }
                k += 2
            }
        }
        guard found else { return nil }
        // Backtrack.
        var edits: [Edit] = []
        var x = n, y = m
        for d in stride(from: trace.count - 1, through: 0, by: -1) {
            let v = trace[d]
            let k = x - y
            let prevK: Int
            if k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]) {
                prevK = k + 1
            } else {
                prevK = k - 1
            }
            let prevX = v[offset + prevK]
            let prevY = prevX - prevK
            while x > prevX && y > prevY { x -= 1; y -= 1 }
            if d > 0 {
                if x == prevX {
                    edits.append(Edit(kind: .insert, newIndex: prevY))   // b[prevY] inserted
                } else {
                    edits.append(Edit(kind: .delete, newIndex: prevY))   // a[prevX] deleted, before new line prevY
                }
            }
            x = prevX; y = prevY
        }
        return edits.reversed()
    }
}
