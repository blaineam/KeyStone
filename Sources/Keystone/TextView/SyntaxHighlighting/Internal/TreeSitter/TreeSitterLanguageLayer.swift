import Foundation

final class TreeSitterLanguageLayer {
    typealias LayerAndNodeTuple = (layer: TreeSitterLanguageLayer, node: TreeSitterNode)

    let language: TreeSitterInternalLanguage
    private(set) var tree: TreeSitterTree?
    var canHighlight: Bool {
        parser.language != nil && tree != nil
    }

    /// Documents with more UTF-16 units than this only re-query injections near an edit
    /// instead of walking the whole syntax tree on every keystroke.
    nonisolated(unsafe) static var localInjectionUpdateThreshold = 200_000

    /// Where this layer was injected in the parent, in current document bytes. Nil for the root layer.
    private(set) var injectionByteRange: ByteRange?
    var injectionLanguageName: String?

    private let lineManager: LineManager
    private let parser: TreeSitterParser
    private let stringView: StringView
    private var childLanguageLayerStore = TreeSitterLanguageLayerStore()
    private weak var parentLanguageLayer: TreeSitterLanguageLayer?
    private let languageProvider: TreeSitterLanguageProvider?
    private var isEmpty: Bool {
        if let rootNode = tree?.rootNode {
            return rootNode.endByte - rootNode.startByte <= ByteCount(0)
        } else {
            return true
        }
    }

    init(language: TreeSitterInternalLanguage,
         languageProvider: TreeSitterLanguageProvider?,
         parser: TreeSitterParser,
         stringView: StringView,
         lineManager: LineManager) {
        self.language = language
        self.languageProvider = languageProvider
        self.parser = parser
        self.stringView = stringView
        self.lineManager = lineManager
    }
}

// MARK: - Parsing
extension TreeSitterLanguageLayer {
    func parse(_ text: NSString) {
        let ranges = [tree?.rootNode.textRange].compactMap { $0 }
        parse(ranges, from: text)
    }

    func apply(_ edit: TreeSitterInputEdit) -> LineChangeSet {
        let ranges = [tree?.rootNode.textRange].compactMap { $0 }
        return apply(edit, parsing: ranges)
    }

    func layerAndNode(at linePosition: LinePosition) -> LayerAndNodeTuple? {
        let point = TreeSitterTextPoint(linePosition)
        guard let node = tree?.rootNode.descendantForRange(from: point, to: point) else {
            return nil
        }
        var result: LayerAndNodeTuple = (layer: self, node: node)
        for childLanguageLayer in childLanguageLayerStore.allLayers {
            if let childRootNode = childLanguageLayer.tree?.rootNode, childRootNode.contains(point) {
                if let childResult = childLanguageLayer.layerAndNode(at: linePosition) {
                    if childResult.node.byteRange.length < result.node.byteRange.length {
                        result = childResult
                    }
                }
            }
        }
        return result
    }

    private func apply(_ edit: TreeSitterInputEdit, parsing ranges: [TreeSitterTextRange] = []) -> LineChangeSet {
        // Apply edit to tree.
        let oldTree = tree
        tree?.apply(edit)
        prepareParser(toParse: ranges)
        tree = parser.parse(oldTree: tree)
        // Gather changed lines.
        let lineChangeSet = LineChangeSet()
        var changedByteWindow: ByteRange?
        if let oldTree = oldTree, let newTree = tree {
            let changedRanges = oldTree.rangesChanged(comparingTo: newTree)
            for changedRange in changedRanges {
                let range = ByteRange(from: changedRange.startByte, to: changedRange.endByte)
                changedByteWindow = changedByteWindow.map { $0.union(range) } ?? range
                let startRow = Int(changedRange.startPoint.row)
                let endRow = Int(changedRange.endPoint.row)
                for row in startRow ... endRow {
                    let line = lineManager.line(atRow: row)
                    lineChangeSet.markLineEdited(line)
                }
            }
        }
        let childLineChangeSet = updateChildLayers(applying: edit, changedByteWindow: changedByteWindow)
        lineChangeSet.union(with: childLineChangeSet)
        return lineChangeSet
    }

    private func prepareParser(toParse ranges: [TreeSitterTextRange]) {
        parser.language = language.languagePointer
        if !ranges.isEmpty && parentLanguageLayer != nil {
            parser.setIncludedRanges(ranges)
        } else {
            parser.removeAllIncludedRanges()
        }
    }

    private func parse(_ ranges: [TreeSitterTextRange], from text: NSString) {
        prepareParser(toParse: ranges)
        tree = parser.parse(text)
        childLanguageLayerStore.removeAll()
        guard let injectionsQuery = language.injectionsQuery, let node = tree?.rootNode else {
            return
        }
        let queryCursor = TreeSitterQueryCursor(query: injectionsQuery, node: node)
        queryCursor.execute()
        let captures = queryCursor.validCaptures(in: stringView)
        let injectedLanguages = injectedLanguages(from: captures)
        for injectedLanguage in injectedLanguages {
            if let childLanguageLayer = childLanguageLayer(withID: injectedLanguage.id, forLanguageNamed: injectedLanguage.languageName) {
                childLanguageLayer.injectionLanguageName = injectedLanguage.languageName
                childLanguageLayer.injectionByteRange = ByteRange(from: injectedLanguage.textRange.startByte, to: injectedLanguage.textRange.endByte)
                childLanguageLayer.parse([injectedLanguage.textRange], from: text)
            }
        }
    }
}

// MARK: - Syntax Highlighting
extension TreeSitterLanguageLayer {
    func captures(in range: ByteRange) -> [TreeSitterCapture] {
        guard !range.isEmpty else {
            return []
        }
        var captures = allValidCaptures(in: range)
        captures.sort(by: TreeSitterCapture.captureLayerSorting)
        return captures
    }

    private func allValidCaptures(in range: ByteRange) -> [TreeSitterCapture] {
        guard let tree = tree else {
            return []
        }
        guard let highlightsQuery = language.highlightsQuery else {
            return []
        }
        let queryCursor = TreeSitterQueryCursor(query: highlightsQuery, node: tree.rootNode)
        queryCursor.setQueryRange(range)
        queryCursor.execute()
        let captures = queryCursor.validCaptures(in: stringView)
        let capturesInChildren = childLanguageLayerStore.allLayers.reduce(into: []) { $0 += $1.allValidCaptures(in: range) }
        return captures + capturesInChildren
    }
}

// MARK: - Child Language Layers
private extension TreeSitterLanguageLayer {
    @discardableResult
    private func childLanguageLayer(withID id: UnsafeRawPointer, forLanguageNamed languageName: String) -> TreeSitterLanguageLayer? {
        if let childLanguageLayer = childLanguageLayerStore.layer(forKey: id) {
            return childLanguageLayer
        } else if let language = languageProvider?.treeSitterLanguage(named: languageName),
                  let internalLanguage = language.internalLanguage {
            let childLanguageLayer = TreeSitterLanguageLayer(
                language: internalLanguage,
                languageProvider: languageProvider,
                parser: parser,
                stringView: stringView,
                lineManager: lineManager)
            childLanguageLayer.parentLanguageLayer = self
            childLanguageLayerStore.storeLayer(childLanguageLayer, forKey: id)
            return childLanguageLayer
        } else {
            return nil
        }
    }

    private func updateChildLayers(applying edit: TreeSitterInputEdit, changedByteWindow: ByteRange?) -> LineChangeSet {
        guard let injectionsQuery = language.injectionsQuery, let node = tree?.rootNode else {
            childLanguageLayerStore.removeAll()
            return LineChangeSet()
        }
        if stringView.string.length > Self.localInjectionUpdateThreshold {
            return updateChildLayersNearEdit(applying: edit, changedByteWindow: changedByteWindow, injectionsQuery: injectionsQuery, rootNode: node)
        }
        let injectionsQueryCursor = TreeSitterQueryCursor(query: injectionsQuery, node: node)
        injectionsQueryCursor.execute()
        let captures = injectionsQueryCursor.validCaptures(in: stringView)
        let injectedLanguages = injectedLanguages(from: captures)
        let capturedIDs = injectedLanguages.map(\.id)
        let currentIDs = childLanguageLayerStore.allIDs
        for id in currentIDs {
            if !capturedIDs.contains(id) {
                // Remove languages that we no longer have any captures for.
                childLanguageLayerStore.removeLayer(forKey: id)
            } else if let rootNode = childLanguageLayerStore.layer(forKey: id)?.tree?.rootNode, rootNode.byteRange.length <= 0 {
                // Remove layers that no longer have any content.
                childLanguageLayerStore.removeLayer(forKey: id)
            }
        }
        // Update layers for current captures.
        let lineChangeSet = LineChangeSet()
        for injectedLanguage in injectedLanguages {
            if let childLanguageLayer = childLanguageLayer(withID: injectedLanguage.id, forLanguageNamed: injectedLanguage.languageName) {
                childLanguageLayer.injectionLanguageName = injectedLanguage.languageName
                childLanguageLayer.injectionByteRange = ByteRange(from: injectedLanguage.textRange.startByte, to: injectedLanguage.textRange.endByte)
                let childLineChangeSet = childLanguageLayer.apply(edit, parsing: [injectedLanguage.textRange])
                lineChangeSet.union(with: childLineChangeSet)
            }
        }
        return lineChangeSet
    }

    /// Large-document variant of `updateChildLayers`. Running the injections query over
    /// the whole tree costs O(document) per keystroke, and the child layers away from
    /// the edit can't have changed, so only the neighbourhood of the edit is queried.
    /// Layers the edit doesn't touch are just carried forward (and shifted).
    private func updateChildLayersNearEdit(
        applying edit: TreeSitterInputEdit,
        changedByteWindow: ByteRange?,
        injectionsQuery: TreeSitterQuery,
        rootNode: TreeSitterNode
    ) -> LineChangeSet {
        let lineChangeSet = LineChangeSet()
        let delta = edit.newEndByte - edit.oldEndByte

        // Everything that may have changed, in post-edit coordinates: the edit itself plus
        // whatever the incremental parse says changed structurally (an edit can invalidate
        // an injection outside its own span, e.g. by breaking the enclosing tag).
        var window = ByteRange(from: edit.startByte, to: max(edit.newEndByte, edit.startByte))
        if let changedByteWindow {
            window = window.union(changedByteWindow)
        }

        func postEdit(_ range: ByteRange) -> ByteRange {
            if range.lowerBound >= edit.oldEndByte {
                return ByteRange(from: range.lowerBound + delta, to: range.upperBound + delta)
            } else if range.upperBound >= edit.oldEndByte {
                return ByteRange(from: range.lowerBound, to: range.upperBound + delta)
            } else {
                return range
            }
        }

        // Split existing layers into those the change can't have touched and the rest.
        var affected: [(id: UnsafeRawPointer, layer: TreeSitterLanguageLayer, range: ByteRange)] = []
        for entry in childLanguageLayerStore.allEntries {
            guard let oldRange = entry.layer.injectionByteRange else {
                affected.append((entry.id, entry.layer, ByteRange(from: ByteCount(0), to: ByteCount(0))))
                continue
            }
            let range = postEdit(oldRange)
            if range.upperBound < window.lowerBound {
                // Entirely before the change: untouched.
            } else if range.lowerBound > window.upperBound {
                // Entirely after it: no reparse needed, only keep node offsets in step with the document.
                entry.layer.shiftForEditBeforeLayer(edit)
                entry.layer.setInjectionByteRange(range)
            } else {
                affected.append((entry.id, entry.layer, range))
            }
        }

        // Re-query only around the change (the tree is already post-edit).
        let queryCursor = TreeSitterQueryCursor(query: injectionsQuery, node: rootNode)
        queryCursor.setQueryRange(window)
        queryCursor.execute()
        let captures = queryCursor.validCaptures(in: stringView)
        let injectedLanguages = injectedLanguages(from: captures)

        var unclaimed = affected
        for injected in injectedLanguages {
            let injectedRange = ByteRange(from: injected.textRange.startByte, to: injected.textRange.endByte)
            let layer: TreeSitterLanguageLayer?
            if let existing = childLanguageLayerStore.layer(forKey: injected.id) {
                layer = existing
                unclaimed.removeAll { $0.id == injected.id }
            } else if let index = unclaimed.firstIndex(where: { candidate in
                // A layer around the edit gets a new node ID after the incremental parse
                // but is the same injection; adopt it so its tree isn't reparsed from scratch.
                candidate.layer.injectionLanguageName == injected.languageName
                    && candidate.layer.injectionByteRange != nil
                    && candidate.range.lowerBound <= injectedRange.upperBound
                    && injectedRange.lowerBound <= candidate.range.upperBound
            }) {
                let candidate = unclaimed.remove(at: index)
                childLanguageLayerStore.removeLayer(forKey: candidate.id)
                childLanguageLayerStore.storeLayer(candidate.layer, forKey: injected.id)
                layer = candidate.layer
            } else {
                layer = childLanguageLayer(withID: injected.id, forLanguageNamed: injected.languageName)
            }
            guard let layer else { continue }
            layer.injectionLanguageName = injected.languageName
            layer.setInjectionByteRange(injectedRange)
            lineChangeSet.union(with: layer.apply(edit, parsing: [injected.textRange]))
        }

        // Layers around the change that no longer have a capture are gone.
        for entry in unclaimed {
            childLanguageLayerStore.removeLayer(forKey: entry.id)
        }
        for entry in childLanguageLayerStore.allEntries where entry.layer.isEmpty {
            childLanguageLayerStore.removeLayer(forKey: entry.id)
        }
        return lineChangeSet
    }

    /// Applies an edit located before this layer to its tree (and nested layers) without reparsing.
    private func shiftForEditBeforeLayer(_ edit: TreeSitterInputEdit) {
        tree?.apply(edit)
        let delta = edit.newEndByte - edit.oldEndByte
        for entry in childLanguageLayerStore.allEntries {
            entry.layer.shiftForEditBeforeLayer(edit)
            if let range = entry.layer.injectionByteRange {
                entry.layer.setInjectionByteRange(ByteRange(from: range.lowerBound + delta, to: range.upperBound + delta))
            }
        }
    }

    private func setInjectionByteRange(_ range: ByteRange) {
        injectionByteRange = range
    }

    private func injectedLanguages(from captures: [TreeSitterCapture]) -> [TreeSitterInjectedLanguage] {
        let mapper = TreeSitterInjectedLanguageMapper(captures: captures)
        mapper.delegate = self
        return mapper.map()
    }
}

// MARK: - TreeSitterInjectedLanguageMapperDelegate
extension TreeSitterLanguageLayer: TreeSitterInjectedLanguageMapperDelegate {
    func treeSitterInjectedLanguageMapper(_ mapper: TreeSitterInjectedLanguageMapper, textIn textRange: TreeSitterTextRange) -> String? {
        let byteRange = ByteRange(from: textRange.startByte, to: textRange.endByte)
        let range = NSRange(byteRange)
        return stringView.substring(in: range)
    }
}

// MARK: - Debugging Language Layers
extension TreeSitterLanguageLayer {
    func languageHierarchyStringRepresentation() -> String {
        var str = ""
        if let rootNode = tree?.rootNode {
            str += "● [\(rootNode.byteRange.lowerBound) - \(rootNode.byteRange.upperBound)]"
        } else {
            str += "●"
        }
        if !childLanguageLayerStore.isEmpty {
            str += "\n"
            str += childLanguageHierarchy(indent: 1)
        }
        return str
    }

    private func childLanguageHierarchy(indent: Int) -> String {
        var str = ""
        let languageIDs = childLanguageLayerStore.allIDs
        for (idx, languageID) in languageIDs.enumerated() {
            let indentStr = String(repeating: "  ", count: indent)
            guard let childLanguageLayer = childLanguageLayerStore.layer(forKey: languageID) else { continue }
            if let rootNode = childLanguageLayer.tree?.rootNode {
                str += indentStr + "\(languageID) [\(rootNode.byteRange.lowerBound) - \(rootNode.byteRange.upperBound)]"
            } else {
                str += indentStr + "\(languageID)"
            }
            if !childLanguageLayer.childLanguageLayerStore.isEmpty {
                str += "\n"
                str += childLanguageLayer.childLanguageHierarchy(indent: indent + 1)
            }
            if idx < languageIDs.count - 1 {
                str += indentStr + "\n"
            }
        }
        return str
    }
}

extension TreeSitterLanguageLayer: CustomDebugStringConvertible {
    var debugDescription: String {
        "[TreeSitterLanguageLayer node=\(tree?.rootNode.debugDescription ?? "") childLanguageLayers=\(childLanguageLayerStore)]"
    }
}

private extension TreeSitterCapture {
    static func captureLayerSorting(_ lhs: TreeSitterCapture, _ rhs: TreeSitterCapture) -> Bool {
        // We sort the captures by three parameters:
        // 1. The location. Captures that are early in the text should be sorted first.
        // 2. The length of the capture. If two captures start at the same location, then we sort the longest capture first.
        //    Short captures that start at that location adds another "layer" of capturing on top of a previous capture.
        // 3. The number of components in the name. E.g. "variable.builtin" is sorted after "variable" as the styling of "variable.builtin"
        //    should be applied after applying the styling of "variable", since it's a specialization.
        if lhs.byteRange.location < rhs.byteRange.location {
            return true
        } else if lhs.byteRange.location > rhs.byteRange.location {
            return false
        } else if lhs.byteRange.length > rhs.byteRange.length {
            return true
        } else if lhs.byteRange.length < rhs.byteRange.length {
            return false
        } else {
            return lhs.nameComponentCount < rhs.nameComponentCount
        }
    }
}

private extension TreeSitterNode {
    func contains(_ point: TreeSitterTextPoint) -> Bool {
        let containsStart = point.row > startPoint.row || (point.row == startPoint.row && point.column >= startPoint.column)
        let containsEnd = point.row < endPoint.row || (point.row == endPoint.row && point.column <= endPoint.column)
        return containsStart && containsEnd
    }
}
