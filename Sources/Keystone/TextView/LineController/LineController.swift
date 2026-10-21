// swiftlint:disable file_length
import CoreGraphics
import CoreText
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

typealias LineFragmentTree = RedBlackTree<LineFragmentNodeID, Int, LineFragmentNodeData>

/// One text replacement in document coordinates: `range` was replaced by `replacementLength` units.
struct TextReplacement {
    let range: NSRange
    let replacementLength: Int
}

protocol LineControllerDelegate: AnyObject {
    func lineSyntaxHighlighter(for lineController: LineController) -> LineSyntaxHighlighter?
    func lineControllerDidInvalidateLineWidthDuringAsyncSyntaxHighlight(_ lineController: LineController)
}

final class LineController {
    /// Lines longer than this (UTF-16 units) are not syntax highlighted. They are also
    /// stored and typeset in chunks (see `chunkLength`); shorter lines are one chunk.
    nonisolated(unsafe) static var maximumHighlightedLineLength = 20_000
    /// Maximum size of one chunk of a long line, in UTF-16 units. An edit rebuilds the
    /// attributed string and `CTTypesetter` of the chunk containing it, not the whole line.
    nonisolated(unsafe) static var chunkLength = 8_192
    /// The attributed string from before the last edit, applied over the unchanged
    /// prefix and suffix of the new one until asynchronous highlighting replaces it.
    private var previousAttributedString: NSAttributedString?
    /// Length of the unchanged prefix after the last edit; typesetting resumes there.
    private var unchangedPrefixLength: Int?
    /// The single replacement (line-local, in the old text) since the string was last
    /// rebuilt, when that is known. Lets a chunked line skip comparing its whole text.
    private var pendingReplacement: TextReplacement?
    /// Indent guides for this line, applied to every fragment.
    var indentGuides = IndentGuideSpec.none {
        didSet {
            guard indentGuides != oldValue else { return }
            for (_, controller) in lineFragmentControllers {
                controller.indentGuides = indentGuides
            }
        }
    }

    private enum TypesetAmount {
        case inRect(CGRect)
        case toLocation(Int)
    }

    weak var delegate: LineControllerDelegate?
    let line: DocumentLineNode
    var lineFragmentHeightMultiplier: CGFloat = 1 {
        didSet {
            if lineFragmentHeightMultiplier != oldValue {
                typesetter.lineFragmentHeightMultiplier = lineFragmentHeightMultiplier
            }
        }
    }
    var theme: Theme = DefaultTheme() {
        didSet {
            syntaxHighlighter?.theme = theme
            applyThemeToAllLineFragmentControllers()
        }
    }
    var estimatedLineFragmentHeight: CGFloat = 15
    var tabWidth: CGFloat = 10
    var constrainingWidth: CGFloat {
        get {
            typesetter.constrainingWidth
        }
        set {
            typesetter.constrainingWidth = newValue
        }
    }
    var lineWidth: CGFloat {
        ceil(typesetter.maximumLineWidth)
    }
    var lineHeight: CGFloat {
        if let lineHeight = _lineHeight {
            return lineHeight
        } else if typesetter.lineFragments.isEmpty {
            let lineHeight = estimatedLineFragmentHeight * lineFragmentHeightMultiplier
            _lineHeight = lineHeight
            return lineHeight
        } else {
            let knownLineFragmentHeight = typesetter.typesetHeight
            let remainingNumberOfLineFragments = typesetter.bestGuessNumberOfLineFragments - typesetter.lineFragments.count
            let lineFragmentHeight = estimatedLineFragmentHeight * lineFragmentHeightMultiplier
            let remainingLineFragmentHeight = CGFloat(remainingNumberOfLineFragments) * lineFragmentHeight
            let lineHeight = knownLineFragmentHeight + remainingLineFragmentHeight
            _lineHeight = lineHeight
            return lineHeight
        }
    }
    var kern: CGFloat = 0 {
        didSet {
            if kern != oldValue {
                isDefaultAttributesInvalid = true
            }
        }
    }
    var lineBreakMode: LineBreakMode {
        get {
            typesetter.lineBreakMode
        }
        set {
            typesetter.lineBreakMode = newValue
        }
    }
    var numberOfLineFragments: Int {
        typesetter.lineFragments.count
    }
    var isFinishedTypesetting: Bool {
        typesetter.isFinishedTypesetting
    }
    /// The whole line's attributed text. Lines above `maximumHighlightedLineLength` are stored
    /// in chunks, so for them this concatenates on every call; prefer `chunks`.
    var attributedString: NSMutableAttributedString? {
        guard let first = chunks.first else {
            return nil
        }
        guard chunks.count > 1 else {
            return first.attributedString
        }
        let result = NSMutableAttributedString()
        for chunk in chunks {
            result.append(chunk.attributedString)
        }
        return result
    }
    /// The line's text in order; a single chunk unless the line is longer than `maximumHighlightedLineLength`.
    private(set) var chunks: [LineChunk] = []
    /// Whether `chunks` holds the line in pieces (set when the string is rebuilt).
    private var isChunkedLine = false

    private let stringView: StringView
    private let invisibleCharacterConfiguration: InvisibleCharacterConfiguration
    private let highlightService: HighlightService
    private let typesetter: LineTypesetter
    private var cachedSyntaxHighlighter: LineSyntaxHighlighter?
    private var lineFragmentControllers: [LineFragmentID: LineFragmentController] = [:]
    private var isLineFragmentCacheInvalid = true
    private var isStringInvalid = true
    private var isDefaultAttributesInvalid = true
    private var isSyntaxHighlightingInvalid = true
    private var isTypesetterInvalid = true
    private var _lineHeight: CGFloat?
    private var lineFragmentTree: LineFragmentTree
    private var syntaxHighlighter: LineSyntaxHighlighter? {
        if let cachedSyntaxHighlighter = cachedSyntaxHighlighter {
            return cachedSyntaxHighlighter
        } else if let syntaxHighlighter = delegate?.lineSyntaxHighlighter(for: self) {
            syntaxHighlighter.theme = theme
            cachedSyntaxHighlighter = syntaxHighlighter
            return syntaxHighlighter
        } else {
            return nil
        }
    }

    init(line: DocumentLineNode,
         stringView: StringView,
         invisibleCharacterConfiguration: InvisibleCharacterConfiguration,
         highlightService: HighlightService) {
        self.line = line
        self.stringView = stringView
        self.invisibleCharacterConfiguration = invisibleCharacterConfiguration
        self.highlightService = highlightService
        self.typesetter = LineTypesetter(lineID: line.id.rawValue)
        let rootLineFragmentNodeData = LineFragmentNodeData(lineFragment: nil)
        self.lineFragmentTree = LineFragmentTree(minimumValue: 0, rootValue: 0, rootData: rootLineFragmentNodeData)
    }

    func prepareToDisplayString(in rect: CGRect, syntaxHighlightAsynchronously: Bool) {
        prepareToDisplayString(.inRect(rect), syntaxHighlightAsynchronously: syntaxHighlightAsynchronously)
    }

    func prepareToDisplayString(toLocation location: Int, syntaxHighlightAsynchronously: Bool) {
        prepareToDisplayString(.toLocation(location), syntaxHighlightAsynchronously: syntaxHighlightAsynchronously)
    }

    func cancelSyntaxHighlighting() {
        syntaxHighlighter?.cancel()
    }

    func invalidateEverything() {
        pendingReplacement = nil
        isLineFragmentCacheInvalid = true
        isStringInvalid = true
        isTypesetterInvalid = true
        isDefaultAttributesInvalid = true
        isSyntaxHighlightingInvalid = true
        _lineHeight = nil
    }

    /// Like `invalidateEverything()`, for a text replacement whose extent is known. The
    /// replacement is remembered only when it is the sole change since the string was
    /// last built; otherwise the next rebuild compares old and new text.
    func invalidateEverything(replacing replacement: TextReplacement) {
        let wasStringInvalid = isStringInvalid
        invalidateEverything()
        if !wasStringInvalid {
            pendingReplacement = replacement
        }
    }

    func invalidateSyntaxHighlighter() {
        cachedSyntaxHighlighter = nil
    }

    func invalidateSyntaxHighlighting() {
        isTypesetterInvalid = true
        isDefaultAttributesInvalid = true
        isSyntaxHighlightingInvalid = true
        _lineHeight = nil
    }

    func lineFragmentControllers(in rect: CGRect) -> [LineFragmentController] {
        let lineYPosition = line.yPosition
        let localMinY = rect.minY - lineYPosition
        let localMaxY = rect.maxY - lineYPosition
        let query = LineFragmentFrameQuery(range: localMinY ... localMaxY)
        return lineFragmentControllers(matching: query)
    }

    func lineFragmentNode(containingCharacterAt location: Int) -> LineFragmentNode? {
        // RedBlackTree.node(containingLocation:) now returns nil for out-of-bounds locations
        // instead of crashing, so this gracefully handles temporarily stale structures
        lineFragmentTree.node(containingLocation: location)
    }

    func lineFragmentNode(atIndex index: Int) -> LineFragmentNode {
        lineFragmentTree.node(atIndex: index)
    }

    func setNeedsDisplayOnLineFragmentViews() {
        for (_, lineFragmentController) in lineFragmentControllers {
            lineFragmentController.lineFragmentView?.setNeedsDisplay()
        }
    }

    func setMarkedTextOnLineFragments(_ range: NSRange?) {
        for (_, lineFragmentController) in lineFragmentControllers {
            let lineFragment = lineFragmentController.lineFragment
            if let range = range, range.overlaps(lineFragment.visibleRange) {
                lineFragmentController.markedRange = range
            } else {
                lineFragmentController.markedRange = nil
            }
        }
    }
}

private extension LineController {
    private func prepareToDisplayString(_ typesetAmount: TypesetAmount, syntaxHighlightAsynchronously: Bool) {
        prepareString(syntaxHighlightAsynchronously: syntaxHighlightAsynchronously)
        typesetLineFragments(typesetAmount)
    }

    private func prepareString(syntaxHighlightAsynchronously: Bool) {
        syntaxHighlighter?.cancel()
        clearLineFragmentControllersIfNecessary()
        updateStringIfNecessary()
        updateDefaultAttributesIfNecessary()
        updateSyntaxHighlightingIfNecessary(async: syntaxHighlightAsynchronously)
        updateTypesetterIfNecessary()
    }

    private func typesetLineFragments(_ typesetAmount: TypesetAmount) {
        let newLineFragments: [LineFragment]
        switch typesetAmount {
        case .inRect(let rect):
            newLineFragments = typesetter.typesetLineFragments(in: rect)
        case .toLocation(let location):
            // When typesetting to a location we'll typeset an additional line fragment to ensure that we can display the text surrounding that location.
            newLineFragments = typesetter.typesetLineFragments(toLocation: location, additionalLineFragmentCount: 1)
        }
        updateLineHeight(for: newLineFragments)
    }

    private func clearLineFragmentControllersIfNecessary() {
        if isLineFragmentCacheInvalid {
            lineFragmentControllers.removeAll(keepingCapacity: true)
            isLineFragmentCacheInvalid = false
        }
    }

    private func updateStringIfNecessary() {
        guard isStringInvalid else {
            return
        }
        let length = line.data.totalLength
        let range = NSRange(location: line.location, length: length)
        let shouldChunk = length > LineController.maximumHighlightedLineLength
        if shouldChunk && isChunkedLine && !chunks.isEmpty && updateChunksAroundEdit(newLength: length) {
            // Only the chunks overlapping the edit were rebuilt; `unchangedPrefixLength` is set.
            previousAttributedString = nil
        } else if let string = stringView.substring(in: range) {
            let old = isChunkedLine ? nil : chunks.first?.attributedString
            if shouldChunk {
                chunks = LineChunk.chunks(of: string, startingAt: 0, chunkLength: LineController.chunkLength)
            } else {
                chunks = [LineChunk(location: 0, string: string)]
            }
            isChunkedLine = shouldChunk
            if let old {
                unchangedPrefixLength = LineController.commonPrefixLength(old.string as NSString, string as NSString)
                // Keep the old attributes around: when highlighting is asynchronous the new
                // string shows them on the unchanged text until fresh captures land, instead
                // of flashing to plain text on every keystroke.
                let highlightable = syntaxHighlighter?.canHighlight == true && !shouldChunk
                previousAttributedString = highlightable ? old : nil
            } else {
                unchangedPrefixLength = nil
                previousAttributedString = nil
            }
            isDefaultAttributesInvalid = true
        } else {
            chunks = []
            isChunkedLine = false
            unchangedPrefixLength = nil
            previousAttributedString = nil
        }
        // A hint describes exactly one rebuild; never let it outlive this one.
        pendingReplacement = nil
        isStringInvalid = false
        isSyntaxHighlightingInvalid = true
        isTypesetterInvalid = true
    }

    /// Reconciles the existing chunks of a long line with the edited text: finds the unchanged
    /// prefix and suffix, rebuilds only the chunks overlapping the edited region and shifts the
    /// ones after it. Returns `false` when the chunks cannot be reconciled and the caller must
    /// rebuild the whole line.
    private func updateChunksAroundEdit(newLength: Int) -> Bool {
        let backing = stringView.string
        let lineLocation = line.location
        guard lineLocation >= 0, newLength > 0, lineLocation + newLength <= backing.length else {
            return false
        }
        let oldLength = chunks.last.map(\.range.upperBound) ?? 0
        let delta = newLength - oldLength
        let replacement = pendingReplacement
        pendingReplacement = nil

        var prefix = 0
        var suffix = 0
        if let replacement,
           replacement.range.location >= 0,
           replacement.range.upperBound <= oldLength,
           oldLength - replacement.range.length + replacement.replacementLength == newLength {
            // The one edit since the last rebuild is known: no need to compare a megabyte of text.
            prefix = replacement.range.location
            suffix = oldLength - replacement.range.upperBound
        } else {
            (prefix, suffix) = unchangedPrefixAndSuffix(in: backing, lineLocation: lineLocation, oldLength: oldLength, newLength: newLength)
        }

        // Chunks overlapping the edited region [prefix, oldLength - suffix) in the old text.
        func chunkIndex(containing offset: Int) -> Int {
            if offset >= oldLength { return chunks.count - 1 }
            return chunks.firstIndex { offset < $0.range.upperBound } ?? chunks.count - 1
        }
        let first = chunkIndex(containing: prefix)
        let oldEditEnd = oldLength - suffix
        var last = oldEditEnd > prefix ? chunkIndex(containing: oldEditEnd - 1) : first
        last = max(first, last)
        let regionLocation = chunks[first].location
        var newRegionLength = chunks[last].range.upperBound - regionLocation + delta
        // A region that shrank to a sliver would make a sliver of a soft-wrap line; fold the next chunk in.
        if newRegionLength < LineController.chunkLength / 4 && last + 1 < chunks.count {
            last += 1
            newRegionLength += chunks[last].length
        }
        guard newRegionLength >= 0 else {
            return false
        }
        var pieces: [LineChunk] = []
        if newRegionLength > 0 {
            let newRange = NSRange(location: lineLocation + regionLocation, length: newRegionLength)
            guard let string = stringView.substring(in: newRange) else {
                return false
            }
            pieces = LineChunk.chunks(of: string, startingAt: regionLocation, chunkLength: LineController.chunkLength)
        }
        if delta != 0 {
            for chunk in chunks[(last + 1)...] {
                chunk.location += delta
            }
        }
        chunks.replaceSubrange(first...last, with: pieces)
        guard let lastChunk = chunks.last, lastChunk.range.upperBound == newLength else {
            return false
        }
        unchangedPrefixLength = prefix
        return true
    }

    /// Lengths of the unchanged prefix and suffix between the old chunks and the line's new text.
    private func unchangedPrefixAndSuffix(in backing: NSString, lineLocation: Int, oldLength: Int, newLength: Int) -> (prefix: Int, suffix: Int) {
        let delta = newLength - oldLength
        var prefix = 0
        for chunk in chunks {
            let comparable = min(chunk.length, newLength - chunk.location)
            guard comparable > 0 else { break }
            let common = LineController.commonLength(
                chunk.string, NSRange(location: 0, length: comparable),
                backing, NSRange(location: lineLocation + chunk.location, length: comparable),
                fromEnd: false
            )
            prefix = chunk.location + common
            if common < chunk.length { break }
        }

        var suffix = 0
        let maximumSuffix = min(oldLength, newLength) - prefix
        for chunk in chunks.reversed() where suffix < maximumSuffix {
            let comparable = min(chunk.length, maximumSuffix - suffix)
            let newUpperBound = lineLocation + chunk.range.upperBound + delta
            let common = LineController.commonLength(
                chunk.string, NSRange(location: chunk.length - comparable, length: comparable),
                backing, NSRange(location: newUpperBound - comparable, length: comparable),
                fromEnd: true
            )
            suffix += common
            if common < comparable { break }
        }
        return (prefix, suffix)
    }

    private func updateDefaultAttributesIfNecessary() {
        let applyToAll = isDefaultAttributesInvalid
        guard applyToAll || chunks.contains(where: \.needsDefaultAttributes) else {
            return
        }
        let defaultStringAttributes = DefaultStringAttributes(
            textColor: theme.textColor,
            font: theme.font,
            kern: kern,
            tabWidth: tabWidth
        )
        for chunk in chunks where applyToAll || chunk.needsDefaultAttributes {
            defaultStringAttributes.apply(to: chunk.attributedString)
            chunk.needsDefaultAttributes = false
            chunk.invalidateTypesetter()
        }
        if let previous = previousAttributedString, let input = createLineSyntaxHighlightInput() {
            LineController.carryOverAttributes(from: previous, to: input.attributedString, prefixLength: unchangedPrefixLength)
        }
        previousAttributedString = nil
        isDefaultAttributesInvalid = false
        isSyntaxHighlightingInvalid = true
        isTypesetterInvalid = true
    }

    private func updateTypesetterIfNecessary() {
        if isTypesetterInvalid {
            // After an edit, fragments before the edit are still right; keep them (and their
            // tree nodes) and resume after them instead of typesetting a long line from its
            // start on every keystroke.
            let reusable = unchangedPrefixLength.map { typesetter.reusableFragmentCount(forEditAt: $0) } ?? 0
            unchangedPrefixLength = nil
            if reusable > 0 && reusable <= lineFragmentTree.nodeTotalCount {
                // The tree nodes after the kept fragments are left in place: the next typesetting
                // pass updates them in place (`updateLineHeight(for:)`) and trims whatever is left,
                // which is far cheaper than removing and re-inserting them.
                typesetter.reset(keepingFragments: reusable)
                _lineHeight = nil
            } else {
                lineFragmentTree.reset(rootValue: 0, rootData: LineFragmentNodeData(lineFragment: nil))
                typesetter.reset()
            }
            if !isChunkedLine {
                // Highlighting mutates the single chunk's attributes in place.
                chunks.first?.invalidateTypesetter()
            }
            let stringLength = chunks.last.map(\.range.upperBound) ?? 0
            typesetter.prepareToTypeset(chunks: chunks, stringLength: stringLength)
            isTypesetterInvalid = false
        }
    }

    private func updateSyntaxHighlightingIfNecessary(async: Bool) {
        guard isSyntaxHighlightingInvalid else {
            return
        }
        guard let syntaxHighlighter = syntaxHighlighter else {
            return
        }
        // Highlighting rebuilds attributes for every token on the line, so a
        // multi-hundred-KB minified line stalls on each keystroke. Plain text
        // beyond the cap, as VS Code does with editor.maxTokenizationLineLength.
        guard line.data.totalLength <= LineController.maximumHighlightedLineLength else {
            isSyntaxHighlightingInvalid = false
            return
        }
        guard syntaxHighlighter.canHighlight else {
            isSyntaxHighlightingInvalid = false
            return
        }
        guard let input = createLineSyntaxHighlightInput() else {
            isSyntaxHighlightingInvalid = false
            return
        }
        if async {
            syntaxHighlighter.syntaxHighlight(input) { [weak self] result in
                if case .success = result, let self = self {
                    let oldWidth = self.lineWidth
                    self.isSyntaxHighlightingInvalid = false
                    self.isTypesetterInvalid = true
                    self.redisplayLineFragments()
                    if abs(self.lineWidth - oldWidth) > CGFloat.ulpOfOne {
                        self.delegate?.lineControllerDidInvalidateLineWidthDuringAsyncSyntaxHighlight(self)
                    }
                }
            }
        } else {
            syntaxHighlighter.cancel()
            syntaxHighlighter.syntaxHighlight(input)
            isSyntaxHighlightingInvalid = false
            isTypesetterInvalid = true
        }
    }

    private func updateLineHeight(for lineFragments: [LineFragment]) {
        var previousNode: LineFragmentNode?
        for lineFragment in lineFragments {
            let length = lineFragment.range.length
            let data = LineFragmentNodeData(lineFragment: lineFragment)
            if lineFragment.index < lineFragmentTree.nodeTotalCount {
                let node = previousNode.map { $0.next } ?? lineFragmentTree.node(atIndex: lineFragment.index)
                let heightDifference = abs(lineFragment.scaledSize.height - node.data.lineFragmentHeight)
                if heightDifference > CGFloat.ulpOfOne {
                    _lineHeight = nil
                }
                let valueChanged = node.value != length
                node.value = length
                node.data.lineFragment = lineFragment
                node.updateTotalLineFragmentHeight()
                if valueChanged {
                    lineFragmentTree.updateAfterChangingChildren(of: node)
                }
                previousNode = node
            } else if let thisPreviousNode = previousNode {
                let newNode = lineFragmentTree.insertNode(value: length, data: data, after: thisPreviousNode)
                newNode.updateTotalLineFragmentHeight()
                previousNode = newNode
                _lineHeight = nil
            } else {
                let thisPreviousNode = lineFragmentTree.node(atIndex: lineFragment.index - 1)
                let newNode = lineFragmentTree.insertNode(value: length, data: data, after: thisPreviousNode)
                newNode.updateTotalLineFragmentHeight()
                previousNode = newNode
                _lineHeight = nil
            }
        }
        // The tree mirrors the typesetter's fragments (plus the root when there are none);
        // drop nodes left over from before an edit.
        let expectedCount = max(1, typesetter.lineFragments.count)
        while lineFragmentTree.nodeTotalCount > expectedCount {
            lineFragmentTree.remove(lineFragmentTree.node(atIndex: lineFragmentTree.nodeTotalCount - 1))
            _lineHeight = nil
        }
    }

    private func createLineSyntaxHighlightInput() -> LineSyntaxHighlighterInput? {
        // Chunked lines are never highlighted (they are above `maximumHighlightedLineLength`).
        guard !isChunkedLine, let chunk = chunks.first else {
            return nil
        }
        return LineSyntaxHighlighterInput(attributedString: chunk.attributedString, byteRange: line.data.totalByteRange)
    }

    private func lineFragmentController(for lineFragment: LineFragment) -> LineFragmentController {
        if let lineFragmentController = lineFragmentControllers[lineFragment.id] {
            lineFragmentController.lineFragment = lineFragment
            return lineFragmentController
        } else {
            let lineFragmentController = LineFragmentController(
                lineFragment: lineFragment,
                invisibleCharacterConfiguration: invisibleCharacterConfiguration
            )
            lineFragmentController.delegate = self
            lineFragmentController.indentGuides = indentGuides
            lineFragmentControllers[lineFragment.id] = lineFragmentController
            applyTheme(to: lineFragmentController)
            return lineFragmentController
        }
    }

    private func redisplayLineFragments() {
        let typesetLength = typesetter.typesetLength
        _lineHeight = nil
        updateTypesetterIfNecessary()
        let newLineFragments = typesetter.typesetLineFragments(toLocation: typesetLength)
        updateLineHeight(for: newLineFragments)
        reapplyLineFragmentToLineFragmentControllers()
        setNeedsDisplayOnLineFragmentViews()
    }

    private func reapplyLineFragmentToLineFragmentControllers() {
        for (_, lineFragmentController) in lineFragmentControllers {
            let lineFragmentID = lineFragmentController.lineFragment.id
            if let lineFragment = typesetter.lineFragment(withID: lineFragmentID) {
                lineFragmentController.lineFragment = lineFragment
            }
        }
    }

    private func lineFragmentControllers<T: RedBlackTreeSearchQuery>(matching query: T)
    -> [LineFragmentController] where T.NodeID == LineFragmentNodeID, T.NodeValue == Int, T.NodeData == LineFragmentNodeData {
        let queryResult = lineFragmentTree.search(using: query)
        return queryResult.compactMap { match in
            if let lineFragment = match.node.data.lineFragment {
                return lineFragmentController(for: lineFragment)
            } else {
                return nil
            }
        }
    }

    private func applyThemeToAllLineFragmentControllers() {
        for (_, lineFragmentController) in lineFragmentControllers {
            applyTheme(to: lineFragmentController)
        }
    }

    private func applyTheme(to lineFragmentController: LineFragmentController) {
        lineFragmentController.markedTextBackgroundColor = theme.markedTextBackgroundColor
        lineFragmentController.markedTextBackgroundCornerRadius = theme.markedTextBackgroundCornerRadius
    }

    private func lineFragment(closestTo point: CGPoint) -> LineFragment? {
        var closestLineFragment = typesetter.lineFragments.last
        for lineFragment in typesetter.lineFragments {
            let lineMaxY = lineFragment.yPosition + lineFragment.scaledSize.height
            if point.y <= lineMaxY {
                closestLineFragment = lineFragment
                break
            }
        }
        return closestLineFragment
    }
}

// MARK: - UITextInput
extension LineController {
    func caretRect(atIndex lineLocalLocation: Int) -> CGRect {
        // First check existing line fragments
        for lineFragment in typesetter.lineFragments {
            if let caretLocation = lineFragment.caretLocation(forLineLocalLocation: lineLocalLocation) {
                let xPosition = lineFragment.xOffset(forLineLocalIndex: caretLocation)
                let yPosition = lineFragment.yPosition + (lineFragment.scaledSize.height - lineFragment.baseSize.height) / 2
                return CGRect(x: xPosition, y: yPosition, width: Caret.width, height: lineFragment.baseSize.height)
            }
        }

        // If not found, try limited on-demand typesetting for find/replace navigation
        // Limit to 50KB ahead to avoid hanging on very large lines (e.g., Command+A on 5M chars)
        let maxTypesetAhead = 50_000
        let lastTypesetLocation = typesetter.lineFragments.last?.visibleRange.upperBound ?? 0
        let distanceToTarget = lineLocalLocation - lastTypesetLocation

        if distanceToTarget > 0 && distanceToTarget <= maxTypesetAhead {
            let newLineFragments = typesetter.typesetLineFragments(toLocation: lineLocalLocation, additionalLineFragmentCount: 1)
            updateLineHeight(for: newLineFragments)

            // Try again with the newly typeset fragments
            for lineFragment in typesetter.lineFragments {
                if let caretLocation = lineFragment.caretLocation(forLineLocalLocation: lineLocalLocation) {
                    let xPosition = lineFragment.xOffset(forLineLocalIndex: caretLocation)
                    let yPosition = lineFragment.yPosition + (lineFragment.scaledSize.height - lineFragment.baseSize.height) / 2
                    return CGRect(x: xPosition, y: yPosition, width: Caret.width, height: lineFragment.baseSize.height)
                }
            }
        }

        // Fallback: use estimated position based on last typeset fragment
        // This handles very distant positions (like Command+A on huge lines) without hanging
        if let lastFragment = typesetter.lineFragments.last {
            let avgCharsPerFragment = max(1, lastFragment.visibleRange.length)
            let fragmentHeight = lastFragment.scaledSize.height
            let estimatedFragmentsAhead = CGFloat(distanceToTarget) / CGFloat(avgCharsPerFragment)
            let estimatedY = lastFragment.yPosition + fragmentHeight + (estimatedFragmentsAhead * fragmentHeight)
            let yPosition = estimatedY + (fragmentHeight * lineFragmentHeightMultiplier - fragmentHeight) / 2
            return CGRect(x: 0, y: yPosition, width: Caret.width, height: fragmentHeight)
        }

        let yPosition = (estimatedLineFragmentHeight * lineFragmentHeightMultiplier - estimatedLineFragmentHeight) / 2
        return CGRect(x: 0, y: yPosition, width: Caret.width, height: estimatedLineFragmentHeight)
    }

    func firstRect(for lineLocalRange: NSRange) -> CGRect {
        for lineFragment in typesetter.lineFragments {
            if let caretRange = lineFragment.caretRange(forLineLocalRange: lineLocalRange) {
                let finalIndex = min(lineFragment.visibleRange.upperBound, caretRange.upperBound)
                let xStart = lineFragment.xOffset(forLineLocalIndex: caretRange.location)
                let xEnd = lineFragment.xOffset(forLineLocalIndex: finalIndex)
                let yPosition = lineFragment.yPosition + (lineFragment.scaledSize.height - lineFragment.baseSize.height) / 2
                return CGRect(x: xStart, y: yPosition, width: xEnd - xStart, height: lineFragment.baseSize.height)
            }
        }
        return CGRect(x: 0, y: 0, width: 0, height: estimatedLineFragmentHeight * lineFragmentHeightMultiplier)
    }

    func closestIndex(to point: CGPoint) -> Int {
        guard let closestLineFragment = lineFragment(closestTo: point) else {
            return line.location
        }
        let localLocation = min(closestLineFragment.lineLocalIndex(forPosition: point), line.data.length)
        return line.location + localLocation
    }
}

// MARK: - LineFragmentControllerDelegate
extension LineController: LineFragmentControllerDelegate {
    func string(in controller: LineFragmentController) -> String? {
        let lineFragment = controller.lineFragment
        let range = NSRange(location: line.location + lineFragment.visibleRange.location, length: lineFragment.visibleRange.length)
        return stringView.substring(in: range)
    }
}

extension LineController {
    /// Length of the common prefix of two strings, in UTF-16 units.
    static func commonPrefixLength(_ a: NSString, _ b: NSString) -> Int {
        let maxCommon = min(a.length, b.length)
        return commonLength(a, NSRange(location: 0, length: maxCommon), b, NSRange(location: 0, length: maxCommon), fromEnd: false)
    }

    /// Number of equal UTF-16 units of `aRange` in `a` and `bRange` in `b` (which must have the
    /// same length), counted from their starts, or from their ends when `fromEnd` is set.
    static func commonLength(_ a: NSString, _ aRange: NSRange, _ b: NSString, _ bRange: NSRange, fromEnd: Bool) -> Int {
        let maxCommon = min(aRange.length, bRange.length)
        guard maxCommon > 0 else { return 0 }
        let chunk = 4096
        var common = 0
        var bufferA = [unichar](repeating: 0, count: chunk)
        var bufferB = [unichar](repeating: 0, count: chunk)
        while common < maxCommon {
            let length = min(chunk, maxCommon - common)
            let rangeA: NSRange
            let rangeB: NSRange
            if fromEnd {
                rangeA = NSRange(location: aRange.upperBound - common - length, length: length)
                rangeB = NSRange(location: bRange.upperBound - common - length, length: length)
            } else {
                rangeA = NSRange(location: aRange.location + common, length: length)
                rangeB = NSRange(location: bRange.location + common, length: length)
            }
            a.getCharacters(&bufferA, range: rangeA)
            b.getCharacters(&bufferB, range: rangeB)
            // memcmp first: a per-unit Swift loop over a megabyte is slow in debug builds.
            let blockIsEqual = memcmp(bufferA, bufferB, length * MemoryLayout<unichar>.stride) == 0
            var i = length
            if !blockIsEqual {
                i = 0
                if fromEnd {
                    while i < length && bufferA[length - 1 - i] == bufferB[length - 1 - i] { i += 1 }
                } else {
                    while i < length && bufferA[i] == bufferB[i] { i += 1 }
                }
            }
            common += i
            if i < length { break }
        }
        return common
    }

    /// Copies `previous`'s attribute runs onto `target` over their common prefix and
    /// suffix, so a single edit keeps the rest of the line's highlighting.
    static func carryOverAttributes(from previous: NSAttributedString, to target: NSMutableAttributedString, prefixLength: Int? = nil) {
        let old = previous.string as NSString
        let new = target.string as NSString
        let oldLength = old.length
        let newLength = new.length
        let maxCommon = min(oldLength, newLength)
        guard maxCommon > 0 else { return }
        let prefix = min(prefixLength ?? commonPrefixLength(old, new), maxCommon)
        var suffix = 0
        while suffix < maxCommon - prefix && old.character(at: oldLength - 1 - suffix) == new.character(at: newLength - 1 - suffix) {
            suffix += 1
        }
        target.beginEditing()
        if prefix > 0 {
            previous.enumerateAttributes(in: NSRange(location: 0, length: prefix), options: []) { attributes, range, _ in
                target.setAttributes(attributes, range: range)
            }
        }
        if suffix > 0 {
            let shift = newLength - oldLength
            previous.enumerateAttributes(in: NSRange(location: oldLength - suffix, length: suffix), options: []) { attributes, range, _ in
                target.setAttributes(attributes, range: NSRange(location: range.location + shift, length: range.length))
            }
        }
        target.endEditing()
    }
}
