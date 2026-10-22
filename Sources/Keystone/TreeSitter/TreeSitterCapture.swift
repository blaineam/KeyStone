import Foundation

final class TreeSitterCapture {
    let node: TreeSitterNode
    let index: UInt32
    let name: String
    let byteRange: ByteRange
    let properties: [String: String]
    let textPredicates: [TreeSitterTextPredicate]
    let nameComponentCount: Int
    /// Bracket nesting depth, read from the tree when the capture is built (under the tree lock) because
    /// `node` must not be walked later: the capture outlives the tree it came from, and a reparse frees it.
    let bracketDepth: Int?

    convenience init(node: TreeSitterNode, index: UInt32, name: String, predicates: [TreeSitterPredicate], bracketDepth: Int? = nil) {
        self.init(node: node, index: index, name: name, byteRange: node.byteRange, predicates: predicates, bracketDepth: bracketDepth)
    }

    private init(node: TreeSitterNode, index: UInt32, name: String, byteRange: ByteRange, predicates: [TreeSitterPredicate], bracketDepth: Int?) {
        let predicateMapResult = TreeSitterPredicateMapper.map(predicates)
        self.node = node
        self.index = index
        self.name = name
        self.byteRange = byteRange
        self.properties = predicateMapResult.properties
        self.textPredicates = predicateMapResult.textPredicates
        self.nameComponentCount = name.split(separator: ".").count
        self.bracketDepth = bracketDepth
    }
}

extension TreeSitterCapture: CustomDebugStringConvertible {
    var debugDescription: String {
        "[TreeSitterCapture byteRange=\(byteRange) name=\(name) properties=\(properties) textPredicates=\(textPredicates)]"
    }
}
