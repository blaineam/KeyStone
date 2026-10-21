import Foundation

/// Fold regions from the syntax tree. No per-language query is needed: a named node
/// that spans several lines folds when it is a block-like construct (by type) or
/// opens with a bracket. Single-line subtrees are never descended into, so a
/// minified megabyte line costs nothing here.
extension TreeSitterLanguageLayer {
    func foldRegions(limit: Int = 20_000) -> [FoldableRegion] {
        var regions: [FoldableRegion] = []
        var seen = Set<FoldLineSpan>()
        collectFoldRegions(into: &regions, seen: &seen, limit: limit)
        return regions
    }

    func collectFoldRegions(into regions: inout [FoldableRegion], seen: inout Set<FoldLineSpan>, limit: Int) {
        if let root = tree?.rootNode {
            collect(root, into: &regions, seen: &seen, limit: limit)
        }
        for child in childLanguageLayers {
            child.collectFoldRegions(into: &regions, seen: &seen, limit: limit)
        }
    }

    /// Iterative walk (deep error-recovery trees would overflow a background thread's stack).
    private func collect(_ root: TreeSitterNode, into regions: inout [FoldableRegion], seen: inout Set<FoldLineSpan>, limit: Int) {
        var stack: [TreeSitterNode] = [root]
        while let node = stack.popLast(), regions.count < limit {
            let startRow = Int(node.startPoint.row)
            var endRow = Int(node.endPoint.row)
            guard endRow > startRow else { continue }
            // A node that ends at column 0 really ends on the previous line.
            if node.endPoint.column == 0 { endRow -= 1 }
            if endRow > startRow, node.isNamed, let type = node.type, Self.isFoldable(node, type: type) {
                let span = FoldLineSpan(start: startRow, end: endRow)
                if seen.insert(span).inserted {
                    regions.append(FoldableRegion(
                        startLine: startRow,
                        endLine: endRow,
                        type: Self.regionType(forNodeType: type),
                        range: NSRange(node.byteRange),
                        previewText: previewText(at: node.startByte)
                    ))
                }
            }
            var index = node.childCount - 1
            while index >= 0 {
                if let child = node.child(at: index) {
                    stack.append(child)
                }
                index -= 1
            }
        }
    }

    private static let foldableSuffixes = ["comment", "block", "_body", "_statement", "_declaration", "_definition", "_clause", "_section", "_item", "_element"]
    private static let foldableTypes: Set<String> = [
        "body", "element", "object", "array", "dictionary", "list", "table", "section",
        "class", "struct", "enum", "module", "interface", "namespace", "function", "method",
        "argument_list", "arguments", "parameters", "formal_parameters", "tuple", "set",
    ]
    private static let openingBrackets: Set<String> = ["{", "[", "(", "<"]

    private static func isFoldable(_ node: TreeSitterNode, type: String) -> Bool {
        if foldableTypes.contains(type) { return true }
        for suffix in foldableSuffixes where type.hasSuffix(suffix) { return true }
        // Anything that opens with a bracket and spans lines: multi-line calls, literals, generics.
        let count = min(node.childCount, 3)
        var index = 0
        while index < count {
            if let child = node.child(at: index), !child.isNamed, let childType = child.type, openingBrackets.contains(childType) {
                return true
            }
            index += 1
        }
        return false
    }

    static func regionType(forNodeType type: String) -> FoldableRegionType {
        if type.contains("comment") { return .comment }
        if type.contains("import") || type == "use_declaration" || type.contains("include") { return .imports }
        if type.contains("function") || type.contains("method") || type.contains("func") || type.contains("lambda") || type.contains("closure") { return .function }
        if type.contains("class") { return .classDefinition }
        if type.contains("struct") { return .structDefinition }
        if type.contains("enum") { return .enumDefinition }
        if type.hasPrefix("if") { return .ifStatement }
        if type.hasPrefix("for") { return .forLoop }
        if type.hasPrefix("while") || type.hasPrefix("repeat") || type.hasPrefix("do") { return .whileLoop }
        if type.hasPrefix("switch") || type.hasPrefix("match") { return .switchStatement }
        return .block
    }

    /// The first line of the region, trimmed, for the fold placeholder.
    private func previewText(at byte: ByteCount) -> String {
        let string = textSourceString
        let location = byte.value / 2
        guard location < string.length else { return "" }
        let length = min(120, string.length - location)
        var line = string.substring(with: NSRange(location: location, length: length))
        if let newline = line.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
            line = String(line[..<newline])
        }
        return String(line.trimmingCharacters(in: .whitespaces).prefix(50))
    }
}

struct FoldLineSpan: Hashable {
    let start: Int
    let end: Int
}
