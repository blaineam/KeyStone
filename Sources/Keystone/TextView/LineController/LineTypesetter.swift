import CoreGraphics
import CoreText
import Foundation

private final class TypesetResult {
    let lineFragments: [LineFragment]
    let lineFragmentsMap: [LineFragmentID: Int]
    let maximumLineWidth: CGFloat

    init(lineFragments: [LineFragment], lineFragmentsMap: [LineFragmentID: Int], maximumLineWidth: CGFloat) {
        self.lineFragments = lineFragments
        self.lineFragmentsMap = lineFragmentsMap
        self.maximumLineWidth = maximumLineWidth
    }
}

final class LineTypesetter {
    private enum TypesetEndCondition {
        case yPosition(_ targetYPosition: CGFloat)
        case characterIndex(_ targetCharacterIndex: Int)

        func shouldKeepTypesetting(currentYPosition: CGFloat, currentCharacterIndex: Int) -> Bool {
            switch self {
            case .yPosition(let targetYPosition):
                return currentYPosition < targetYPosition
            case .characterIndex(let targetCharacterIndex):
                return currentCharacterIndex < targetCharacterIndex
            }
        }
    }

    var lineBreakMode: LineBreakMode = .byWordWrapping
    var constrainingWidth: CGFloat = 0
    var lineFragmentHeightMultiplier: CGFloat = 1
    private(set) var lineFragments: [LineFragment] = []
    private(set) var maximumLineWidth: CGFloat = 0
    /// Sum of the scaled heights of `lineFragments`, kept incrementally.
    private(set) var typesetHeight: CGFloat = 0
    var bestGuessNumberOfLineFragments: Int {
        if startOffset >= stringLength {
            return lineFragments.count
        } else {
            let charactersPerLineFragment = Double(startOffset) / Double(lineFragments.count)
            let charactersRemaining = stringLength - startOffset
            let remainingNumberOfLineFragments = Int(ceil(Double(charactersRemaining) / charactersPerLineFragment))
            return lineFragments.count + remainingNumberOfLineFragments
        }
    }
    var isFinishedTypesetting: Bool {
        startOffset >= stringLength
    }
    var typesetLength: Int {
        startOffset
    }

    private let lineID: String
    private var stringLength = 0
    /// The line's text in pieces, each with its own typesetter. Fragments never cross a chunk.
    private var chunks: [LineChunk] = []
    private var lineFragmentsMap: [LineFragmentID: Int] = [:]
    /// Line-local offset where the next fragment starts.
    private var startOffset = 0
    private var nextYPosition: CGFloat = 0
    private var lineFragmentIndex = 0

    init(lineID: String) {
        self.lineID = lineID
    }

    func reset() {
        lineFragments = []
        maximumLineWidth = 0
        typesetHeight = 0
        stringLength = 0
        chunks = []
        lineFragmentsMap = [:]
        startOffset = 0
        nextYPosition = 0
        lineFragmentIndex = 0
    }

    /// Like `reset()`, but keeps the first `count` already typeset fragments. An edit
    /// deep inside a long line only changes fragments from the edit on; the ones
    /// before it are reused and typesetting resumes after them.
    func reset(keepingFragments count: Int) {
        guard count > 0, count <= lineFragments.count else {
            reset()
            return
        }
        // Truncate in place: thousands of fragments may be kept, so rebuilding the map
        // on every keystroke would cost more than the typesetting it saves.
        for fragment in lineFragments[count...] {
            lineFragmentsMap[fragment.id] = nil
            typesetHeight -= fragment.scaledSize.height
        }
        lineFragments.removeSubrange(count...)
        let last = lineFragments[count - 1]
        chunks = []
        stringLength = 0
        maximumLineWidth = lineFragments.reduce(0) { max($0, $1.scaledSize.width) }
        startOffset = last.range.upperBound
        nextYPosition = last.yPosition + last.scaledSize.height
        lineFragmentIndex = count
    }

    /// Number of leading fragments that stay valid when the text changes at `editOffset`:
    /// those ending before it, minus one for the fragment whose break looked past it.
    func reusableFragmentCount(forEditAt editOffset: Int) -> Int {
        // Fragments are in order, so find the first one ending after the edit by bisection.
        var low = 0
        var high = lineFragments.count
        while low < high {
            let mid = (low + high) / 2
            if lineFragments[mid].range.upperBound <= editOffset {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return max(0, low - 1)
    }

    /// Typeset `chunks`, which together hold the line's text in order; `stringLength` is their total length.
    func prepareToTypeset(chunks: [LineChunk], stringLength: Int) {
        self.chunks = chunks
        self.stringLength = stringLength
    }

    @discardableResult
    func typesetLineFragments(in rect: CGRect) -> [LineFragment] {
        let lineFragments = typesetLineFragments(until: .yPosition(rect.maxY))
        releaseChunksIfFinished()
        return lineFragments
    }

    @discardableResult
    func typesetLineFragments(toLocation location: Int, additionalLineFragmentCount: Int = 0) -> [LineFragment] {
        let lineFragments = typesetLineFragments(until: .characterIndex(location), additionalLineFragmentCount: additionalLineFragmentCount)
        releaseChunksIfFinished()
        return lineFragments
    }

    func lineFragment(withID lineFragmentID: LineFragmentID) -> LineFragment? {
        if let index = lineFragmentsMap[lineFragmentID] {
            return lineFragments[index]
        } else {
            return nil
        }
    }
}

private extension LineTypesetter {
    private func releaseChunksIfFinished() {
        // Once the whole line is typeset the typesetters are not needed until the next
        // invalidation; the chunks themselves stay with the line controller.
        if isFinishedTypesetting {
            for chunk in chunks {
                chunk.invalidateTypesetter()
            }
            chunks = []
        }
    }

    private func updateState(from typesetResult: TypesetResult) {
        lineFragments.append(contentsOf: typesetResult.lineFragments)
        for fragment in typesetResult.lineFragments {
            typesetHeight += fragment.scaledSize.height
        }
        for (id, index) in typesetResult.lineFragmentsMap {
            lineFragmentsMap[id] = index
        }
        maximumLineWidth = max(maximumLineWidth, typesetResult.maximumLineWidth)
    }

    /// The chunk containing the line-local `offset` (binary search).
    private func chunk(containing offset: Int) -> LineChunk? {
        var low = 0
        var high = chunks.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let chunk = chunks[mid]
            if offset < chunk.location {
                high = mid - 1
            } else if offset >= chunk.location + chunk.length {
                low = mid + 1
            } else {
                return chunk
            }
        }
        return nil
    }

    private func typesetLineFragments(until condition: TypesetEndCondition, additionalLineFragmentCount: Int = 0) -> [LineFragment] {
        guard !chunks.isEmpty, constrainingWidth > 0 else {
            return []
        }
        var maximumLineWidth: CGFloat = 0
        var lineFragments: [LineFragment] = []
        var lineFragmentsMap: [LineFragmentID: Int] = [:]
        var remainingAdditionalLineFragmentCount = additionalLineFragmentCount
        let conditionAllowsKeepTypesetting = condition.shouldKeepTypesetting(currentYPosition: nextYPosition, currentCharacterIndex: startOffset)
        var shouldKeepTypesetting = conditionAllowsKeepTypesetting || remainingAdditionalLineFragmentCount > 0
        while startOffset < stringLength && shouldKeepTypesetting, let chunk = chunk(containing: startOffset), let lineFragment = makeNextLineFragment(in: chunk) {
            lineFragments.append(lineFragment)
            nextYPosition += lineFragment.scaledSize.height
            startOffset += lineFragment.range.length
            if lineFragment.scaledSize.width > maximumLineWidth {
                maximumLineWidth = lineFragment.scaledSize.width
            }
            lineFragmentsMap[lineFragment.id] = lineFragmentIndex
            lineFragmentIndex += 1
            if condition.shouldKeepTypesetting(currentYPosition: nextYPosition, currentCharacterIndex: startOffset) {
                shouldKeepTypesetting = true
            } else if remainingAdditionalLineFragmentCount > 0 {
                shouldKeepTypesetting = true
                remainingAdditionalLineFragmentCount -= 1
            } else {
                shouldKeepTypesetting = false
            }
        }
        let typesetResult = TypesetResult(lineFragments: lineFragments, lineFragmentsMap: lineFragmentsMap, maximumLineWidth: maximumLineWidth)
        updateState(from: typesetResult)
        return typesetResult.lineFragments
    }

    private func makeNextLineFragment(in chunk: LineChunk) -> LineFragment? {
        let typesetter = chunk.typesetter
        let chunkLocalStart = startOffset - chunk.location
        // suggestNextLineBreak(in:) uses CTTypesetterSuggestLineBreak but it may return lines that are longer than our constraining width.
        // In that case we keep removeing characters from the line until we're below the constraining width.
        var length = suggestNextLineBreak(in: chunk, startingAt: chunkLocalStart)
        var lineFragment: LineFragment?
        while lineFragment == nil || lineFragment!.scaledSize.width > constrainingWidth {
            let visibleRange = CFRangeMake(chunkLocalStart, length)
            lineFragment = makeLineFragment(for: visibleRange, in: typesetter, stringOffset: chunk.location, lineFragmentIndex: lineFragmentIndex, yPosition: nextYPosition)
            length -= 1
        }
        guard let lineFragment else {
            return nil
        }
        let whitespaceLength = lengthOfWhitespace(after: chunkLocalStart + length, in: chunk.string)
        guard whitespaceLength > 0 else {
            return lineFragment
        }
        return lineFragment.withHiddenLength(whitespaceLength)
    }

    private func suggestNextLineBreak(in chunk: LineChunk, startingAt chunkLocalStart: Int) -> Int {
        let lineBreakSuggester = LineBreakSuggester(
            lineBreakMode: lineBreakMode,
            typesetter: chunk.typesetter,
            attributedString: chunk.attributedString,
            constrainingWidth: constrainingWidth
        )
        return lineBreakSuggester.suggestLineBreak(startingAt: chunkLocalStart)
    }

    private func lengthOfWhitespace(after location: Int, in string: NSString) -> Int {
        let stringLength = string.length
        guard location < stringLength - 1 else {
            return 0
        }
        var nextCharacter = location + 1
        var length = 0
        while nextCharacter < stringLength && string.isWhitespaceCharacter(at: nextCharacter) {
            nextCharacter += 1
            length += 1
        }
        return length
    }

    private func makeLineFragment(
        for visibleRange: CFRange,
        in typesetter: CTTypesetter,
        stringOffset: Int,
        lineFragmentIndex: Int,
        yPosition: CGFloat
    ) -> LineFragment {
        let line = CTTypesetterCreateLine(typesetter, visibleRange)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let height = ascent + descent + leading
        let baseSize = CGSize(width: width, height: height)
        let scaledSize = CGSize(width: width, height: height * lineFragmentHeightMultiplier)
        let id = LineFragmentID(lineId: lineID, lineFragmentIndex: lineFragmentIndex)
        let visibleRange = NSRange(location: visibleRange.location + stringOffset, length: visibleRange.length)
        return LineFragment(
            id: id,
            index: lineFragmentIndex,
            visibleRange: visibleRange,
            line: line,
            stringOffset: stringOffset,
            descent: descent,
            baseSize: baseSize,
            scaledSize: scaledSize,
            yPosition: yPosition
        )
    }
}
