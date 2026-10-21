import Foundation

/// The text the layers read while querying: the live buffer, or a snapshot while a
/// background parse runs so the parser never reads text the main thread is editing.
final class TreeSitterTextSource {
    let live: StringView
    var snapshot: StringView?
    var current: StringView { snapshot ?? live }

    init(live: StringView) {
        self.live = live
    }
}

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
    var injectionByteRange: ByteRange?
    var injectionLanguageName: String?

    private let parser: TreeSitterParser
    private let textSource: TreeSitterTextSource
    private var stringView: StringView { textSource.current }
    private var childLanguageLayerStore = TreeSitterLanguageLayerStore()
    var childLanguageLayers: [TreeSitterLanguageLayer] { childLanguageLayerStore.allLayers }
    var textSourceString: NSString { textSource.current.string }
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
         textSource: TreeSitterTextSource) {
        self.language = language
        self.languageProvider = languageProvider
        self.parser = parser
        self.textSource = textSource
    }
}

// MARK: - Parsing
extension TreeSitterLanguageLayer {
    /// Full parse of `text`, replacing every layer. Used on load.
    func parse(_ text: NSString) {
        parse([], from: text)
    }

    /// Synchronous edit: adjusts the trees for `edit` and reparses.
    /// - Returns: Changed byte ranges in document coordinates.
    func apply(_ edit: TreeSitterInputEdit) -> [ByteRange] {
        applyEditWithoutReparse(edit)
        return reparse(parsing: [], window: Self.window(for: edit))
    }

    /// Adjusts every layer's tree for `edit` without parsing, so node positions stay
    /// right until a (possibly background) reparse lands.
    func applyEditWithoutReparse(_ edit: TreeSitterInputEdit) {
        tree?.apply(edit)
        for entry in childLanguageLayerStore.allEntries {
            entry.layer.applyEditWithoutReparse(edit)
            if let range = entry.layer.injectionByteRange {
                entry.layer.injectionByteRange = Self.shift(range, for: edit)
            }
        }
    }

    /// The bytes `edit` touched, in post-edit coordinates.
    static func window(for edit: TreeSitterInputEdit) -> ByteRange {
        ByteRange(from: edit.startByte, to: max(edit.newEndByte, edit.startByte))
    }

    /// Maps a byte range from before `edit` to after it.
    static func shift(_ range: ByteRange, for edit: TreeSitterInputEdit) -> ByteRange {
        let delta = edit.newEndByte - edit.oldEndByte
        if range.upperBound < edit.startByte {
            return range
        }
        if range.lowerBound >= edit.oldEndByte {
            return ByteRange(from: range.lowerBound + delta, to: range.upperBound + delta)
        }
        // Overlaps the edit: the start stays, the end moves with the replacement.
        let lower = min(range.lowerBound, edit.startByte)
        let upper = range.upperBound >= edit.oldEndByte ? range.upperBound + delta : edit.newEndByte
        return ByteRange(from: lower, to: max(lower, upper))
    }

    /// Reparses this layer (its tree must already reflect the edits) and updates its injections.
    /// - Parameters:
    ///   - ranges: Included ranges for an injected layer; empty for the root.
    ///   - window: Post-edit bytes around what changed. Large documents re-query injections
    ///     only inside it; `nil` re-queries everything.
    /// - Returns: Changed byte ranges in document coordinates.
    func reparse(parsing ranges: [TreeSitterTextRange], window: ByteRange?) -> [ByteRange] {
        let oldTree = tree
        prepareParser(toParse: ranges)
        tree = parser.parse(oldTree: oldTree)
        var changed: [ByteRange] = []
        var changedWindow: ByteRange?
        if let oldTree = oldTree, let newTree = tree {
            for changedRange in oldTree.rangesChanged(comparingTo: newTree) {
                let range = ByteRange(from: changedRange.startByte, to: changedRange.endByte)
                changed.append(range)
                changedWindow = changedWindow.map { $0.union(range) } ?? range
            }
        }
        changed += updateChildLayers(window: window, changedWindow: changedWindow)
        return changed
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
                textSource: textSource)
            childLanguageLayer.parentLanguageLayer = self
            childLanguageLayerStore.storeLayer(childLanguageLayer, forKey: id)
            return childLanguageLayer
        } else {
            return nil
        }
    }

    private func updateChildLayers(window: ByteRange?, changedWindow: ByteRange?) -> [ByteRange] {
        guard let injectionsQuery = language.injectionsQuery, let node = tree?.rootNode else {
            childLanguageLayerStore.removeAll()
            return []
        }
        if let window, stringView.string.length > Self.localInjectionUpdateThreshold {
            let fullWindow = changedWindow.map { window.union($0) } ?? window
            return updateChildLayersNearEdit(window: fullWindow, injectionsQuery: injectionsQuery, rootNode: node)
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
        var changed: [ByteRange] = []
        for injectedLanguage in injectedLanguages {
            if let childLanguageLayer = childLanguageLayer(withID: injectedLanguage.id, forLanguageNamed: injectedLanguage.languageName) {
                childLanguageLayer.injectionLanguageName = injectedLanguage.languageName
                childLanguageLayer.injectionByteRange = ByteRange(from: injectedLanguage.textRange.startByte, to: injectedLanguage.textRange.endByte)
                changed += childLanguageLayer.reparse(parsing: [injectedLanguage.textRange], window: window)
            }
        }
        return changed
    }

    /// Large-document variant of `updateChildLayers`. Running the injections query over
    /// the whole tree costs O(document) per keystroke, and the child layers away from
    /// the change can't have been affected, so only `window` is queried. Layers outside
    /// it were already adjusted by `applyEditWithoutReparse`.
    private func updateChildLayersNearEdit(
        window: ByteRange,
        injectionsQuery: TreeSitterQuery,
        rootNode: TreeSitterNode
    ) -> [ByteRange] {
        var changed: [ByteRange] = []

        // Layers the change may have replaced or resized.
        var affected: [(id: UnsafeRawPointer, layer: TreeSitterLanguageLayer, range: ByteRange)] = []
        for entry in childLanguageLayerStore.allEntries {
            guard let range = entry.layer.injectionByteRange else {
                affected.append((entry.id, entry.layer, ByteRange(from: ByteCount(0), to: ByteCount(0))))
                continue
            }
            if range.upperBound >= window.lowerBound && range.lowerBound <= window.upperBound {
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
            layer.injectionByteRange = injectedRange
            changed += layer.reparse(parsing: [injected.textRange], window: window)
        }

        // Layers around the change that no longer have a capture are gone.
        for entry in unclaimed {
            childLanguageLayerStore.removeLayer(forKey: entry.id)
        }
        for entry in childLanguageLayerStore.allEntries where entry.layer.isEmpty {
            childLanguageLayerStore.removeLayer(forKey: entry.id)
        }
        return changed
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
