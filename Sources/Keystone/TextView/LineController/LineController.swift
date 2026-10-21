// swiftlint:disable file_length
import CoreGraphics
import CoreText
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

typealias LineFragmentTree = RedBlackTree<LineFragmentNodeID, Int, LineFragmentNodeData>

protocol LineControllerDelegate: AnyObject {
    func lineSyntaxHighlighter(for lineController: LineController) -> LineSyntaxHighlighter?
    func lineControllerDidInvalidateLineWidthDuringAsyncSyntaxHighlight(_ lineController: LineController)
}

final class LineController {
    /// Lines longer than this (UTF-16 units) are not syntax highlighted.
    nonisolated(unsafe) static var maximumHighlightedLineLength = 20_000
    /// The attributed string from before the last edit, applied over the unchanged
    /// prefix and suffix of the new one until asynchronous highlighting replaces it.
    private var previousAttributedString: NSAttributedString?
    /// Length of the unchanged prefix after the last edit; typesetting resumes there.
    private var unchangedPrefixLength: Int?
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
            let knownLineFragmentHeight = typesetter.lineFragments.reduce(0) { $0 + $1.scaledSize.height }
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
    private(set) var attributedString: NSMutableAttributedString?

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
        isLineFragmentCacheInvalid = true
        isStringInvalid = true
        isTypesetterInvalid = true
        isDefaultAttributesInvalid = true
        isSyntaxHighlightingInvalid = true
        _lineHeight = nil
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
        if isStringInvalid {
            let range = NSRange(location: line.location, length: line.data.totalLength)
            let old = attributedString
            if let string = stringView.substring(in: range) {
                attributedString = NSMutableAttributedString(string: string)
                if let old {
                    unchangedPrefixLength = LineController.commonPrefixLength(old.string as NSString, string as NSString)
                    // Keep the old attributes around: when highlighting is asynchronous the new
                    // string shows them on the unchanged text until fresh captures land, instead
                    // of flashing to plain text on every keystroke.
                    let highlightable = syntaxHighlighter?.canHighlight == true && line.data.totalLength <= LineController.maximumHighlightedLineLength
                    previousAttributedString = highlightable ? old : nil
                } else {
                    unchangedPrefixLength = nil
                    previousAttributedString = nil
                }
            } else {
                attributedString = nil
            }
            isStringInvalid = false
            isDefaultAttributesInvalid = true
            isSyntaxHighlightingInvalid = true
            isTypesetterInvalid = true
        }
    }

    private func updateDefaultAttributesIfNecessary() {
        if isDefaultAttributesInvalid {
            if let input = createLineSyntaxHighlightInput() {
                let defaultStringAttributes = DefaultStringAttributes(
                    textColor: theme.textColor,
                    font: theme.font,
                    kern: kern,
                    tabWidth: tabWidth
                )
                defaultStringAttributes.apply(to: input.attributedString)
                if let previous = previousAttributedString {
                    LineController.carryOverAttributes(from: previous, to: input.attributedString, prefixLength: unchangedPrefixLength)
                }
            }
            previousAttributedString = nil
            isDefaultAttributesInvalid = false
            isSyntaxHighlightingInvalid = true
            isTypesetterInvalid = true
        }
    }

    private func updateTypesetterIfNecessary() {
        if isTypesetterInvalid {
            // After an edit, fragments before the edit are still right; keep them (and their
            // tree nodes) and resume after them instead of typesetting a long line from its
            // start on every keystroke.
            let reusable = unchangedPrefixLength.map { typesetter.reusableFragmentCount(forEditAt: $0) } ?? 0
            unchangedPrefixLength = nil
            if reusable > 0 && reusable <= lineFragmentTree.nodeTotalCount {
                while lineFragmentTree.nodeTotalCount > reusable {
                    lineFragmentTree.remove(lineFragmentTree.node(atIndex: lineFragmentTree.nodeTotalCount - 1))
                }
                typesetter.reset(keepingFragments: reusable)
                _lineHeight = nil
            } else {
                lineFragmentTree.reset(rootValue: 0, rootData: LineFragmentNodeData(lineFragment: nil))
                typesetter.reset()
            }
            if let attributedString = attributedString {
                typesetter.prepareToTypeset(attributedString)
            }
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
                let node = lineFragmentTree.node(atIndex: lineFragment.index)
                let heightDifference = abs(lineFragment.baseSize.height - node.data.lineFragmentHeight)
                if heightDifference > CGFloat.ulpOfOne {
                    _lineHeight = nil
                }
                node.value = length
                node.data.lineFragment = lineFragment
                node.updateTotalLineFragmentHeight()
                lineFragmentTree.updateAfterChangingChildren(of: node)
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
    }

    private func createLineSyntaxHighlightInput() -> LineSyntaxHighlighterInput? {
        if let attributedString = attributedString {
            let byteRange = line.data.totalByteRange
            return LineSyntaxHighlighterInput(attributedString: attributedString, byteRange: byteRange)
        } else {
            return nil
        }
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
                let xPosition = CTLineGetOffsetForStringIndex(lineFragment.line, caretLocation, nil)
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
                    let xPosition = CTLineGetOffsetForStringIndex(lineFragment.line, caretLocation, nil)
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
                let xStart = CTLineGetOffsetForStringIndex(lineFragment.line, caretRange.location, nil)
                let xEnd = CTLineGetOffsetForStringIndex(lineFragment.line, finalIndex, nil)
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
        let localLocation = min(CTLineGetStringIndexForPosition(closestLineFragment.line, point), line.data.length)
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
    /// Copies `previous`'s attribute runs onto `target` over their common prefix and
    /// suffix, so a single edit keeps the rest of the line's highlighting.
    /// Length of the common prefix of two strings, in UTF-16 units.
    static func commonPrefixLength(_ a: NSString, _ b: NSString) -> Int {
        let maxCommon = min(a.length, b.length)
        guard maxCommon > 0 else { return 0 }
        let chunk = 4096
        var prefix = 0
        var bufferA = [unichar](repeating: 0, count: chunk)
        var bufferB = [unichar](repeating: 0, count: chunk)
        while prefix < maxCommon {
            let length = min(chunk, maxCommon - prefix)
            let range = NSRange(location: prefix, length: length)
            a.getCharacters(&bufferA, range: range)
            b.getCharacters(&bufferB, range: range)
            var i = 0
            while i < length && bufferA[i] == bufferB[i] { i += 1 }
            prefix += i
            if i < length { break }
        }
        return prefix
    }

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
